import AVFoundation
import AppKit
import CryptoKit
import SwiftUI

enum Corner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: Self { self }

    var label: String {
        switch self {
        case .topLeft: String(localized: "Top Left")
        case .topRight: String(localized: "Top Right")
        case .bottomLeft: String(localized: "Bottom Left")
        case .bottomRight: String(localized: "Bottom Right")
        }
    }

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case color, image

    var id: Self { self }
    var label: String { self == .color ? String(localized: "Color") : String(localized: "Image") }
}

enum VideoCodec: String, Codable, CaseIterable, Identifiable {
    case h264, hevc

    var id: Self { self }
    var label: String { self == .h264 ? "H.264" : "HEVC (H.265)" }

    var exportPreset: String {
        self == .h264 ? AVAssetExportPresetHighestQuality : AVAssetExportPresetHEVCHighestQuality
    }
}

struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let defaultBackground = RGBAColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// All settings for poster and video.
/// Sizes and distances are relative to the video size so the result looks the same at any resolution.
/// Images are references to copies in the asset folder (see AssetStore).
struct IntroSettings: Codable, Hashable {
    // Background: solid color or image
    var backgroundKind: BackgroundKind = .color
    var backgroundColor: RGBAColor = .defaultBackground
    var backgroundPath: String?
    var backgroundDim: Double = 0          // image darkening in %

    // Logo (nothing is drawn without a chosen image)
    var showLogo = true
    var logoPath: String?
    var logoCorner: Corner = .bottomRight
    var logoWidth: Double = 8              // % of video width
    var logoMargin: Double = 4             // % of video width

    // Title
    var fontName = "HelveticaNeue"         // PostScript name; Helvetica Neue is available on every Mac
    var titleSize: Double = 10             // % of video height
    var titleColor: RGBAColor = .white
    var titleOffset: Double = 0            // % of video height, positive = up
    var titleShadow = false

    // Intro
    var introDuration: Double = 2          // seconds
    var fadeIn: Double = 0                 // seconds, fade in from black
    var crossfade: Double = 0              // seconds, cross-fade from poster into video

    // Output
    var codec: VideoCodec = .h264
    var savePoster = true
    var createSubfolder = true

    var backgroundURL: URL? {
        guard backgroundKind == .image else { return nil }
        return backgroundPath.map(AssetStore.url(for:))
    }

    var logoURL: URL? {
        guard showLogo else { return nil }
        return logoPath.map(AssetStore.url(for:))
    }

    /// All image references of this preset – including a currently unused background image,
    /// so it is still there when switching back from "Color" to "Image".
    var assetReferences: [String] {
        [backgroundPath, logoPath].compactMap { $0 }
    }

    /// Whether the preset's font is installed on this Mac.
    var isFontAvailable: Bool {
        NSFont(name: fontName, size: 12) != nil
    }

    /// Images and font used by the preset that are not (or no longer) available.
    var missingResources: [String] {
        var missing: [String] = []
        if !isFontAvailable { missing.append(String(localized: "Font “\(fontName)”")) }
        if backgroundKind == .image, !(backgroundPath.map(AssetStore.exists) ?? false) {
            missing.append(String(localized: "Background image"))
        }
        if showLogo, let path = logoPath, !AssetStore.exists(path) { missing.append(String(localized: "Logo")) }
        return missing
    }
}

// MARK: - Assets

/// Images chosen in presets are copied into the asset folder so presets don't depend on the original files.
/// Content-addressed storage: `<checksum>/<original file name>`. Same image → one shared copy,
/// different images with the same name → different folders.
enum AssetStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Make Intro/Assets", isDirectory: true)
    }

    /// References are relative to the asset folder; absolute paths come from older versions.
    static func url(for reference: String) -> URL {
        reference.hasPrefix("/") ? URL(fileURLWithPath: reference) : directory.appendingPathComponent(reference)
    }

    static func exists(_ reference: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: reference).path)
    }

    static func isImported(_ reference: String) -> Bool {
        !reference.hasPrefix("/")
    }

    /// Copies the file into the asset folder (unless already present) and returns the reference to it.
    static func importFile(_ source: URL) throws -> String {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: source)
        let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let folder = directory.appendingPathComponent(hash, isDirectory: true)

        if let existing = try? fileManager.contentsOfDirectory(atPath: folder.path).first(where: { !$0.hasPrefix(".") }) {
            return "\(hash)/\(existing)"
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(source.lastPathComponent), options: .atomic)
        return "\(hash)/\(source.lastPathComponent)"
    }

    /// Deletes all copies that none of the given references point to.
    static func removeUnused(keeping references: [String]) {
        let fileManager = FileManager.default
        let used = Set(references.filter(isImported).compactMap { $0.split(separator: "/").first.map(String.init) })
        for folder in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        where !folder.hasPrefix(".") && !used.contains(folder) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(folder))
        }
    }
}

