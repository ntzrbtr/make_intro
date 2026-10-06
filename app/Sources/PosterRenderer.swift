import AppKit
import CoreText
import ImageIO

/// Loads images downscaled and keeps them in memory so the live preview stays responsive.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let maxPixelSize = 4096
    private var cache: [URL: CGImage] = [:]
    private let lock = NSLock()

    func image(at url: URL) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[url] { return cached }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        cache[url] = image
        return image
    }
}

enum PosterRenderer {
    static func render(title: String, settings: IntroSettings, size: CGSize) -> CGImage? {
        let width = size.width.rounded()
        let height = size.height.rounded()
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: Int(width), height: Int(height),
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.interpolationQuality = .high

        // Background: color or image (aspect fill, center-cropped, optionally darkened)
        switch settings.backgroundKind {
        case .color:
            ctx.setFillColor(settings.backgroundColor.nsColor.cgColor)
            ctx.fill(canvas)
        case .image:
            ctx.setFillColor(.black)
            ctx.fill(canvas)
            if let url = settings.backgroundURL, let background = ImageLoader.shared.image(at: url) {
                ctx.draw(background, in: aspectFill(CGSize(width: background.width, height: background.height), in: canvas))
            }
            if settings.backgroundDim > 0 {
                ctx.setFillColor(CGColor(gray: 0, alpha: settings.backgroundDim / 100))
                ctx.fill(canvas)
            }
        }

        // Logo
        if let url = settings.logoURL, let logo = ImageLoader.shared.image(at: url) {
            let logoWidth = width * settings.logoWidth / 100
            let logoHeight = logoWidth * CGFloat(logo.height) / CGFloat(logo.width)
            let margin = width * settings.logoMargin / 100
            let x = settings.logoCorner.isLeft ? margin : width - margin - logoWidth
            let y = settings.logoCorner.isTop ? height - margin - logoHeight : margin
            ctx.draw(logo, in: CGRect(x: x, y: y, width: logoWidth, height: logoHeight))
        }

        // Title – a literal "\n" also becomes a line break
        let text = title.replacingOccurrences(of: "\\n", with: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ctx.makeImage() }

        let fontSize = max(1, height * settings.titleSize / 100)
        let font = NSFont(name: settings.fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: settings.titleColor.nsColor,
            .paragraphStyle: paragraph,
        ])

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let maxTextWidth = width * 0.9
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil, CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude), nil)
        let textHeight = ceil(fitted.height) + 2
        let textRect = CGRect(
            x: (width - maxTextWidth) / 2,
            y: (height - textHeight) / 2 + height * settings.titleOffset / 100,
            width: maxTextWidth,
            height: textHeight)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: textRect, transform: nil), nil)

        if settings.titleShadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.004), blur: height * 0.015,
                          color: CGColor(gray: 0, alpha: 0.75))
        }
        CTFrameDraw(frame, ctx)

        return ctx.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw IntroError.posterWriteFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IntroError.posterWriteFailed }
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - scaled.width / 2, y: rect.midY - scaled.height / 2,
                      width: scaled.width, height: scaled.height)
    }
}
