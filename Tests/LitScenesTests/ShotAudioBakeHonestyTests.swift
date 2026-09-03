import AVFoundation
import Foundation
import Testing
@testable import LitScenes

// BAKE HONESTY: a flatten must refuse to bake silence where the document
// promises audio. These tests pin the three halves: the pure expected-audible
// enumeration mirrors `applyMix`'s gates, the readability verifier throws
// with the file's name, and the reel bake fingerprint moves when a referenced
// file's identity moves.

private func honestyShot(
    regions: [ShotAudioRegion] = [],
    lanes: [ShotAudioLane] = []
) -> ProjectShot {
    var shot = ProjectShot(shotId: "shot_bake_honesty", name: "Bake Honesty")
    shot.audioRegions = regions
    shot.audioMix = ShotAudioMix(lanes: lanes)
    return shot
}

private func honestyRegion(
    _ regionId: String,
    laneId: String = ShotAudioLaneId.clip,
    path: String = "/audio/music.wav",
    startSeconds: Double = 0,
    durationSeconds: Double = 4,
    gain: Double = 1,
    isMuted: Bool = false,
    label: String = ""
) -> ShotAudioRegion {
    var region = ShotAudioRegion(
        regionId: regionId,
        laneId: laneId,
        path: path,
        startSeconds: startSeconds,
        durationSeconds: durationSeconds
    )
    region.gain = gain
    region.isMuted = isMuted
    region.label = label
    return region
}

@Test func expectedAudibleFilesMirrorApplyMixGates() {
    let shot = honestyShot(regions: [
        honestyRegion("audible", path: "/audio/music.wav", label: "Music"),
        honestyRegion("muted", path: "/audio/muted.wav", isMuted: true),
        honestyRegion("zeroGain", path: "/audio/zero.wav", gain: 0),
        honestyRegion("onDisabledLane", laneId: "clip_2", path: "/audio/disabled-lane.wav"),
        honestyRegion("sourceSpan", laneId: ShotAudioLaneId.source, path: "/audio/source.wav")
    ], lanes: [
        {
            var lane = ShotAudioLane.canonical(ShotAudioLaneId.clip)
            lane.isEnabled = true
            return lane
        }(),
        {
            var lane = ShotAudioLane.canonical("clip_2")
            lane.isEnabled = false
            return lane
        }()
    ])
    let files = shotExpectedAudibleAudioFiles(shot: shot, outputDurationSeconds: 10)
    #expect(files.map(\.path) == ["/audio/music.wav"])
    #expect(files.map(\.label) == ["Music"])
}

@Test func regionsStrandedPastTheOutputEndAreNotRequired() {
    // The real incident: an ambient region left at 25.4s after the picture
    // was razored down to ~22s. It is arithmetically silent, so it must not
    // fail a bake it cannot be heard in — but an OVERHANGING region (starts
    // inside, ends past the edge) still sounds and stays required.
    let shot = honestyShot(regions: [
        honestyRegion("stranded", path: "/audio/stranded.wav", startSeconds: 25.375, durationSeconds: 5),
        honestyRegion("overhang", path: "/audio/overhang.wav", startSeconds: 1.5, durationSeconds: 36.6)
    ])
    let files = shotExpectedAudibleAudioFiles(shot: shot, outputDurationSeconds: 21.883)
    #expect(files.map(\.path) == ["/audio/overhang.wav"])
    // With no known duration every placed region is required.
    let unbounded = shotExpectedAudibleAudioFiles(shot: shot, outputDurationSeconds: .infinity)
    #expect(unbounded.map(\.path) == ["/audio/stranded.wav", "/audio/overhang.wav"])
}

