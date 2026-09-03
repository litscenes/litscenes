import Foundation
import Testing
@testable import LitScenes

private func sampleIdentity(
    essence: String = "a tired staff engineer",
    publicFunction: String = "Staff engineer",
    desire: String = "wants the system to admit it is absurd",
    operatingRule: String = "never flatters a dashboard",
    cost: String = "passed over every cycle",
    signature: String = "annotates org charts in red ink",
    formativePressure: String = "one catastrophic launch",
    strangeness: Double = 0.5,
    visualDescription: String = "rumpled oxford, red pen behind the ear"
) -> GoalCastIdentity {
    GoalCastIdentity(
        essence: essence,
        publicFunction: publicFunction,
        desire: desire,
        operatingRule: operatingRule,
        cost: cost,
        signature: signature,
        formativePressure: formativePressure,
        strangeness: strangeness,
        visualDescription: visualDescription
    )
}

private func sampleMember(
    memberId: String = "castmember_leo",
    name: String = "Leo",
    takes: [GoalCastTake]? = nil,
    activeTakeId: String? = nil,
    pinnedDimensions: [String] = []
) -> GoalCastMember {
    let resolvedTakes = takes ?? [GoalCastTake(takeId: "take_1", origin: "initial", identity: sampleIdentity())]
    return GoalCastMember(
        memberId: memberId,
        name: name,
        takes: resolvedTakes,
        activeTakeId: activeTakeId ?? resolvedTakes.last?.takeId ?? "",
        pinnedDimensions: pinnedDimensions
    )
}

