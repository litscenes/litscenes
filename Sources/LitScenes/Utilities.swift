import AppKit
import CoreTransferable
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MediaIDTransfer: Codable, Hashable, Transferable {
    let mediaId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

enum ScreenGraphError: LocalizedError {
    case missingAPIKey
    case missingResource(String)
    case invalidImageDestination
    case openAI(String)
    case capture(String)
    case credentials(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key missing. Add one in App Settings, or set OPENAI_API_KEY."
        case .missingResource(let name):
            return "Missing resource: \(name)"
        case .invalidImageDestination:
            return "Could not create image destination."
        case .openAI(let message):
            return message
        case .capture(let message):
            return message
        case .credentials(let message):
            return message
        }
    }
}

enum DateFormats {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func now() -> String {
        string(from: Date())
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

func uniqueNonEmpty(_ values: [String], limit: Int? = nil) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { continue }
        let key = cleaned.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        output.append(cleaned)
        if let limit, output.count >= limit {
            break
        }
    }
    return output
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CodableValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([CodableValue])
    case object([String: CodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CodableValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: CodableValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

func stableSlug(_ value: String, fallback: String = "item") -> String {
    let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let allowed = CharacterSet.alphanumerics
    var scalars: [UnicodeScalar] = []
    var previousDash = false
    for scalar in lowered.unicodeScalars {
        if allowed.contains(scalar) {
            scalars.append(scalar)
            previousDash = false
        } else if !previousDash {
            scalars.append("-")
            previousDash = true
        }
    }
    let slug = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug.isEmpty ? fallback : slug
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func shortHash(_ value: String, length: Int = 12) -> String {
    String(sha256Hex(Data(value.utf8)).prefix(length))
}

func ensureDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

/// True when this process is a test runner. Derived from the process itself,
/// never from mutable state, so it cannot depend on initialization order.
let litScenesIsRunningTests: Bool = {
    let environment = ProcessInfo.processInfo.environment
    if environment["XCTestConfigurationFilePath"] != nil { return true }
    if environment["XCTestBundlePath"] != nil { return true }
    if ProcessInfo.processInfo.processName == "swiftpm-testing-helper" { return true }
    return ProcessInfo.processInfo.arguments.contains { $0.hasSuffix(".xctest") }
}()

/// Per-process sandbox root for test runs. One directory per process, so every
/// store in a run agrees on where "Application Support" is, and each run starts
/// clean without racing a sibling run.
private let litScenesTestSandboxDirectory: URL = FileManager.default.temporaryDirectory
    .appendingPathComponent(
        "litscenes-test-support-\(ProcessInfo.processInfo.processIdentifier)",
        isDirectory: true
    )

/// The app's Application Support root — and the single chokepoint that keeps
/// test runs out of the user's real data.
///
/// This resolver is load-bearing for isolation, not just convenience. Several
/// stores default-construct `ProjectLibrary()` (whose root derives from here),
/// and `SoundSceneTimelineStore.shared` is an actor singleton that hardcodes
/// one with no injection point at all — so a test that touched it registered a
/// project in the USER's registry and created a directory in the USER's
/// projects folder, no matter what temp root the fixture passed. That leak put
/// 1,275 dead rows in the real registry and 84 stray project directories on
/// disk (since swept). Redirecting the root is what actually closes it;
/// injecting at call sites cannot reach the singleton.
///
/// `LITSCENES_APP_SUPPORT_DIR` overrides everything, for running the real app
/// against a scratch library.
func litScenesApplicationSupportDirectory() -> URL {
    if let override = ProcessInfo.processInfo.environment["LITSCENES_APP_SUPPORT_DIR"],
       !override.trimmingCharacters(in: .whitespaces).isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
            .appendingPathComponent(LitScenesReleaseIdentity.current.applicationSupportDirectoryName, isDirectory: true)
    }
    if litScenesIsRunningTests {
        return litScenesTestSandboxDirectory
            .appendingPathComponent(LitScenesReleaseIdentity.current.applicationSupportDirectoryName, isDirectory: true)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent(
        LitScenesReleaseIdentity.current.applicationSupportDirectoryName,
        isDirectory: true
    )
}

func pngData(from image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw ScreenGraphError.invalidImageDestination
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScreenGraphError.invalidImageDestination
    }
    return data as Data
}

func writePNG(_ image: CGImage, to url: URL) throws -> Data {
    let data = try pngData(from: image)
    try data.write(to: url, options: [.atomic])
    return data
}

struct ProviderReadyImage: Sendable {
    var data: Data
    var mimeType: String
    var fileExtension: String
    var width: Int
    var height: Int
    var sourceTypeIdentifier: String
    var wasConverted: Bool
}

/// Validates image bytes at the provider boundary. OpenAI accepts JPEG, PNG, GIF,
/// and WebP; other ImageIO-decodable formats (notably HEIC from Photos) are converted
/// to a bounded sRGB JPEG instead of being mislabeled from their filename extension.
func providerReadyImage(
    from imageData: Data,
    maxPixelSize: Int = 2048,
    quality: Double = 0.90
) throws -> ProviderReadyImage {
    guard !imageData.isEmpty else {
        throw ScreenGraphError.capture("Image data is empty.")
    }
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions),
          let sourceTypeValue = CGImageSourceGetType(source) else {
        throw ScreenGraphError.capture("Image data could not be decoded.")
    }
    let sourceTypeIdentifier = sourceTypeValue as String
    guard let sourceType = UTType(sourceTypeIdentifier),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        throw ScreenGraphError.capture("Image format or dimensions could not be read.")
    }
    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard width > 0, height > 0 else {
        throw ScreenGraphError.capture("Image has invalid dimensions.")
    }

    let supported: (mimeType: String, fileExtension: String)?
    if sourceType.conforms(to: .jpeg) {
        supported = ("image/jpeg", "jpg")
    } else if sourceType.conforms(to: .png) {
        supported = ("image/png", "png")
    } else if sourceType.conforms(to: .gif) {
        supported = ("image/gif", "gif")
    } else if sourceType.conforms(to: .webP) {
        supported = ("image/webp", "webp")
    } else {
        supported = nil
    }
    if let supported {
        return ProviderReadyImage(
            data: imageData,
            mimeType: supported.mimeType,
            fileExtension: supported.fileExtension,
            width: width,
            height: height,
            sourceTypeIdentifier: sourceTypeIdentifier,
            wasConverted: false
        )
    }

    let normalized = try normalizedJPEGData(
        from: source,
        maxPixelSize: maxPixelSize,
        quality: quality
    )
    return ProviderReadyImage(
        data: normalized.data,
        mimeType: "image/jpeg",
        fileExtension: "jpg",
        width: normalized.width,
        height: normalized.height,
        sourceTypeIdentifier: sourceTypeIdentifier,
        wasConverted: true
    )
}

func normalizedJPEGData(
    from imageData: Data,
    maxPixelSize: Int = 2048,
    quality: Double = 0.90
) throws -> (data: Data, width: Int, height: Int) {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions) else {
        throw ScreenGraphError.capture("Could not load image data.")
    }
    return try normalizedJPEGData(from: source, maxPixelSize: maxPixelSize, quality: quality)
}

