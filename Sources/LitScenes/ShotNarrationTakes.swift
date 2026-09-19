import Foundation

extension ProjectShot {
    var authoredNarrationDriverSeconds: Double? {
        guard let narration = narrationArtifact, narration.isReady,
              narration.provider == "elevenlabs_tts",
              FileManager.default.fileExists(atPath: narration.audioPath) else { return nil }
        if let region = audioRegions.map({ $0.normalized() }).first(where: {
            $0.laneId == ShotAudioLaneId.narration && $0.provenance == "active_narration" && !$0.path.isEmpty
        }) {
            return max(region.startSeconds, 0) + max(region.durationSeconds, 0)
        }
        return audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds + narration.durationSeconds
    }

    var narrationVideoNeedsSync: Bool {
        guard let version = activeRenderVersion,
              version.model == VideoModelSelection.falLTX23AudioToVideo.providerModelId else { return false }
        return (!version.sourceNarrationFingerprint.isEmpty
            && version.sourceNarrationFingerprint != ShotNarrationDriverBuilder.currentFingerprint(shot: self))
            || (!version.sourceNarrationTraceId.isEmpty
                && version.sourceNarrationTraceId != narrationArtifact?.effectiveSpeechTraceId)
    }

    var sortedNarrationTakes: [ShotNarrationArtifact] {
        var migrated = self
        migrated.migrateLegacyNarrationIfNeeded()
        return migrated.narrationTakes.reversed()
    }

    func identifiedNarrationTake(_ artifact: ShotNarrationArtifact) -> ShotNarrationArtifact {
        var take = artifact.normalized()
        if take.takeId.isEmpty {
            let identity = "\(shotId):\(take.effectiveSourceAudioPath):\(take.generatedAt):\(take.requestId):\(take.status)"
            take.takeId = "narration_\(shortHash(identity, length: 20))"
        }
        return take
    }

    /// Adopt only actual saved artifacts. Historical transcript strings cannot
    /// establish another recording's bytes, voice, or provider provenance.
    mutating func migrateLegacyNarrationIfNeeded() {
        var seen: Set<String> = []
        narrationTakes = narrationTakes.map { identifiedNarrationTake($0) }
            .filter { seen.insert($0.takeId).inserted }
        if let mirror = narrationArtifact {
            let take = identifiedNarrationTake(mirror)
            if !narrationTakes.contains(where: { $0.takeId == take.takeId }) {
                narrationTakes.append(take)
            }
            narrationArtifact = take
            activeNarrationTakeId = take.isReady ? take.takeId : ""
        } else {
            activeNarrationTakeId = ""
        }
    }

    func recordingNarrationTake(_ artifact: ShotNarrationArtifact, now: String) -> ProjectShot {
        var value = self
        let take = identifiedNarrationTake(artifact)
        if let index = value.narrationTakes.firstIndex(where: { $0.takeId == take.takeId }) {
            value.narrationTakes[index] = take
        } else {
            value.narrationTakes.append(take)
        }
        if value.narrationArtifact?.takeId == take.takeId, value.narrationArtifact?.isReady != true {
            value.narrationArtifact = take
            value.activeNarrationTakeId = take.isReady ? take.takeId : ""
        }
        value.updatedAt = now
        return value
    }

    func activatingNarrationTake(_ takeId: String, atStart: Bool = false, now: String) -> ProjectShot {
        guard let take = narrationTakes.first(where: { $0.takeId == takeId && $0.isReady }) else { return self }
        var value = settingNarrationArtifact(take, now: now)
        if atStart {
            value.audioMix = value.audioMix.settingNarrationStartSeconds(0)
            for index in value.audioRegions.indices where value.audioRegions[index].laneId == ShotAudioLaneId.narration
                && value.audioRegions[index].provenance == "active_narration" {
                value.audioRegions[index].startSeconds = 0
            }
        }
        return value
    }
}

/// Narration edits have their own undo state so a paste cannot roll back
/// unrelated picture work. Generated media is retained for redo.
struct ShotNarrationStateSnapshot: Hashable, Sendable {
    var projectId: String
    var artifact: ShotNarrationArtifact?
    var takes: [ShotNarrationArtifact]
    var activeTakeId: String
    var audioMix: ShotAudioMix
    var audioRegions: [ShotAudioRegion]

    init(shot: ProjectShot, projectId: String) {
        self.projectId = projectId
        artifact = shot.narrationArtifact
        takes = shot.narrationTakes
        activeTakeId = shot.activeNarrationTakeId
        audioMix = shot.audioMix
        audioRegions = shot.audioRegions
    }

    func applying(to shot: ProjectShot, now: String) -> ProjectShot {
        var value = shot
        value.narrationArtifact = artifact
        value.narrationTakes = takes
        value.activeNarrationTakeId = activeTakeId
        value.audioMix = audioMix
        value.audioRegions = audioRegions
        value.updatedAt = now
        return value
    }
}

struct ShotNarrationStateEdit: Sendable {
    var before: ShotNarrationStateSnapshot
    var after: ShotNarrationStateSnapshot
}

/// UI and export share the same exact bounds; rounding is presentation only.
enum ShotNarrationDuration {
    static func isValid(_ seconds: Double) -> Bool {
        seconds.isFinite && seconds >= 2 && seconds <= 20
    }

    static func label(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "unknown duration" }
        let rounded = String(format: "%.3f", seconds)
        if !isValid(seconds), let displayed = Double(rounded), isValid(displayed) {
            return "\(seconds)s"
        }
        return rounded + "s"
    }

    static func refusal(_ seconds: Double) -> String? {
        guard !isValid(seconds) else { return nil }
        if !seconds.isFinite { return "Narration duration is unavailable. Open Narration to repair it." }
        return seconds < 2
            ? "\(label(seconds)) — below the 2s minimum. Adjust narration length or speed."
            : "\(label(seconds)) — above the 20s maximum. Adjust narration length or speed."
    }
}
