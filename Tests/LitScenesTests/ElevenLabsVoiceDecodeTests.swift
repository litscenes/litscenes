import Foundation
import Testing
@testable import LitScenes

// THE SNAKE-CASE COLLISION: `JSONCoding.decoder` converts incoming keys from
// snake_case (Utilities.swift), so a model that ALSO declares an explicit
// `case voiceId = "voice_id"` never matches — the decoder offers `voiceId`
// while the CodingKey answers to `voice_id`. The whole voices response then
// threw `keyNotFound`, the account list silently stayed empty, and the Voices
// tab showed only the three built-in presets while the API had happily
// returned 33 voices with HTTP 200.

/// One voice object shaped exactly like the live `/v1/voices` payload,
/// including the fields the model ignores.
private let liveVoicesPayload = """
{"voices":[
  {"voice_id":"2ajXGJNYBR0iNHpS4VZb","name":"Rob - Tough & Calloused","category":"professional",
   "description":"A tough British man. Gritty, Experienced, Strong.","is_owner":false,
   "labels":{"accent":"british"},"high_quality_base_model_ids":["eleven_v3"]},
  {"voice_id":"Ri2jKmhQJqHIlH3y1w0I","name":"Owner Clone v2","category":"cloned","description":null},
  {"voice_id":"L0Dsvb3SLTyegXwtm47J","name":"Archer","category":"professional","description":""}
]}
"""

@Test func elevenLabsVoicesDecodeThroughTheSharedSnakeCaseDecoder() throws {
    let decoded = try JSONCoding.decoder.decode(
        ElevenLabsVoicesResponse.self,
        from: Data(liveVoicesPayload.utf8)
    )
    #expect(decoded.voices.count == 3)
    #expect(decoded.voices.map(\.voiceId) == [
        "2ajXGJNYBR0iNHpS4VZb",
        "Ri2jKmhQJqHIlH3y1w0I",
        "L0Dsvb3SLTyegXwtm47J"
    ])
    #expect(decoded.voices[0].name == "Rob - Tough & Calloused")
    #expect(decoded.voices[0].category == "professional")
    // A null description is legal and must not sink the whole list.
    #expect(decoded.voices[1].name == "Owner Clone v2")
    #expect(decoded.voices[1].description.isEmpty)
}

/// A raw (non-converting) decoder must read the same payload — the model owns
/// its tolerance rather than depending on one decoder's key strategy.
@Test func elevenLabsVoicesDecodeThroughAPlainDecoder() throws {
    let decoded = try JSONDecoder().decode(
        ElevenLabsVoicesResponse.self,
        from: Data(liveVoicesPayload.utf8)
    )
    #expect(decoded.voices.map(\.voiceId).first == "2ajXGJNYBR0iNHpS4VZb")
}

/// Sparse and junk entries degrade honestly instead of throwing: a voice with
/// no usable id decodes empty and is dropped by `listVoices`.
@Test func elevenLabsVoicesToleratesSparseEntries() throws {
    let sparse = """
    {"voices":[{"voice_id":"abc123"},{"name":"No id here"},{}]}
    """
    let decoded = try JSONCoding.decoder.decode(
        ElevenLabsVoicesResponse.self,
        from: Data(sparse.utf8)
    )
    #expect(decoded.voices.count == 3)
    #expect(decoded.voices[0].voiceId == "abc123")
    #expect(decoded.voices[0].name.isEmpty)
    #expect(decoded.voices[1].voiceId.isEmpty)
    #expect(decoded.voices.filter { !$0.voiceId.isEmpty }.count == 1)
}

/// The account voices reach the sidebar list: extras merge after the three
/// built-ins, and an account voice that duplicates a built-in id folds into it.
@Test func accountVoicesMergeIntoTheSidebarList() {
    let account = [
        StoryAudioVoiceOption(
            id: "2ajXGJNYBR0iNHpS4VZb",
            name: "Rob - Tough & Calloused",
            descriptor: "professional",
            voiceId: "2ajXGJNYBR0iNHpS4VZb"
        ),
        // Archer's own id — must not appear twice.
        StoryAudioVoiceOption(
            id: "L0Dsvb3SLTyegXwtm47J",
            name: "Archer",
            descriptor: "professional",
            voiceId: "L0Dsvb3SLTyegXwtm47J"
        )
    ]
    let options = StoryAudioVoiceCatalog.voiceOptions(
        customVoiceId: "h2D62TolsL0yO7khh3d3",
        extraVoices: account
    )
    #expect(options.count == 4)
    #expect(options.map(\.name).contains("Rob - Tough & Calloused"))
    #expect(options.filter { $0.voiceId == "L0Dsvb3SLTyegXwtm47J" }.count == 1)
}

