import AppKit
import CoreText
import Foundation

/// Registers the bundled display faces (Fraunces statics, SIL OFL 1.1 — the
/// project's first bundled fonts) with the current process. Registration is
/// process-scoped and idempotent: an already-registered face reports an error
/// CoreText code we deliberately ignore. `CanonType.display*` consults
/// `displayFaceAvailable` so a missing or failed registration degrades to the
/// system serif — `Font.custom` with an unknown name would silently render
/// sans, which is the one outcome the fallback law forbids.
enum CanonFontRegistration {
    static let displayRegularName = "Fraunces72pt-Regular"
    static let displaySemiBoldName = "Fraunces72pt-SemiBold"
    static let displayItalicName = "Fraunces72pt-Italic"

    private static let registerOnce: Bool = {
        guard let fontsURL = Bundle.module.url(forResource: "Fonts", withExtension: nil) else {
            return false
        }
        let fontURLs = (try? FileManager.default.contentsOfDirectory(
            at: fontsURL,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension.lowercased() == "ttf" } ?? []
        for url in fontURLs {
            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
            if !registered, let error = registrationError?.takeRetainedValue() {
                // Already-registered is fine (relaunch within tests, or a
                // system-installed copy); anything else is degraded honestly
                // by the availability probe below.
                _ = error
            }
        }
        return NSFont(name: displayRegularName, size: 12) != nil
    }()

    /// Performs registration on first call; safe to call repeatedly.
    @discardableResult
    static func registerBundledFonts() -> Bool {
        registerOnce
    }

    /// True when the display face actually resolves in this process.
    static var displayFaceAvailable: Bool {
        registerOnce
    }
}
