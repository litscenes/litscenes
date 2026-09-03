import Foundation
import Testing
@testable import LitScenes

// THE ROW LAW: `laneId` identifies, `kind` decides behavior, `label` displays.
// A shot may hold several rows of the same kind; every per-type branch keys on
// kind, so the second row of a kind is never treated as an unknown lane.

@Test func anArbitraryLaneIdResolvesToItsKindsBehaviorAndANumberedLabel() {
    #expect(ShotAudioLaneId.kind(ofLaneId: "clip_2") == ShotAudioLaneId.clip)
    #expect(ShotAudioLaneId.kind(ofLaneId: "ambient_11") == ShotAudioLaneId.ambient)
    #expect(ShotAudioLaneId.kind(ofLaneId: "microphone_3") == ShotAudioLaneId.microphone)
    #expect(ShotAudioLaneId.kind(ofLaneId: "clip") == ShotAudioLaneId.clip)

    // Kinds that cannot extend never parse a suffix away — an id that merely
    // LOOKS like an extra row of a locked kind stays its own unknown lane.
    #expect(ShotAudioLaneId.kind(ofLaneId: "source_2") == "source_2")
    #expect(ShotAudioLaneId.kind(ofLaneId: "narration_2") == "narration_2")
    // Nor does a non-numeric suffix.
    #expect(ShotAudioLaneId.kind(ofLaneId: "clip_extra") == "clip_extra")

    // A lane the mix has never seen still resolves usably.
    let fallback = ShotAudioLane.canonical("clip_2")
    #expect(fallback.kind == ShotAudioLaneId.clip)
    #expect(fallback.label == "Clip 2")
    #expect(ShotAudioLane.canonical("clip").label == "Clip")
    #expect(ShotAudioLane.canonical("microphone_4").label == "Mic 4")
}

@Test func anExtraRowMixesWithItsOwnVolumeAndMute() {
    // The reason extra rows work at all: `applyMix` looks the lane up per
    // region, and `lane(_:)` synthesizes an unknown id through `.canonical`.
    var mix = ShotAudioMix()
    mix = mix.settingLaneVolume("clip_2", volume: 0.4)
    mix = mix.settingLaneEnabled(ShotAudioLaneId.clip, enabled: false)

    #expect(abs(mix.lane("clip_2").volume - 0.4) < 0.000_1)
    #expect(mix.lane("clip_2").isEnabled)
    // The base row's mute does not travel to its siblings.
    #expect(!mix.lane(ShotAudioLaneId.clip).isEnabled)
    #expect(abs(mix.lane(ShotAudioLaneId.clip).volume - 1) < 0.000_1)
    // Persisting a lane IS creating the row — there is no second roster.
    #expect(mix.lanes.contains { $0.laneId == "clip_2" && $0.kind == ShotAudioLaneId.clip })
}

@Test func addingARowAlwaysMakesANumberedSiblingOfAnExtendableKind() throws {
    var mix = ShotAudioMix()
    // Never the bare kind: the base row is drawn whether or not anything has
    // persisted it, so "add a row" that returned `clip` would add nothing the
    // operator can see.
    let second = try #require(mix.addingLane(kind: ShotAudioLaneId.clip))
    #expect(second.laneId == "clip_2")

    mix = second.mix
    let third = try #require(mix.addingLane(kind: ShotAudioLaneId.clip))
    #expect(third.laneId == "clip_3")
    // Each kind numbers independently.
    #expect(try #require(third.mix.addingLane(kind: ShotAudioLaneId.ambient)).laneId == "ambient_2")

    // Picture-locked and artifact-governed kinds refuse outright.
    #expect(mix.addingLane(kind: ShotAudioLaneId.source) == nil)
    #expect(mix.addingLane(kind: ShotAudioLaneId.narration) == nil)
    #expect(mix.addingLane(kind: "nonsense") == nil)
}

@Test func removingARowRefusesEveryBaseRow() throws {
    let withExtra = try #require(ShotAudioMix().addingLane(kind: ShotAudioLaneId.clip)).mix
    #expect(withExtra.lanes.contains { $0.laneId == "clip_2" })

    // A base row is what the shot HAS, not how it is organized.
    #expect(withExtra.removingLane(ShotAudioLaneId.clip) == nil)
    #expect(withExtra.removingLane(ShotAudioLaneId.source) == nil)
    // An id with no row is not an error to report, just nothing to do.
    #expect(withExtra.removingLane("clip_9") == nil)

    let removed = try #require(withExtra.removingLane("clip_2"))
    #expect(!removed.lanes.contains { $0.laneId == "clip_2" })
    // The base CLIP row survives the removal — it is drawn unconditionally.
    #expect(shotAudioLaneRows(mix: removed, regions: []).contains(ShotAudioLaneId.clip))
    #expect(!shotAudioLaneRows(mix: removed, regions: []).contains("clip_2"))
}

@Test func rowOrderPlacesEachExtraDirectlyAfterItsOwnKind() {
    var mix = ShotAudioMix()
    mix = mix.settingLaneVolume("clip_3", volume: 0.5)
    mix = mix.settingLaneVolume("clip_2", volume: 0.5)
    mix = mix.settingLaneVolume("microphone_2", volume: 0.5)

    let rows = shotAudioLaneRows(mix: mix, regions: [])
    #expect(rows == [
        ShotAudioLaneId.source,
        ShotAudioLaneId.narration,
        ShotAudioLaneId.microphone, "microphone_2",
        ShotAudioLaneId.ambient,
        ShotAudioLaneId.clip, "clip_2", "clip_3"
    ])
    // Extras sort by ordinal, not by the order they were persisted.
    #expect(rows.firstIndex(of: "clip_2")! < rows.firstIndex(of: "clip_3")!)
}

@Test func aRegionPointingAtAMissingRowStillGetsARow() {
    // A row can go absent — an older document, a hand-edited file. A region on
    // a row that is never drawn would be audible with no way to reach it.
    let orphan = ShotAudioRegion(
        regionId: "r1",
        laneId: "clip_2",
        path: "/tmp/a.mp3",
        durationSeconds: 2
    )
    let rows = shotAudioLaneRows(mix: ShotAudioMix(), regions: [orphan])
    #expect(rows.contains("clip_2"))
    #expect(rows.firstIndex(of: "clip_2") == rows.firstIndex(of: ShotAudioLaneId.clip)! + 1)

    // The five canonical rows are always drawn, even on an empty shot.
    let bare = shotAudioLaneRows(mix: ShotAudioMix(), regions: [])
    #expect(bare.count == ShotTimelineAxis.laneCount)
    #expect(bare.first == ShotAudioLaneId.source)
    #expect(bare.last == ShotAudioLaneId.clip)
}

@Test func theStackAndPlayheadGrowWithTheRealRowCount() {
    let five = ShotTimelineAxis.playheadHeight(laneCount: 5)
    let six = ShotTimelineAxis.playheadHeight(laneCount: 6)
    #expect(six - five == ShotTimelineAxis.laneHeight + ShotTimelineAxis.rowSpacing)
    #expect(
        ShotTimelineAxis.stackHeight(laneCount: 6) - ShotTimelineAxis.stackHeight(laneCount: 5)
            == ShotTimelineAxis.laneHeight + ShotTimelineAxis.rowSpacing
    )
}
