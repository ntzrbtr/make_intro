import SwiftUI

@main
struct MakeIntroApp: App {
    @StateObject private var presets = PresetStore()

    var body: some Scene {
        Window("Make Intro", id: "main") {
            ContentView()
                .environmentObject(presets)
                .frame(minWidth: 640, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) { PresetsMenuItem() }
        }

        Window("Presets", id: PresetEditor.windowID) {
            PresetEditor()
                .environmentObject(presets)
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}

/// "Presets…" menu item (⌘,) – a separate view because openWindow is only available in views.
private struct PresetsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Presets…") { openWindow(id: PresetEditor.windowID) }
            .keyboardShortcut(",")
    }
}
