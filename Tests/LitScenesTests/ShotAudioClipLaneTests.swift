import Foundation
import Testing
@testable import LitScenes

// The clip lane carries an imported audio file on a shot — the
// "imported-media lane" ShotAudioModels anticipated. Semantics deliberately
// mirror the ambient bed, with one difference that matters: a clip plays ONCE
// at its own length, where a synthesized bed loops.

@Test func attachingAnAudioClipEnablesTheLaneAndSetsAFirstVolume() {
    let mix = ShotAudioMix().settingAudioClip(mediaId: "m_audio", path: "/tmp/a.wav")
    let lane = mix.lane(ShotAudioLaneId.clip)

    #expect(lane.hasAudioClip)
    #expect(lane.clipMediaId == "m_audio")
    #expect(lane.clipPath == "/tmp/a.wav")
    #expect(lane.isEnabled)
    #expect(lane.volume == 0.6)
}

@Test func swappingTheClipKeepsTheUserVolume() {
    // The ambient-bed rule: the default volume applies to the FIRST clip only,
    // so replacing a clip never quietly undoes a level the user set.
    var mix = ShotAudioMix().settingAudioClip(mediaId: "m_first", path: "/tmp/first.wav")
    mix = mix.settingLaneVolume(ShotAudioLaneId.clip, volume: 0.25)
    mix = mix.settingAudioClip(mediaId: "m_second", path: "/tmp/second.wav")

    let lane = mix.lane(ShotAudioLaneId.clip)
    #expect(lane.clipMediaId == "m_second")
    #expect(lane.volume == 0.25)
}

@Test func detachingClearsBothPointersAndDisablesTheLane() {
    var mix = ShotAudioMix().settingAudioClip(mediaId: "m_audio", path: "/tmp/a.wav")
    mix = mix.settingAudioClip(mediaId: nil, path: nil)

    let lane = mix.lane(ShotAudioLaneId.clip)
    #expect(!lane.hasAudioClip)
    #expect(lane.clipMediaId == nil)
    #expect(lane.clipPath == nil)
    #expect(!lane.isEnabled)
}

@Test func normalizingDropsAStrandedClipPath() {
    // A path without an id is not a half-attached clip, it is garbage — the
    // same rule the ambient fields follow.
    var lane = ShotAudioLane(laneId: ShotAudioLaneId.clip, kind: "clip", label: "Clip")
    lane.clipMediaId = "   "
    lane.clipPath = "/tmp/orphan.wav"

    let normalized = lane.normalized()
    #expect(normalized.clipMediaId == nil)
    #expect(normalized.clipPath == nil)
}

@Test func clipLaneSurvivesDecodingADocumentWrittenBeforeItExisted() {
    // THE hard rule on this type: a lane decode failure silently resets the
    // user's ENTIRE mix (ProjectShot decodes audioMix behind `try?` ?? empty).
    // Every new stored property must therefore be Optional, and old documents
    // must still decode.
    let legacyLaneJSON = """
    {"lanes":[{"laneId":"ambient","kind":"ambient","label":"Ambient","isEnabled":true,"volume":0.35,
      "activeTakeId":"","microphoneTakes":[],"ambientBedId":"ambient_abc","ambientBedPath":"/tmp/bed.m4a"}]}
    """
    let data = Data(legacyLaneJSON.utf8)

    let decoded = try? JSONDecoder().decode(ShotAudioMix.self, from: data)
    #expect(decoded != nil, "adding clip fields must not break documents written before them")
    // The pre-existing ambient attachment is intact…
    #expect(decoded?.lane(ShotAudioLaneId.ambient).ambientBedId == "ambient_abc")
    // …and the clip lane simply reads as empty.
    #expect(decoded?.lane(ShotAudioLaneId.clip).hasAudioClip == false)
}

@Test func clipAndAmbientLanesAreIndependent() {
    // Attaching a clip must not disturb a bed, and vice versa: they are
    // different materials on different lanes.
    var mix = ShotAudioMix().settingAmbientBed(bedId: "ambient_abc", path: "/tmp/bed.m4a")
    mix = mix.settingAudioClip(mediaId: "m_audio", path: "/tmp/a.wav")

    #expect(mix.lane(ShotAudioLaneId.ambient).ambientBedId == "ambient_abc")
    #expect(mix.lane(ShotAudioLaneId.clip).clipMediaId == "m_audio")

    mix = mix.settingAudioClip(mediaId: nil, path: nil)
    #expect(mix.lane(ShotAudioLaneId.ambient).hasAmbientBed)
    #expect(!mix.lane(ShotAudioLaneId.clip).hasAudioClip)
}

@Test func clipLaneCarriesACanonicalLabel() {
    #expect(ShotAudioLane.canonical(ShotAudioLaneId.clip).label == "Clip")
    #expect(ShotAudioLane.canonical(ShotAudioLaneId.ambient).label == "Ambient")
}
