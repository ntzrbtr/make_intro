import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Invisible layer over the window that accepts only video files via drag and drop.
/// It sits above all controls so that e.g. the title field doesn't take the file path as text.
/// Mouse clicks pass through it (hitTest returns nil); drag and drop is not affected by that.
struct VideoDropTarget: NSViewRepresentable {
    var isEnabled: Bool
    @Binding var isTargeted: Bool
    var onDrop: (URL) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.isEnabled = isEnabled
        view.onTargetedChange = { targeted in
            if isTargeted != targeted { isTargeted = targeted }
        }
        view.onDrop = onDrop
    }

    static func isVideo(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .movie) ?? false
    }

    final class DropView: NSView {
        var isEnabled = true
        var onTargetedChange: (Bool) -> Void = { _ in }
        var onDrop: (URL) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// Exactly one file, and it must be a video – otherwise the drop is rejected.
        private func videoURL(from info: NSDraggingInfo) -> URL? {
            guard isEnabled,
                  let urls = info.draggingPasteboard.readObjects(
                      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  urls.count == 1, let url = urls.first, VideoDropTarget.isVideo(url)
            else { return nil }
            return url
        }

        private func evaluate(_ info: NSDraggingInfo) -> NSDragOperation {
            let accepted = videoURL(from: info) != nil
            onTargetedChange(accepted)
            return accepted ? .copy : []
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
        override func draggingExited(_ sender: NSDraggingInfo?) { onTargetedChange(false) }
        override func draggingEnded(_ sender: NSDraggingInfo) { onTargetedChange(false) }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            videoURL(from: sender) != nil
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            onTargetedChange(false)
            guard let url = videoURL(from: sender) else { return false }
            onDrop(url)
            return true
        }
    }
}