@Test
func goalCastDocumentNormalizesDedupesCapsAndRoundTrips() throws {
    var document = GoalCastDocument.empty(projectId: "project_test")
    document.members = [
        sampleMember(memberId: "m1", name: "Leo"),
        sampleMember(memberId: "m2", name: "leo"),          // ci-duplicate name — dropped
        sampleMember(memberId: "m1", name: "Voss"),         // duplicate id — dropped
        sampleMember(memberId: "m3", name: "   ")           // blank name — dropped
    ]
    let normalized = document.normalized()
    #expect(normalized.members.map(\.name) == ["Leo"])
    #expect(normalized.member(named: "LEO")?.memberId == "m1")

    let data = try JSONCoding.encoder.encode(normalized)
    let decoded = try JSONCoding.decoder.decode(GoalCastDocument.self, from: data)
    #expect(decoded == normalized)

    // Member cap holds at 12.
    var crowded = GoalCastDocument.empty(projectId: "project_test")
    crowded.members = (0..<14).map { sampleMember(memberId: "m\($0)", name: "Name \($0)") }
    #expect(crowded.normalized().members.count == GoalCastDocument.maximumMembers)

    // Tolerant decode of a minimal payload mints ids and fills defaults.
    let minimal = try JSONCoding.decoder.decode(
        GoalCastDocument.self,
        from: Data(#"{"members": [{"name": "Ava"}]}"#.utf8)
    )
    #expect(minimal.schemaVersion == GoalCastDocument.schemaVersion)
    #expect(minimal.articulatedAt.isEmpty)
    #expect(minimal.members.count == 1)
    #expect(!minimal.members[0].memberId.isEmpty)
    #expect(minimal.members[0].takes.isEmpty)
    #expect(minimal.members[0].activeTakeId.isEmpty)
}

@Test
func goalCastMemberRepairsActiveTakeCapsTakesAndFiltersPins() {
    let takes = (1...10).map { index in
        GoalCastTake(takeId: "take_\(index)", origin: "initial", identity: sampleIdentity(strangeness: 1.7))
    }
    let member = sampleMember(
        takes: takes,
        activeTakeId: "take_missing",
        pinnedDimensions: ["cost", "bogus", "desire", "cost"]
    ).normalized()

    #expect(member.takes.count == GoalCastMember.maximumTakes)
    #expect(member.takes.first?.takeId == "take_3")                    // oldest evicted, newest kept
    #expect(member.activeTakeId == "take_10")                          // dangling pointer repairs to newest
    #expect(member.pinnedDimensions == ["desire", "cost"])             // declaration order, unknowns dropped
    #expect(member.activeIdentity.strangeness == 1.0)                  // clamped
}

@Test
func appendTakeEvictsOldestAndActivates() {
    var member = sampleMember(
        takes: (1...GoalCastMember.maximumTakes).map {
            GoalCastTake(takeId: "take_\($0)", origin: "initial", identity: sampleIdentity())
        }
    )
    let newcomer = GoalCastTake(takeId: "take_new", origin: "stranger", identity: sampleIdentity(strangeness: 0.8))
    member.appendTake(newcomer, now: "2026-07-17T00:00:00Z")
    #expect(member.takes.count == GoalCastMember.maximumTakes)
    #expect(member.takes.first?.takeId == "take_2")
    #expect(member.activeTakeId == "take_new")
    #expect(member.updatedAt == "2026-07-17T00:00:00Z")
}

@Test
func mergeChangesOnlyTheAllowedSetAndKeepsEmptyEmissions() {
    let prior = sampleIdentity()
    let emitted = sampleIdentity(
        essence: "DIFFERENT essence",
        publicFunction: "DIFFERENT function",
        desire: "DIFFERENT desire",
        operatingRule: "DIFFERENT rule",
        cost: "",                                  // claimed but empty — keeps prior
        signature: "hums elevator jingles",
        formativePressure: "DIFFERENT pressure",
        strangeness: 0.9,
        visualDescription: "carries a chrome kazoo"
    )

    // new-tell touches only signature + visualDescription.
    let newTell = mergedGoalCastIdentity(
        prior: prior,
        emitted: emitted,
        allowed: GoalCastSteerGesture.newTell.allowedDimensions ?? [],
        pinned: []
    )
    #expect(newTell.signature == "hums elevator jingles")
    #expect(newTell.visualDescription == "carries a chrome kazoo")
    #expect(newTell.essence == prior.essence)
    #expect(newTell.publicFunction == prior.publicFunction)
    #expect(newTell.desire == prior.desire)
    #expect(newTell.operatingRule == prior.operatingRule)
    #expect(newTell.cost == prior.cost)
    #expect(newTell.formativePressure == prior.formativePressure)
    #expect(newTell.strangeness == prior.strangeness)          // not in the new-tell set

    // Empty emission keeps prior even inside the allowed set.
    let raiseCost = mergedGoalCastIdentity(
        prior: prior,
        emitted: emitted,
        allowed: GoalCastSteerGesture.raiseCost.allowedDimensions ?? [],
        pinned: []
    )
    #expect(raiseCost.cost == prior.cost)

    // Strangeness moves only when its dimension is allowed.
    let stranger = mergedGoalCastIdentity(
        prior: prior,
        emitted: emitted,
        allowed: GoalCastSteerGesture.stranger.allowedDimensions ?? [],
        pinned: []
    )
    #expect(stranger.strangeness == 0.9)
}

@Test
func mergePinsBlockGesturesAndChatOverridesCrossThem() {
    let prior = sampleIdentity()
    let emitted = sampleIdentity(
        desire: "DIFFERENT desire",
        signature: "hums elevator jingles",
        visualDescription: "carries a chrome kazoo"
    )

    // A pinned signature survives new-tell; visualDescription still updates.
    let pinnedTell = mergedGoalCastIdentity(
        prior: prior,
        emitted: emitted,
        allowed: GoalCastSteerGesture.newTell.allowedDimensions ?? [],
        pinned: [.signature]
    )
    #expect(pinnedTell.signature == prior.signature)
    #expect(pinnedTell.visualDescription == "carries a chrome kazoo")

    // A chat patch whose field is user-authored crosses the pin.
    let crossed = mergedGoalCastIdentity(
        prior: prior,
        emitted: emitted,
        allowed: [.desire],
        pinned: [.desire],
        pinOverride: [.desire]
    )
    #expect(crossed.desire == "DIFFERENT desire")
}

@Test
func gestureVocabularyAndProvenanceLabels() {
    #expect(GoalCastSteerGesture.newTell.allowedDimensions == [.signature, .visualDescription])
    #expect(GoalCastSteerGesture.raiseCost.allowedDimensions == [.cost, .signature, .visualDescription])
    #expect(GoalCastSteerGesture.feedback("x").allowedDimensions == nil)
    #expect(GoalCastSteerGesture.stranger.originLabel == "stranger")

    let long = String(repeating: "y", count: 120)
    let label = GoalCastSteerGesture.feedback(long).originLabel
    #expect(label.hasPrefix("feedback: "))
    #expect(label.hasSuffix("…"))
    #expect(label.count < 100)

    #expect(goalCastChatOriginLabel("") == "chat")
    #expect(goalCastChatOriginLabel("softened the rule") == "chat: softened the rule")

    let responseMember = GoalCastArticulatedMember(changedFields: ["cost", "bogus", "strangeness"])
    #expect(responseMember.changedDimensions == [.cost, .strangeness])
}

@Test
func sanitizerEnforcesRemoveVerbatimMatchFallbacksAndCaps() {
    var cast = GoalCastDocument.empty(projectId: "project_test")
    cast.members = [sampleMember(memberId: "m1", name: "Aurelio")]

    let completePatch = ProjectGoalCastUpdate(
        targetName: "Nadia",
        action: "update",
        essence: "e", publicFunction: "f", desire: "d", operatingRule: "r",
        cost: "c", signature: "s", visualDescription: "v"
    )
    let updates: [ProjectGoalCastUpdate] = [
        ProjectGoalCastUpdate(targetName: "Voss", action: "remove"),                  // hallucinated — dropped
        ProjectGoalCastUpdate(targetName: "Aurelio", action: "remove"),               // verbatim in message — kept
        ProjectGoalCastUpdate(targetName: "Nadia", action: "update", cost: "c"),      // unknown + incomplete — dropped
        completePatch,                                                                // unknown + complete — becomes add
        ProjectGoalCastUpdate(targetName: "aurelio", action: "add", cost: "c"),       // dup name in batch — skipped
        ProjectGoalCastUpdate(targetName: "Bram", action: "merge"),                   // unknown action — dropped
        ProjectGoalCastUpdate(
            targetName: "Sana", action: "add", desire: "wants out",
            userAuthoredFields: ["desire", "cost", "nonsense"]                        // cost not emitted, nonsense invalid
        )
    ]
    let result = sanitizeGoalCastChatUpdates(updates, currentCast: cast, latestUserMessage: "please remove Aurelio from the story")

    #expect(result.updates.map(\.targetName) == ["Aurelio", "Nadia", "Sana"])
    #expect(result.updates[0].action == "remove")
    #expect(result.updates[1].action == "add")
    #expect(result.updates[2].userAuthoredFields == ["desire"])
    #expect(result.warnings.count == 3)

    // Existing-name add demotes to update; batch cap holds at 6.
    let flood = [ProjectGoalCastUpdate(targetName: "Aurelio", action: "add", cost: "c")]
        + (0..<7).map { ProjectGoalCastUpdate(targetName: "Extra \($0)", action: "add") }
    let capped = sanitizeGoalCastChatUpdates(flood, currentCast: cast, latestUserMessage: "")
    #expect(capped.updates.count == 6)
    #expect(capped.updates[0].action == "update")
}

@Test
func applyMintsTakesWithProvenancePinsAndSyncIds() {
    var cast = GoalCastDocument.empty(projectId: "project_test")
    cast.members = [sampleMember(memberId: "m1", name: "Aurelio", pinnedDimensions: ["desire"])]
    let now = "2026-07-17T00:00:00Z"

    let sanitized = sanitizeGoalCastChatUpdates(
        [
            ProjectGoalCastUpdate(
                targetName: "Voss", action: "add",
                essence: "a rival maître d'", desire: "wants the room's fear",
                userAuthoredFields: ["desire"], changeNote: "added rival"
            ),
            ProjectGoalCastUpdate(
                targetName: "Aurelio", action: "update",
                desire: "wants a quiet exit", cost: "his stars",
                userAuthoredFields: ["desire"], changeNote: "user redefined the desire"
            )
        ],
        currentCast: cast,
        latestUserMessage: "add Voss; Aurelio now wants a quiet exit"
    )
    let applied = appliedGoalCastChatUpdates(document: cast, updates: sanitized.updates, now: now)

    let voss = applied.document.member(named: "Voss")
    #expect(voss != nil)
    #expect(voss?.takes.count == 1)
    #expect(voss?.takes.first?.origin == "chat: added rival")
    #expect(voss?.activeIdentity.strangeness == 0.5)                    // nil strangeness defaults on add
    #expect(voss?.pinnedDimensions == ["desire"])                       // user-authored auto-pin

    let aurelio = applied.document.member(named: "Aurelio")
    #expect(aurelio?.takes.count == 2)
    #expect(aurelio?.activeIdentity.desire == "wants a quiet exit")     // user-authored crossed the pin
    #expect(aurelio?.activeIdentity.cost == "his stars")
    #expect(aurelio?.activeIdentity.operatingRule == sampleIdentity().operatingRule)  // untouched field carried
    #expect(aurelio?.pinnedDimensions == ["desire"])                    // still pinned after crossing
    #expect(applied.syncMemberIds.count == 2)

    // Remove drops the member and never lands in syncMemberIds.
    let removal = sanitizeGoalCastChatUpdates(
        [ProjectGoalCastUpdate(targetName: "Voss", action: "remove")],
        currentCast: applied.document,
        latestUserMessage: "remove Voss"
    )
    let afterRemove = appliedGoalCastChatUpdates(document: applied.document, updates: removal.updates, now: now)
    #expect(afterRemove.document.member(named: "Voss") == nil)
    #expect(afterRemove.syncMemberIds.isEmpty)
}

@Test
func castUpdateTolerantDecodeAndEmittedDimensions() throws {
    let decoded = try JSONCoding.decoder.decode(
        ProjectGoalCastUpdate.self,
        from: Data(#"{"target_name": "Ava", "action": "update", "cost": "her marriage"}"#.utf8)
    )
    #expect(decoded.targetName == "Ava")
    #expect(decoded.strangeness == nil)
    #expect(decoded.userAuthoredFields.isEmpty)
    #expect(decoded.emittedDimensions == [.cost])

    let response = try JSONCoding.decoder.decode(
        GoalCastArticulationResponse.self,
        from: Data(#"{"members": [{"name": "Ava", "strangeness": 0.2}]}"#.utf8)
    )
    #expect(response.members.count == 1)
    #expect(response.members[0].identity.strangeness == 0.2)
    #expect(response.castingNote.isEmpty)
}

@Test
func interviewResponseToleratesV05ShapedPayloads() throws {
    // A v0.5 response has no cast_updates key — decode must not hard-fail.
    let payload = #"{"schema_version": "litscenes.project_goal_interview_response.v0.5", "assistant_message": "ok", "brief": {"goal": "make it strange"}, "change_summary": "note"}"#
    let decoded = try ProjectGoalInterviewResponseV3.decode(from: Data(payload.utf8))
    #expect(decoded.assistantMessage == "ok")
    #expect(decoded.brief.goal == "make it strange")
    #expect(decoded.castUpdates.isEmpty)

    let withUpdates = #"{"assistant_message": "ok", "brief": {"goal": "g"}, "change_summary": "", "cast_updates": [{"target_name": "Voss", "action": "add", "desire": "wants the room's fear"}]}"#
    let decodedUpdates = try ProjectGoalInterviewResponseV3.decode(from: Data(withUpdates.utf8))
    #expect(decodedUpdates.castUpdates.count == 1)
    #expect(decodedUpdates.castUpdates[0].targetName == "Voss")
    #expect(decodedUpdates.castUpdates[0].emittedDimensions == [.desire])
}

@Test
func identityGistSkipsEmptyDimensions() {
    #expect(GoalCastIdentity().gist == nil)
    let gist = sampleIdentity(cost: "", formativePressure: "").gist
    #expect(gist == "wants wants the system to admit it is absurd; rule: never flatters a dashboard; tell: annotates org charts in red ink")
}
