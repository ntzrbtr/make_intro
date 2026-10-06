import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var settings: IntroSettings
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Background") {
                Picker("Type", selection: $settings.backgroundKind) {
                    ForEach(BackgroundKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch settings.backgroundKind {
                case .color:
                    ColorPicker("Color", selection: Binding(
                        get: { settings.backgroundColor.color },
                        set: { settings.backgroundColor = RGBAColor($0) }),
                        supportsOpacity: false)
                case .image:
                    imageRow("Image", path: $settings.backgroundPath, placeholder: "No image chosen")
                    SliderRow("Darken", value: $settings.backgroundDim, in: 0...80, step: 1, unit: "%")
                }
            }

            Section("Logo") {
                imageRow("Image", path: $settings.logoPath, placeholder: "No logo") { settings.showLogo = true }
                Group {
                    Toggle("Show logo", isOn: $settings.showLogo)
                    Picker("Position", selection: $settings.logoCorner) {
                        ForEach(Corner.allCases) { Text($0.label).tag($0) }
                    }
                    SliderRow("Width", value: $settings.logoWidth, in: 2...30, step: 0.5, unit: "%")
                    SliderRow("Margin", value: $settings.logoMargin, in: 0...15, step: 0.5, unit: "%")
                }
                .disabled(settings.logoPath == nil)
            }

            Section("Title") {
                FontPicker(fontName: $settings.fontName)
                SliderRow("Size", value: $settings.titleSize, in: 3...25, step: 0.5, unit: "%")
                ColorPicker("Color", selection: Binding(
                    get: { settings.titleColor.color },
                    set: { settings.titleColor = RGBAColor($0) }))
                SliderRow("Position", value: $settings.titleOffset, in: -40...40, step: 1, unit: "%")
                Toggle("Shadow", isOn: $settings.titleShadow)
            }

            Section("Intro") {
                SliderRow("Duration", value: $settings.introDuration, in: 0.5...10, step: 0.5, unit: "s")
                SliderRow("Fade in", value: $settings.fadeIn, in: 0...3, step: 0.25, unit: "s")
                SliderRow("Cross-fade", value: $settings.crossfade, in: 0...3, step: 0.25, unit: "s")
            }

            Section("Output") {
                Picker("Codec", selection: $settings.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Save poster as PNG", isOn: $settings.savePoster)
                Toggle("Create subfolder", isOn: $settings.createSubfolder)
            }

            Section {
                Button("Reset to Defaults", role: .destructive) { settings = IntroSettings() }
            } footer: {
                Text("Sizes and margins are relative to the video size (width or height). Position moves the title up (+) or down (−) from the center.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("The image could not be imported",
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {}
        } message: {
            Text(verbatim: importError ?? "")
        }
    }

    private func imageRow(_ label: LocalizedStringKey, path: Binding<String?>, placeholder: LocalizedStringKey,
                          onChoose: @escaping () -> Void = {}) -> some View {
        LabeledContent(label) {
            HStack {
                if let reference = path.wrappedValue {
                    if !AssetStore.exists(reference) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Image not found – please choose it again.")
                    }
                    Text(verbatim: (reference as NSString).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        path.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove image")
                } else {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                }
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    do {
                        path.wrappedValue = try AssetStore.importFile(url)
                        onChoose()
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
        }
    }
}

private struct SliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    init(_ label: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(verbatim: "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

/// Font family and style picker for the fonts installed on this Mac.
private struct FontPicker: View {
    @Binding var fontName: String

    /// Placeholder entry for a font that is not (or no longer) installed.
    private static let missingTag = "\u{0}missing"

    @State private var families: [String] = []

    private var installedFamily: String? {
        NSFont(name: fontName, size: 12)?.familyName
    }

    private func members(of family: String) -> [(name: String, style: String)] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard let name = member.first as? String, let style = member.dropFirst().first as? String else { return nil }
            return (name, style)
        }
    }

    var body: some View {
        let family = installedFamily

        Picker("Font", selection: Binding(
            get: { family ?? Self.missingTag },
            set: { newFamily in
                guard newFamily != Self.missingTag else { return }
                let members = members(of: newFamily)
                fontName = members.first(where: { $0.style == "Regular" })?.name ?? members.first?.name ?? fontName
            }
        )) {
            if family == nil {
                Text("\(fontName) (missing)").tag(Self.missingTag)
                Divider()
            }
            ForEach(families, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        .onAppear(perform: loadFamilies)
        .onReceive(NotificationCenter.default.publisher(for: NSFont.fontSetChangedNotification)) { _ in
            loadFamilies()
        }

        if let family {
            Picker("Style", selection: $fontName) {
                ForEach(members(of: family), id: \.name) { Text(verbatim: $0.style).tag($0.name) }
            }
        } else {
            Label("This font is not installed on this Mac. Please install it or choose another one.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func loadFamilies() {
        families = NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
