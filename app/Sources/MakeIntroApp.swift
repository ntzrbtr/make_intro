import AppKit
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
            CommandGroup(replacing: .appInfo) { AboutMenuItem() }
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

/// "About Make Intro" menu item: the standard About panel with license note and website link.
/// The copyright line comes from NSHumanReadableCopyright in Info.plist.
private struct AboutMenuItem: View {
    private static let website = URL(string: "https://www.netzarbeiter.info")!

    var body: some View {
        Button("About Make Intro") {
            NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
            NSApp.activate()
        }
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,  // dynamic, readable in light and dark mode
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: String(localized: "Released under the MIT License.") + "\n", attributes: attributes)
        var link = attributes
        link[.link] = website
        credits.append(NSAttributedString(string: "www.netzarbeiter.info", attributes: link))
        return credits
    }
}