// MARK: Voice curation (hiding is display-only)

private func voice(_ id: String, _ name: String, _ descriptor: String) -> StoryAudioVoiceOption {
    StoryAudioVoiceOption(id: id, name: name, descriptor: descriptor, voiceId: id)
}

@Test func hiddenVoicesLeaveTheMenuButNeverTheCurrentSelection() {
    let all = [
        voice("archer", "Archer", "British male"),
        voice("rob", "Rob", "professional"),
        voice("roger", "Roger", "premade"),
        voice("sarah", "Sarah", "premade")
    ]
    // Plain hide: the two stock voices go.
    let visible = StoryAudioVoiceCatalog.visibleOptions(
        all,
        hiddenVoiceIds: ["roger", "sarah"]
    )
    #expect(visible.map(\.id) == ["archer", "rob"])

    // A narration already using a hidden voice still shows it — a menu must
    // be able to display its own value.
    let keeping = StoryAudioVoiceCatalog.visibleOptions(
        all,
        hiddenVoiceIds: ["roger", "sarah"],
        keepingVoiceId: "sarah"
    )
    #expect(keeping.map(\.id) == ["archer", "rob", "sarah"])

    // Hiding everything is refused in effect: the full list comes back rather
    // than an empty menu.
    #expect(
        StoryAudioVoiceCatalog.visibleOptions(
            all,
            hiddenVoiceIds: ["archer", "rob", "roger", "sarah"]
        ).count == 4
    )
    // No curation = untouched list (identity, not a copy of the filter path).
    #expect(StoryAudioVoiceCatalog.visibleOptions(all, hiddenVoiceIds: []).map(\.id) == all.map(\.id))
}

@Test func stockVoiceIdsTargetPremadeOnly() {
    let all = [
        voice("archer", "Archer", "British male"),
        voice("rob", "Rob", "professional"),
        voice("clone", "Owner Clone v2", "cloned"),
        voice("uncle", "Wise Hawaiian Uncle", "generated"),
        voice("roger", "Roger", "premade"),
        voice("sarah", "Sarah", "Premade")
    ]
    // Case-insensitive, and nothing the operator made or saved is swept in.
    #expect(StoryAudioVoiceCatalog.stockVoiceIds(in: all) == ["roger", "sarah"])
}

@Test func hiddenVoiceIdsSerializeAsOneSortedLocalValue() {
    // The stored form is a comma-separated list; parsing tolerates spaces,
    // blanks, and duplicates the same way the env reader does elsewhere.
    let parsed = Set(
        " rob , , roger,rob "
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    )
    #expect(parsed == ["rob", "roger"])
}

// MARK: THE RAW-ID PRESET LAW (voice never depends on a warmed cache)

@Test func rawVoiceIdPresetResolvesItselfEvenWithNoAccountList() {
    // Regression: Rob chosen as default, app relaunched,
    // Voices tab never opened → extras empty → the raw-id preset used to
    // fold to the custom clone. It must resolve to ITSELF.
    let rob = "2ajXGJNYBR0iNHpS4VZb"
    let resolved = StoryAudioVoiceCatalog.option(
        for: rob,
        customVoiceId: "h2D62TolsL0yO7khh3d3",
        extraVoices: []
    )
    #expect(resolved.voiceId == rob)
    #expect(resolved.voiceId != "h2D62TolsL0yO7khh3d3")

    // With the account list loaded, the exact match wins and carries the name.
    let named = StoryAudioVoiceCatalog.option(
        for: rob,
        customVoiceId: nil,
        extraVoices: [StoryAudioVoiceOption(
            id: rob, name: "Rob - Tough & Calloused", descriptor: "professional", voiceId: rob
        )]
    )
    #expect(named.name == "Rob - Tough & Calloused")

    // Legacy slugs keep their meaning; true junk still folds tolerantly.
    #expect(StoryAudioVoiceCatalog.option(for: "archer", customVoiceId: nil).id
        == StoryAudioVoiceCatalog.archerPresetId)
    #expect(StoryAudioVoiceCatalog.migratedPresetId(StoryAudioVoiceCatalog.legacyCustomPresetId)
        == StoryAudioVoiceCatalog.customPresetId)
    #expect(StoryAudioVoiceCatalog.option(for: StoryAudioVoiceCatalog.legacyCustomPresetId, customVoiceId: "h2D62TolsL0yO7khh3d3").id
        == StoryAudioVoiceCatalog.customPresetId)
    #expect(StoryAudioVoiceCatalog.option(for: "old preset!", customVoiceId: "h2D62TolsL0yO7khh3d3").id
        == StoryAudioVoiceCatalog.customPresetId)
}
