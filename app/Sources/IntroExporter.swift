import AVFoundation
import CoreImage

enum IntroError: LocalizedError {
    case noVideoTrack
    case posterRenderFailed
    case posterWriteFailed
    case exportUnavailable
    case missingResources([String])

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: String(localized: "The input file contains no video track.")
        case .posterRenderFailed: String(localized: "The poster could not be created.")
        case .posterWriteFailed: String(localized: "The poster could not be saved.")
        case .exportUnavailable: String(localized: "Export is not available for this file.")
        case .missingResources(let names):
            String(localized: "Missing from preset: \(names.formatted(.list(type: .and))).")
        }
    }
}

struct ExportResult {
    let folder: URL
    let video: URL
}

enum IntroExporter {
    /// Prepends the poster as an intro to the video and shifts the audio tracks accordingly.
    static func export(
        title: String,
        input: URL,
        destination: URL,
        settings: IntroSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportResult {
        let missing = settings.missingResources
        guard missing.isEmpty else { throw IntroError.missingResources(missing) }

        let asset = AVURLAsset(url: input)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw IntroError.noVideoTrack
        }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio)
        let (naturalSize, transform, minFrameDuration, videoRange) = try await sourceVideo.load(
            .naturalSize, .preferredTransform, .minFrameDuration, .timeRange)

        let renderSize = orientedSize(naturalSize, transform)
        guard let poster = PosterRenderer.render(title: title, settings: settings, size: renderSize) else {
            throw IntroError.posterRenderFailed
        }

        // Output: <destination>/<name>/<name>.{png,mp4} (without the subfolder if disabled)
        let name = input.deletingPathExtension().lastPathComponent
        let folder = settings.createSubfolder ? destination.appendingPathComponent(name, isDirectory: true) : destination
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if settings.savePoster {
            try PosterRenderer.writePNG(poster, to: folder.appendingPathComponent("\(name).png"))
        }
        let output = folder.appendingPathComponent("\(name).mp4")

        // Composition: insert the source at 0, then insert empty time for the intro in front of it
        let introTime = CMTime(seconds: settings.introDuration, preferredTimescale: 600)
        let introRange = CMTimeRange(start: .zero, duration: introTime)
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw IntroError.exportUnavailable
        }
        try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
        videoTrack.insertEmptyTimeRange(introRange)

        for source in sourceAudio {
            guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let audioRange = try await source.load(.timeRange)
            try audioTrack.insertTimeRange(audioRange, of: source, at: .zero)
            audioTrack.insertEmptyTimeRange(introRange)
        }

        let instruction = IntroInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration),
            trackID: videoTrack.trackID,
            poster: CIImage(cgImage: poster),
            sourceTransform: transform,
            naturalSize: naturalSize,
            renderSize: renderSize,
            introDuration: settings.introDuration,
            fadeIn: settings.fadeIn,
            crossfade: settings.crossfade)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = IntroCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = minFrameDuration.isValid && minFrameDuration.seconds > 0
            ? minFrameDuration : CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: composition, presetName: settings.codec.exportPreset) else {
            throw IntroError.exportUnavailable
        }
        session.videoComposition = videoComposition

        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        let monitor = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }

        try await session.export(to: output, as: .mp4)
        progress(1)
        return ExportResult(folder: folder, video: output)
    }

    private static func orientedSize(_ size: CGSize, _ transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
    }
}

// MARK: - Video compositor

final class IntroInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let trackID: CMPersistentTrackID
    let poster: CIImage
    let frameTransform: CGAffineTransform
    let introDuration: Double
    let fadeIn: Double
    let crossfade: Double

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, poster: CIImage,
         sourceTransform: CGAffineTransform, naturalSize: CGSize, renderSize: CGSize,
         introDuration: Double, fadeIn: Double, crossfade: Double) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.poster = poster
        self.introDuration = introDuration
        self.fadeIn = fadeIn
        self.crossfade = crossfade
        // preferredTransform uses a top-left origin, Core Image a bottom-left one.
        // Some files rotate without a translation, so move the result back to the origin.
        let rotated = CGRect(origin: .zero, size: naturalSize).applying(sourceTransform)
        let normalized = sourceTransform.concatenating(CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY))
        let flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: naturalSize.height)
        let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderSize.height)
        self.frameTransform = flipIn.concatenating(normalized).concatenating(flipOut)
    }

    /// Poster opacity: full during the intro, then optionally cross-fading into the video.
    func posterOpacity(at time: Double) -> Double {
        if time < introDuration { return 1 }
        guard crossfade > 0 else { return 0 }
        return max(0, 1 - (time - introDuration) / crossfade)
    }

    /// Opacity of the black fade at the start.
    func blackOpacity(at time: Double) -> Double {
        guard fadeIn > 0, time < fadeIn else { return 0 }
        return 1 - time / fadeIn
    }
}

final class IntroCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixelAttributes: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    let sourcePixelBufferAttributes: [String: any Sendable]? = IntroCompositor.pixelAttributes
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = IntroCompositor.pixelAttributes

    // Render without color management so video and poster colors pass through unchanged.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? IntroInstruction,
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "MakeIntro", code: 1))
            return
        }

        let time = request.compositionTime.seconds
        let extent = CGRect(origin: .zero, size: request.renderContext.size)
        var image = CIImage(color: .black).cropped(to: extent)

        if let frame = request.sourceFrame(byTrackID: instruction.trackID) {
            var source = CIImage(cvPixelBuffer: frame)
            if !instruction.frameTransform.isIdentity {
                source = source.transformed(by: instruction.frameTransform)
            }
            image = source.composited(over: image)
        }

        let posterOpacity = instruction.posterOpacity(at: time)
        if posterOpacity > 0 {
            image = withOpacity(instruction.poster, posterOpacity).composited(over: image)
        }

        let blackOpacity = instruction.blackOpacity(at: time)
        if blackOpacity > 0 {
            image = withOpacity(CIImage(color: .black).cropped(to: extent), blackOpacity).composited(over: image)
        }

        context.render(image.cropped(to: extent), to: output)
        request.finish(withComposedVideoFrame: output)
    }

    private func withOpacity(_ image: CIImage, _ opacity: Double) -> CIImage {
        guard opacity < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(opacity), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(opacity), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(opacity), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ])
    }
}