@Test func legacyOverlaysAreRequiredOnlyWhenTheirLanesSound() {
    var clipLane = ShotAudioLane.canonical(ShotAudioLaneId.clip)
    clipLane.clipPath = "/audio/legacy-clip.mp3"
    var ambientLane = ShotAudioLane.canonical(ShotAudioLaneId.ambient)
    ambientLane.ambientBedPath = "/audio/bed.caf"
    ambientLane.isEnabled = false
    let shot = honestyShot(lanes: [clipLane, ambientLane])
    let files = shotExpectedAudibleAudioFiles(shot: shot, outputDurationSeconds: 10)
    #expect(files.map(\.path) == ["/audio/legacy-clip.mp3"])
    #expect(files.map(\.label) == ["Audio clip"])
}

@Test func duplicatePathsCollapseToOneRequirement() {
    let shot = honestyShot(regions: [
        honestyRegion("sliverOne", path: "/audio/drums.wav", startSeconds: 11.875, durationSeconds: 0.708),
        honestyRegion("sliverTwo", path: "/audio/drums.wav", startSeconds: 12.792, durationSeconds: 0.708)
    ])
    let files = shotExpectedAudibleAudioFiles(shot: shot, outputDurationSeconds: 21.883)
    #expect(files.count == 1)
}

@Test func verifierPassesReadableAudioAndNamesTheUnreadable() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bake-honesty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // A real, readable audio file.
    let readableURL = directory.appendingPathComponent("readable.caf")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let writer = try AVAudioFile(forWriting: readableURL, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
    buffer.frameLength = 4_800
    try writer.write(from: buffer)

    try await ShotAudioComposition.verifyExpectedAudibleFilesReadable([
        ShotAudioFileRequirement(path: readableURL.path, label: "Bed")
    ])

    // Exists on disk but is not audio — the dataless-placeholder shape.
    let garbageURL = directory.appendingPathComponent("swing-drums.wav")
    try Data(repeating: 0x41, count: 2_048).write(to: garbageURL)
    await #expect(throws: ScreenGraphError.self) {
        try await ShotAudioComposition.verifyExpectedAudibleFilesReadable([
            ShotAudioFileRequirement(path: garbageURL.path, label: "Music")
        ])
    }
    do {
        try await ShotAudioComposition.verifyExpectedAudibleFilesReadable([
            ShotAudioFileRequirement(path: garbageURL.path, label: "Music")
        ])
        Issue.record("An unreadable file must refuse the bake")
    } catch {
        #expect(error.localizedDescription.contains("swing-drums.wav"))
        #expect(error.localizedDescription.contains("Music"))
    }

    // Gone entirely.
    do {
        try await ShotAudioComposition.verifyExpectedAudibleFilesReadable([
            ShotAudioFileRequirement(path: directory.appendingPathComponent("gone.wav").path, label: "Music")
        ])
        Issue.record("A missing file must refuse the bake")
    } catch {
        #expect(error.localizedDescription.contains("gone.wav"))
    }
}

@Test func offlineChipOutranksCountAndMissingOutranksOffline() {
    let regions = [
        honestyRegion("r1", label: "Drums"),
        honestyRegion("r2", label: "Bass")
    ]
    let offline = shotAudioLaneHead(
        laneId: ShotAudioLaneId.clip,
        laneLabel: "Clip",
        isEnabled: true,
        laneVolume: 1,
        regions: regions,
        missingRegionIds: [],
        offlineRegionIds: ["r2"],
        emptyText: "NO CLIP",
        unit: "CLIP",
        hasPickerTargets: true
    )
    #expect(offline.chip.text == "OFFLINE CLIP")
    #expect(offline.chip.tone == .rust)
    #expect(offline.chip.help.contains("Finder"))

    let both = shotAudioLaneHead(
        laneId: ShotAudioLaneId.clip,
        laneLabel: "Clip",
        isEnabled: true,
        laneVolume: 1,
        regions: regions,
        missingRegionIds: ["r1"],
        offlineRegionIds: ["r2"],
        emptyText: "NO CLIP",
        unit: "CLIP",
        hasPickerTargets: true
    )
    #expect(both.chip.text == "MISSING CLIP")
}
