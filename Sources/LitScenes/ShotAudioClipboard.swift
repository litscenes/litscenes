import AppKit
import Foundation
import UniformTypeIdentifiers

/// THE AUDIO CLIPBOARD: copy/cut/paste for audio regions rides the SYSTEM
/// pasteboard under a custom type, not an in-app singleton — it survives
/// sheets, window churn, and relaunch, and cross-shot paste comes free.
/// The payload is tolerant JSON like every persisted document: a paste from
/// a newer build with fields this build doesn't know still lands.
///
/// Cross-PROJECT paste is allowed and honest: `region.path` is absolute, so
/// it plays wherever the file still exists; where it doesn't, the lane's
/// MISSING hatch + REPLACE relink flow already covers recovery. A dangling
/// `mediaId` is accepted — regions resolve by path first.
extension NSPasteboard.PasteboardType {
    static let litScenesShotAudioRegion =
        NSPasteboard.PasteboardType("com.litscenes.shot-audio-region")
}

struct ShotAudioRegionClipboardPayload: Codable, Hashable, Sendable {
    var version: Int = 1
    var region = ShotAudioRegion()
    var sourceShotId: String = ""
    var sourceProjectId: String = ""

    private enum CodingKeys: String, CodingKey {
        case version, region, sourceShotId, sourceProjectId
    }

    init(
        version: Int = 1,
        region: ShotAudioRegion = ShotAudioRegion(),
        sourceShotId: String = "",
        sourceProjectId: String = ""
    ) {
        self.version = version
        self.region = region
        self.sourceShotId = sourceShotId
        self.sourceProjectId = sourceProjectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        region = (try? container.decodeIfPresent(ShotAudioRegion.self, forKey: .region))
            ?? ShotAudioRegion()
        sourceShotId = try container.decodeIfPresent(String.self, forKey: .sourceShotId) ?? ""
        sourceProjectId = try container.decodeIfPresent(String.self, forKey: .sourceProjectId) ?? ""
    }

    /// A payload worth pasting: it names media (path or id) and claims real
    /// duration. Anything else reads as an empty clipboard.
    var isPasteable: Bool {
        let clean = region.normalized()
        return (!clean.path.isEmpty || !clean.mediaId.isEmpty) && clean.durationSeconds > 0
    }
}

enum ShotAudioClipboard {
    /// The exported type behind `.onCopyCommand`/`.onPasteCommand` — declared
    /// in code (this app is the only reader), identifier == the pasteboard
    /// type's raw string, so provider-written and directly-written payloads
    /// read back through the same `read()`.
    static let utType = UTType(exportedAs: "com.litscenes.shot-audio-region")

    /// The item-provider form for SwiftUI's copy/cut commands, which write
    /// the pasteboard themselves from the returned providers.
    static func itemProviders(for payload: ShotAudioRegionClipboardPayload) -> [NSItemProvider] {
        guard let data = try? JSONEncoder().encode(payload) else { return [] }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: utType.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return [provider]
    }

    static func write(_ payload: ShotAudioRegionClipboardPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .litScenesShotAudioRegion)
    }

    static func read() -> ShotAudioRegionClipboardPayload? {
        guard let data = NSPasteboard.general.data(forType: .litScenesShotAudioRegion),
              let payload = try? JSONDecoder().decode(
                  ShotAudioRegionClipboardPayload.self,
                  from: data
              ),
              payload.isPasteable else { return nil }
        return payload
    }

    static var hasPayload: Bool {
        NSPasteboard.general.availableType(from: [.litScenesShotAudioRegion]) != nil
    }
}
