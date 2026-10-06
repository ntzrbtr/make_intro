import SwiftUI

/// Live preview of the poster. Rendered at reduced resolution –
/// since all dimensions are relative, the result matches the export.
struct PosterPreview: View {
    let title: String
    let settings: IntroSettings
    var videoSize = CGSize(width: 1920, height: 1080)

    @State private var image: CGImage?

    private struct RenderKey: Hashable {
        let title: String
        let settings: IntroSettings
        let size: CGSize
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .aspectRatio(videoSize, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .frame(maxWidth: .infinity)
        .task(id: RenderKey(title: title, settings: settings, size: videoSize)) {
            await render()
        }
    }

    private func render() async {
        let scale = min(1, 1280 / max(videoSize.width, 1))
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        let title = title.isEmpty ? String(localized: "My Title") : title
        let settings = settings
        let rendered = await Task.detached(priority: .userInitiated) {
            PosterRenderer.render(title: title, settings: settings, size: size)
        }.value
        if !Task.isCancelled { image = rendered }
    }
}
