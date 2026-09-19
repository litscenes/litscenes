import AppKit
import Combine
import Foundation
import SwiftUI

/// One clipboard item can offer different representations to the timeline
/// and the Shot row. Prepare every representation before replacing anything.
struct ShotClipboardContents {
    var data: [NSPasteboard.PasteboardType: Data]

    @MainActor var includesNarration: Bool { data[ShotNarrationClipboard.pasteboardType] != nil }

    @MainActor
    func matches(_ pasteboard: NSPasteboard) -> Bool {
        !data.isEmpty && data.allSatisfy { pasteboard.data(forType: $0.key) == $0.value }
    }

    @MainActor
    func write(to pasteboard: NSPasteboard) throws {
        guard !data.isEmpty else { throw ScreenGraphError.capture("Nothing could be copied. Select the audio again.") }
        let item = NSPasteboardItem()
        for (type, bytes) in data {
            guard item.setData(bytes, forType: type) else {
                throw ScreenGraphError.capture("Could not prepare the clipboard. Try Copy again.")
            }
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]), matches(pasteboard) else {
            throw ScreenGraphError.capture("Copy failed. Try Copy again before pasting.")
        }
    }

    func itemProviders() -> [NSItemProvider] {
        guard !data.isEmpty else { return [] }
        let provider = NSItemProvider()
        for (type, bytes) in data {
            provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                completion(bytes, nil)
                return nil
            }
        }
        return [provider]
    }
}

/// Pasteboard writes from Edit commands and other app instances do not emit
/// our own notifications. Publish only ownership changes, once for all rows.
@MainActor
final class ShotClipboardState: ObservableObject {
    static let shared = ShotClipboardState()
    @Published private(set) var revision: Int
    private var observation: AnyCancellable?

    private init() {
        revision = NSPasteboard.general.changeCount
        observation = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let current = NSPasteboard.general.changeCount
        if revision != current { revision = current }
    }
}

@MainActor
final class ShotClipboardCopyFeedback: ObservableObject {
    @Published private(set) var message = ""
    @Published private(set) var detail = ""
    @Published private(set) var isError = false
    @Published private(set) var verifiedRevision: Int?
    private var verification: Task<Void, Never>?
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func copy(_ prepare: () throws -> ShotClipboardContents, onCopied: () -> Void = {}) {
        verification?.cancel()
        do {
            let contents = try prepare()
            try contents.write(to: pasteboard)
            confirm(contents)
            onCopied()
        } catch { fail(error.localizedDescription) }
    }

    /// SwiftUI owns the actual Edit-menu write. Confirm its completed data,
    /// not provider creation, and delay Cut deletion until that succeeds.
    func providers(_ prepare: () throws -> ShotClipboardContents,
                   onCopied: @escaping () -> Void = {}) -> [NSItemProvider] {
        verification?.cancel()
        do {
            let contents = try prepare()
            let providers = contents.itemProviders()
            guard !providers.isEmpty else { throw ScreenGraphError.capture("Nothing could be copied. Select the audio again.") }
            let before = pasteboard.changeCount
            verifiedRevision = nil
            message = "Copying…"
            detail = ""
            isError = false
            verification = Task { [weak self] in
                for _ in 0..<20 {
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                    guard let self else { return }
                    if pasteboard.changeCount != before, contents.matches(pasteboard) {
                        confirm(contents)
                        onCopied()
                        return
                    }
                }
                self?.fail("Copy could not be confirmed. Try the Copy button before pasting.")
            }
            return providers
        } catch {
            fail(error.localizedDescription)
            return []
        }
    }

    private func confirm(_ contents: ShotClipboardContents) {
        isError = false
        verifiedRevision = pasteboard.changeCount
        message = contents.includesNarration ? "✓ Narration copied" : "✓ Audio region copied"
        detail = contents.includesNarration
            ? "Use Paste Narration on another Shot. Timeline Paste keeps the selected region’s edits."
            : "Paste into an audio timeline. To copy a whole narration, use Copy in Narration Takes."
        ShotClipboardState.shared.refresh()
    }

    private func fail(_ reason: String) {
        isError = true
        verifiedRevision = nil
        message = reason
        detail = ""
        ShotClipboardState.shared.refresh()
    }
}

struct ShotClipboardFeedbackView: View {
    @ObservedObject var feedback: ShotClipboardCopyFeedback
    @ObservedObject private var clipboard = ShotClipboardState.shared

    var body: some View {
        if !feedback.message.isEmpty,
           feedback.verifiedRevision == nil || feedback.verifiedRevision == clipboard.revision {
            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.message).font(.system(size: 11, weight: .semibold))
                if !feedback.detail.isEmpty { Text(feedback.detail).font(.system(size: 11)) }
            }
            .foregroundStyle(feedback.isError ? CanonColor.rust : CanonColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }
}
