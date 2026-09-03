import AppKit
import Foundation

/// The app's one share surface: presents the macOS share picker
/// (NSSharingServicePicker) for a set of local files. Callers have no stable
/// NSView anchor (SwiftUI buttons, context menus), so the picker anchors at
/// the pointer's position in the key window — which is where the triggering
/// click just happened.
@MainActor
enum ShareServices {
    /// AppKit does not retain a presented picker; hold the active one so the
    /// popover survives its presenting call. Replaced on the next present.
    private static var activePicker: NSSharingServicePicker?

    static func presentPicker(for urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty,
              let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }
        let mouse = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let anchor = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        let picker = NSSharingServicePicker(items: existing)
        activePicker = picker
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }
}