extension IntroSettings {
    /// Lenient decoding: missing or invalid values (e.g. from older versions) fall back to the default
    /// instead of making the whole preset unreadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = IntroSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }

        self.init()
        backgroundPath = (try? container.decodeIfPresent(String.self, forKey: .backgroundPath)) ?? nil
        // Presets from versions without a background kind: with image → image, otherwise → color
        backgroundKind = value(.backgroundKind, backgroundPath == nil ? .color : .image)
        backgroundColor = value(.backgroundColor, defaults.backgroundColor)
        backgroundDim = value(.backgroundDim, defaults.backgroundDim)
        showLogo = value(.showLogo, defaults.showLogo)
        logoPath = (try? container.decodeIfPresent(String.self, forKey: .logoPath)) ?? nil
        logoCorner = value(.logoCorner, defaults.logoCorner)
        logoWidth = value(.logoWidth, defaults.logoWidth)
        logoMargin = value(.logoMargin, defaults.logoMargin)
        fontName = value(.fontName, defaults.fontName)
        titleSize = value(.titleSize, defaults.titleSize)
        titleColor = value(.titleColor, defaults.titleColor)
        titleOffset = value(.titleOffset, defaults.titleOffset)
        titleShadow = value(.titleShadow, defaults.titleShadow)
        introDuration = value(.introDuration, defaults.introDuration)
        fadeIn = value(.fadeIn, defaults.fadeIn)
        crossfade = value(.crossfade, defaults.crossfade)
        codec = value(.codec, defaults.codec)
        savePoster = value(.savePoster, defaults.savePoster)
        createSubfolder = value(.createSubfolder, defaults.createSubfolder)
    }
}

// MARK: - Presets

struct Preset: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var settings = IntroSettings()
}

@MainActor
final class PresetStore: ObservableObject {
    private static let key = "presets"
    private static let backupKey = "presets.unreadable"
    private static let legacySettingsKey = "introSettings"

    @Published var presets: [Preset] {
        didSet { save() }
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.key) {
            if let stored = try? JSONDecoder().decode([Preset].self, from: data), !stored.isEmpty {
                presets = stored
                prepareAssets()
                return
            }
            // Don't silently overwrite unreadable data – keep a backup instead.
            defaults.set(data, forKey: Self.backupKey)
        }

        // First launch: take over settings from earlier versions (if any) as the default preset.
        var initial = Preset(name: String(localized: "Default"))
        if let data = defaults.data(forKey: Self.legacySettingsKey),
           let legacy = try? JSONDecoder().decode(IntroSettings.self, from: data) {
            initial.settings = legacy
        }
        presets = [initial]
        prepareAssets()
        defaults.removeObject(forKey: Self.legacySettingsKey)
    }

    /// On launch: import old image paths, save (didSet doesn't fire in init) and clean up.
    private func prepareAssets() {
        importExternalAssets()
        save()
        removeUnusedAssets()
    }

    func preset(withID id: UUID?) -> Preset? {
        presets.first { $0.id == id }
    }

    @discardableResult
    func add() -> Preset {
        let preset = Preset(name: uniqueName(String(localized: "New Preset")))
        presets.append(preset)
        return preset
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Preset? {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = presets[index]
        copy.id = UUID()
        copy.name = uniqueName(String(localized: "\(copy.name) Copy"))
        presets.insert(copy, at: index + 1)
        return copy
    }

    func delete(_ id: UUID) {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == id }
        removeUnusedAssets()
    }

    /// Imports images from older versions (absolute paths) into the asset folder while the originals still exist.
    private func importExternalAssets() {
        let keyPaths: [WritableKeyPath<IntroSettings, String?>] = [\.backgroundPath, \.logoPath]
        for index in presets.indices {
            for keyPath in keyPaths {
                guard let reference = presets[index].settings[keyPath: keyPath],
                      !AssetStore.isImported(reference), AssetStore.exists(reference),
                      let imported = try? AssetStore.importFile(AssetStore.url(for: reference))
                else { continue }
                presets[index].settings[keyPath: keyPath] = imported
            }
        }
    }

    /// Deletes copies no longer in use – unless there are backed-up unreadable presets that might still need them.
    private func removeUnusedAssets() {
        guard UserDefaults.standard.data(forKey: Self.backupKey) == nil else { return }
        AssetStore.removeUnused(keeping: presets.flatMap(\.settings.assetReferences))
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(presets.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
