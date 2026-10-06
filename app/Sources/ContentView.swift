import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ExportModel: ObservableObject {
    /// Shared so the app delegate can ask before quitting during an export.
    static let shared = ExportModel()

    @Published var isRunning = false
    @Published var progress = 0.0
    @Published var errorMessage: String?
    @Published var result: ExportResult?

    private var task: Task<Void, Never>?

    func start(title: String, input: URL, destination: URL, settings: IntroSettings,
               onSuccess: @escaping (ExportResult) -> Void) {
        isRunning = true
        progress = 0
        errorMessage = nil
        result = nil

        task = Task {
            do {
                let result = try await IntroExporter.export(
                    title: title, input: input, destination: destination, settings: settings
                ) { value in
                    Task { @MainActor in self.progress = value }
                }
                self.result = result
                onSuccess(result)
            } catch is CancellationError {
                errorMessage = String(localized: "Cancelled.")
            } catch {
                errorMessage = Task.isCancelled ? String(localized: "Cancelled.") : error.localizedDescription
            }
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
    }

    func clearStatus() {
        guard !isRunning else { return }
        result = nil
        errorMessage = nil
    }
}

struct ContentView: View {
    private static let defaultVideoSize = CGSize(width: 1920, height: 1080)

    @EnvironmentObject private var presets: PresetStore
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var export = ExportModel.shared
    @State private var window: NSWindow?

    @State private var title = ""
    @State private var input: URL?
    @State private var videoSize = ContentView.defaultVideoSize
    @State private var isDropTargeted = false
    @AppStorage("destinationPath") private var lastDestinationPath = ""
    @AppStorage("selectedPresetID") private var selectedPresetID = ""

    /// The selected preset; falls back to the first one if the selected preset was deleted.
    private var preset: Preset {
        presets.preset(withID: UUID(uuidString: selectedPresetID)) ?? presets.presets[0]
    }

    private var canStart: Bool {
        !export.isRunning && input != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preset.settings.missingResources.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PosterPreview(title: title, settings: preset.settings, videoSize: videoSize)

            Form {
                TextField("Title", text: $title, prompt: Text("My Title"), axis: .vertical)
                    .lineLimit(1...4)
                    .help("Multiple lines with ⌥⏎ or \\n")

                LabeledContent("Preset") {
                    HStack {
                        Picker("Preset", selection: Binding(
                            get: { preset.id },
                            set: { selectedPresetID = $0.uuidString }
                        )) {
                            ForEach(presets.presets) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        Button("Edit…") { openWindow(id: PresetEditor.windowID) }
                    }
                }

                let missing = preset.settings.missingResources
                if !missing.isEmpty {
                    Label("Missing from preset: \(missing.formatted(.list(type: .and))). Please adjust the preset.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                LabeledContent("Video") {
                    HStack {
                        Group {
                            if let input {
                                Text(verbatim: input.lastPathComponent)
                            } else {
                                Text("Drag a video here or choose one")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        .truncationMode(.middle)
                        Spacer()
                        Button("Choose…", action: chooseVideo)
                    }
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(export.isRunning)
            .padding(.horizontal, -20)

            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: 3)
                .padding(4)
                .opacity(isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay {
            VideoDropTarget(isEnabled: !export.isRunning, isTargeted: $isDropTargeted, onDrop: setInput)
        }
        .background(WindowAccessor { window = $0 })
        // Closing the main window quits the app (the presets window alone doesn't keep it running).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window, notification.object as? NSWindow === window { NSApp.terminate(nil) }
        }
        // While exporting, the window can't be closed (this also blocks ⌘W).
        .onChange(of: export.isRunning) {
            if export.isRunning {
                window?.styleMask.remove(.closable)
            } else {
                window?.styleMask.insert(.closable)
            }
        }
        .onChange(of: title) {
            // Hide the last export's message only once a new title is typed
            if !title.isEmpty { export.clearStatus() }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if export.isRunning {
                ProgressView(value: export.progress)
                    .frame(maxWidth: 240)
                Text(export.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if let result = export.result {
                Label("Created “\(result.video.lastPathComponent)”", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if let message = export.errorMessage {
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()

            if export.isRunning {
                Button("Cancel", action: export.cancel)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Create Intro…", action: chooseDestinationAndStart)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
            }
        }
    }

    // MARK: Actions

    /// Asks for the destination folder, then starts the export.
    private func chooseDestinationAndStart() {
        guard canStart else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Where should the intro be saved?")
        panel.prompt = String(localized: "Save Here")
        if !lastDestinationPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: lastDestinationPath)
        }

        let handle = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let destination = panel.url else { return }
            lastDestinationPath = destination.path
            startExport(to: destination)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    private func startExport(to destination: URL) {
        guard let input else { return }
        export.start(title: title, input: input, destination: destination, settings: preset.settings) { result in
            NSWorkspace.shared.activateFileViewerSelecting([result.video])
            resetForm()
        }
    }

    /// Resets the state for the next video (the selected preset stays).
    private func resetForm() {
        title = ""
        input = nil
        videoSize = Self.defaultVideoSize
    }

    private func setInput(_ url: URL) {
        input = url
        export.clearStatus()
        Task {
            guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                  let (size, transform) = try? await track.load(.naturalSize, .preferredTransform)
            else { return }
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            videoSize = CGSize(width: abs(rect.width), height: abs(rect.height))
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { setInput(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            setInput(url)
        }
    }
}

/// Gives access to the NSWindow hosting a SwiftUI view.
private struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { WindowView(onWindow: onWindow) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
