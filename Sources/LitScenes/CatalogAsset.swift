import AppKit
import Foundation
import SwiftUI

/// Portable content-addressed references; never resolve a caller-supplied file path.
enum BundledCatalogAsset {
    static func url(for address: String, expectedSHA256: String? = nil) throws -> URL {
        guard let url = URL(string: address), url.scheme == "litscenes-bundle", url.host == "catalog",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.pathComponents.count == 3, url.pathComponents[1] == "images", url.pathExtension == "png" else {
            throw ScreenGraphError.capture("This style image is not a bundled reference.")
        }
        let hash = url.deletingPathExtension().lastPathComponent
        guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }),
              expectedSHA256 == nil || expectedSHA256 == hash else {
            throw ScreenGraphError.capture("The bundled style reference has an invalid identity.")
        }
        let file = try packagedResourceURL(named: "CatalogFallback/images/\(hash)", extension: "png")
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), sha256Hex(data) == hash else {
            throw ScreenGraphError.capture("The bundled style image failed its integrity check. Reinstall the app or choose a local style image.")
        }
        return file
    }
}

/// Local previews only. Older remote thumbnails may still exist in the OS cache.
struct CatalogImage<Content: View>: View {
    let address: String
    @ViewBuilder var content: (AsyncImagePhase) -> Content
    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase).task(id: address) {
            do {
                let data: Data
                if address.hasPrefix("litscenes-bundle:") {
                    data = try Data(contentsOf: BundledCatalogAsset.url(for: address))
                } else if let url = URL(string: address),
                          let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url)) {
                    data = cached.data
                } else {
                    throw ScreenGraphError.capture("Choose a local replacement for this unavailable legacy style image.")
                }
                guard let image = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                phase = .success(Image(nsImage: image))
            } catch { phase = .failure(error) }
        }
    }
}
