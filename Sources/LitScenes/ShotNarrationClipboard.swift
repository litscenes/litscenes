import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ShotNarrationClipboardPayload: Codable, Sendable {
    var version: Int = 1
    var take: ShotNarrationArtifact
    var sourceProjectId: String
    var sourceShotId: String

    var isPasteable: Bool { version == 1 && take.isReady && take.durationSeconds.isFinite && take.durationSeconds > 0 }

    init(take: ShotNarrationArtifact, sourceProjectId: String, sourceShotId: String) {
        self.take = take
        self.sourceProjectId = sourceProjectId
        self.sourceShotId = sourceShotId
    }

    private enum CodingKeys: String, CodingKey { case version, take, sourceProjectId, sourceShotId }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        take = try values.decode(ShotNarrationArtifact.self, forKey: .take)
        sourceProjectId = try values.decodeIfPresent(String.self, forKey: .sourceProjectId) ?? ""
        sourceShotId = try values.decodeIfPresent(String.self, forKey: .sourceShotId) ?? ""
    }

    var pasteRefusal: String? {
        guard isPasteable else { return "Copy a ready narration take first." }
        for path in [take.audioPath, take.effectiveSourceAudioPath] {
            guard path.hasPrefix("/"), FileManager.default.isReadableFile(atPath: path) else {
                return "The copied narration audio is missing or unreadable. Restore it or copy another take."
            }
        }
        return nil
    }

    /// The media reference establishes identity, never the label or transcript.
    /// Scope snapshots may retain an earlier speed derivative of the same take.
    static func matching(_ region: ShotAudioRegion, in shot: ProjectShot,
                         projectId: String) -> ShotNarrationClipboardPayload? {
        guard ShotAudioLaneId.kind(ofLaneId: region.laneId) == ShotAudioLaneId.narration,
              !region.path.isEmpty else { return nil }
        func scopeTakes(_ scopes: [ShotOutputScope]) -> [ShotNarrationArtifact] {
            scopes.flatMap { [$0.edits.narrationArtifact].compactMap { $0 } + scopeTakes($0.children) }
        }
        let candidates = [shot.narrationArtifact].compactMap { $0 }
            + shot.sortedNarrationTakes + scopeTakes(shot.outputScopes)
        var seen: Set<String> = []
        let matches = candidates.map { shot.identifiedNarrationTake($0) }.filter { take in
            guard take.isReady, take.audioPath == region.path else { return false }
            if !region.sourceArtifactId.isEmpty,
               ![take.takeId, take.traceId, take.effectiveSpeechTraceId].contains(region.sourceArtifactId) { return false }
            return seen.insert(take.takeId + "|" + take.audioPath).inserted
        }
        guard matches.count == 1, let take = matches.first else { return nil }
        return .init(take: take, sourceProjectId: projectId, sourceShotId: shot.shotId)
    }

    /// Copy files before publishing destination state. Independent paths keep
    /// another project's deletion or a future speed edit from changing a take.
    func materialized(in directory: URL, now: String) throws -> ShotNarrationArtifact {
        if let refusal = pasteRefusal { throw ScreenGraphError.capture(refusal) }
        let paths = [take.effectiveSourceAudioPath, take.audioPath]
        for path in paths {
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else {
                throw ScreenGraphError.capture("The copied narration audio is missing. Restore its file or copy another take.")
            }
        }
        var copy = take
        copy.takeId = "narration_\(UUID().uuidString.lowercased())"
        copy.sourceProjectId = sourceProjectId
        copy.sourceShotId = sourceShotId
        copy.sourceTakeId = take.takeId
        copy.copiedAt = now
        copy.updatedAt = now
        let destination = directory.appendingPathComponent(copy.takeId, isDirectory: true)
        try ensureDirectory(destination)
        var copied: [String: String] = [:]
        do {
            for (index, path) in paths.enumerated() where copied[path] == nil {
                let source = URL(fileURLWithPath: path)
                let target = destination.appendingPathComponent(index == 0 ? "source" : "audio")
                    .appendingPathExtension(source.pathExtension)
                try FileManager.default.copyItem(at: source, to: target)
                copied[path] = target.path
            }
        } catch {
            // Only this operation's newly created directory is removed.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        copy.sourceAudioPath = copied[take.effectiveSourceAudioPath] ?? ""
        copy.audioPath = copied[take.audioPath] ?? ""
        return copy.normalized()
    }
}

enum ShotNarrationPasteAvailability {
    case available(ShotNarrationClipboardPayload)
    case unavailable(String)

    var payload: ShotNarrationClipboardPayload? {
        if case .available(let payload) = self { return payload }
        return nil
    }
    var refusal: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

@MainActor
enum ShotNarrationClipboard {
    static let utType = UTType(exportedAs: "com.litscenes.shot-narration")
    static let pasteboardType = NSPasteboard.PasteboardType(utType.identifier)

    static func contents(for payload: ShotNarrationClipboardPayload) throws -> ShotClipboardContents {
        if let refusal = payload.pasteRefusal { throw ScreenGraphError.capture(refusal) }
        return ShotClipboardContents(data: [pasteboardType: try JSONEncoder().encode(payload)])
    }

    static func availability(pasteboard: NSPasteboard = .general,
                             resolveLegacy: (ShotAudioRegionClipboardPayload) -> ShotNarrationClipboardPayload? = { _ in nil }) -> ShotNarrationPasteAvailability {
        if let data = pasteboard.data(forType: pasteboardType) {
            guard let payload = try? JSONDecoder().decode(ShotNarrationClipboardPayload.self, from: data) else {
                return .unavailable("The copied narration cannot be read. Copy it again from Narration Takes.")
            }
            return validated(payload)
        }
        if let region = ShotAudioClipboard.read(from: pasteboard) {
            guard ShotAudioLaneId.kind(ofLaneId: region.region.laneId) == ShotAudioLaneId.narration else {
                return .unavailable("The clipboard contains another kind of audio. Copy a narration take first.")
            }
            guard let payload = resolveLegacy(region) else {
                return .unavailable("The original narration take could not be identified. Copy it again from Narration Takes.")
            }
            return validated(payload)
        }
        return .unavailable("Copy a narration take or its timeline region first.")
    }

    static func validated(_ payload: ShotNarrationClipboardPayload) -> ShotNarrationPasteAvailability {
        if let refusal = payload.pasteRefusal { return .unavailable(refusal) }
        return .available(payload)
    }

}

@MainActor
final class ShotNarrationUndoCoordinator: ObservableObject {
    var applyState: ((String, ShotNarrationStateSnapshot) -> Bool)?
    private weak var manager: UndoManager?

    func register(shotId: String, edit: ShotNarrationStateEdit, name: String, undoManager: UndoManager?) {
        guard let undoManager, edit.before != edit.after else { return }
        manager = undoManager
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                guard target.applyState?(shotId, edit.before) == true else { return }
                target.register(shotId: shotId,
                    edit: ShotNarrationStateEdit(before: edit.after, after: edit.before),
                    name: name, undoManager: target.manager)
            }
        }
        undoManager.setActionName(name)
    }
}