func normalizedJPEGData(
    from imageURL: URL,
    maxPixelSize: Int = 2048,
    quality: Double = 0.90
) throws -> (data: Data, width: Int, height: Int) {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, sourceOptions) else {
        throw ScreenGraphError.capture("Could not load image at \(imageURL.path).")
    }
    return try normalizedJPEGData(from: source, maxPixelSize: maxPixelSize, quality: quality)
}

private func normalizedJPEGData(
    from source: CGImageSource,
    maxPixelSize: Int,
    quality: Double
) throws -> (data: Data, width: Int, height: Int) {
    let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
        throw ScreenGraphError.capture("Could not decode image.")
    }
    let width = decoded.width
    let height = decoded.height
    guard width > 0, height > 0 else {
        throw ScreenGraphError.capture("Image has invalid dimensions.")
    }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ScreenGraphError.capture("Could not create image normalization canvas.")
    }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(NSColor.black.cgColor)
    context.fill(rect)
    context.interpolationQuality = .high
    context.draw(decoded, in: rect)
    guard let rendered = context.makeImage() else {
        throw ScreenGraphError.capture("Could not create normalized image.")
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw ScreenGraphError.invalidImageDestination
    }
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(destination, rendered, options)
    guard CGImageDestinationFinalize(destination) else {
        throw ScreenGraphError.invalidImageDestination
    }
    return (output as Data, width, height)
}

func imagePixelSize(from data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return nil
    }
    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard width > 0, height > 0 else { return nil }
    return (width, height)
}

func loadDotEnv(from url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var values: [String: String] = [:]
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
        let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
        var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        values[key] = value
    }
    return values
}

func environmentValue(_ key: String, cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> String? {
    if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
        return value
    }

    let bundleURL = Bundle.main.bundleURL
    let homeURL = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [
        cwd.appendingPathComponent(".env"),
        bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
        bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env"),
        homeURL.appendingPathComponent(".litscenes.env"),
        homeURL.appendingPathComponent(".config/litscenes/.env")
    ]

    for candidate in candidates {
        if let value = loadDotEnv(from: candidate)[key], !value.isEmpty {
            return value
        }
    }
    return nil
}

func packagedResourceURL(named name: String, extension ext: String) throws -> URL {
    let filename = "\(name).\(ext)"
    let bundleNames = ["LitScenes_LitScenes.bundle", "ScreenGraphRecorder_ScreenGraphRecorder.bundle"]
    var candidates: [URL] = []
    if let resourceURL = Bundle.main.resourceURL {
        for bundleName in bundleNames {
            candidates.append(resourceURL.appendingPathComponent(bundleName).appendingPathComponent(filename))
        }
        candidates.append(resourceURL.appendingPathComponent(filename))
    }
    for bundleName in bundleNames {
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName).appendingPathComponent(filename))
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName).appendingPathComponent(filename))
    }
    candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/LitScenes/Resources/Schemas").appendingPathComponent(filename))
    candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/LitScenes/Resources").appendingPathComponent(filename))
    candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/LitScenes/Resources/Pricing").appendingPathComponent(filename))
    for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
    }
    throw ScreenGraphError.missingResource(filename)
}

extension URL {
    func relativePath(from base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = standardizedFileURL.path
        if path.hasPrefix(basePath) {
            return String(path.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return path
    }
}

extension Double {
    var dollars: String {
        if self < 0.01 {
            return String(format: "$%.5f", self)
        }
        return String(format: "$%.2f", self)
    }
}
