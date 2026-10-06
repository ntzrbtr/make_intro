import SwiftUI

/// Window for creating, editing and deleting presets.
struct PresetEditor: View {
    static let windowID = "presets"

    @EnvironmentObject private var store: PresetStore
    @State private var selection: UUID?
    @State private var sampleTitle = String(localized: "Sample Title")
    @State private var pendingDeletion: Preset?

    var body: some View {
        // Fixed sidebar instead of NavigationSplitView so the preset list cannot be collapsed.
        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.presets) { preset in
                    Text(preset.name).tag(preset.id)
                }
                .onMove { store.presets.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    listButtons
                }
            }
            .frame(width: 200)

            Divider()

            Group {
                if let id = selection, store.preset(withID: id) != nil {
                    detail(for: binding(for: id))
                } else {
                    Text("No preset selected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selection == nil { selection = store.presets.first?.id }
        }
        .confirmationDialog(
            "Delete preset “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { preset in
            Button("Delete", role: .destructive) { delete(preset) }
        } message: { _ in
            Text("This cannot be undone.")
        }
    }

    private var listButtons: some View {
        HStack(spacing: 2) {
            Button {
                selection = store.add().id
            } label: {
                Image(systemName: "plus").frame(width: 20, height: 18)
            }
            .help("New preset")

            Button {
                pendingDeletion = store.preset(withID: selection)
            } label: {
                Image(systemName: "minus").frame(width: 20, height: 18)
            }
            .help("Delete preset")
            .disabled(selection == nil || store.presets.count <= 1)

            Button {
                if let id = selection { selection = store.duplicate(id)?.id }
            } label: {
                Image(systemName: "plus.square.on.square").frame(width: 20, height: 18)
            }
            .help("Duplicate preset")
            .disabled(selection == nil)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(8)
    }

    private func detail(for preset: Binding<Preset>) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Form {
                    TextField("Name", text: preset.name)
                    TextField("Sample title", text: $sampleTitle, axis: .vertical)
                        .lineLimit(1...3)
                }
                .formStyle(.grouped)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, -20)

                PosterPreview(title: sampleTitle, settings: preset.wrappedValue.settings)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(minWidth: 360)

            Divider()

            SettingsView(settings: preset.settings)
                .frame(width: 340)
        }
    }

    /// Binds by ID instead of index so deleting/moving doesn't leave stale indices behind.
    private func binding(for id: UUID) -> Binding<Preset> {
        Binding(
            get: { store.preset(withID: id) ?? Preset(name: "") },
            set: { updated in
                if let index = store.presets.firstIndex(where: { $0.id == id }) {
                    store.presets[index] = updated
                }
            })
    }

    private func delete(_ preset: Preset) {
        guard let index = store.presets.firstIndex(where: { $0.id == preset.id }) else { return }
        store.delete(preset.id)
        selection = store.presets[min(index, store.presets.count - 1)].id
    }
}
