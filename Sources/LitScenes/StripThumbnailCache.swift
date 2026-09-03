import AppKit
import ImageIO

/// Downsampled decode cache for the SCENES canvas thumbnails (cut strips,
/// stage palettes, shelves). The cells are ~196×110pt but the renders behind
/// them are full-resolution PNGs; `NSImage(contentsOfFile:)` inside `body`
/// re-decoded every one of them on every SwiftUI pass, which is where the
/// SCENES tab's memory and main-thread time went. This decodes once at cell
/// scale (CGImageSource thumbnailing never inflates the full bitmap), keyed
/// by path + mtime so a re-rendered file re-decodes.
/// `@unchecked Sendable`: the only state is an `NSCache`, which is
/// documented thread-safe.
final class StripThumbnailCache: @unchecked Sendable {
    static let shared = StripThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
        cache.totalCostLimit = 128 * 1_024 * 1_024
    }

    /// `maxPixel` defaults to 2× the 196pt cell edge — crisp on retina, tiny
    /// beside a 1024px+ source decode.
    func image(path: String, maxPixel: Int = 400) -> NSImage? {
        let trimmed = path.trimmed
        guard !trimmed.isEmpty else { return nil }
        let mtime = ((try? FileManager.default.attributesOfItem(atPath: trimmed))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(trimmed)|\(Int(mtime))|\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let url = URL(fileURLWithPath: trimmed)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        cache.setObject(image, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        return image
    }
}
