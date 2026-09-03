import Testing
@testable import LitScenes

// Implicit casting: the scene cast is derived from the newest media version's takes.
// These cover the pure derivation core and the pure-plan predicate that gates
// hard-removal of planned takes.

@Test
func derivedCharacterIdsKeepsFirstAppearanceOrder() {
    let derived = LensCastDerivation.derivedCharacterIds(
        resolvedIds: ["b", "a", "b", "c", "a"],
        knownIds: ["a", "b", "c"]
    )
    #expect(derived == ["b", "a", "c"])
}

@Test
func derivedCharacterIdsFiltersUnknownAndEmptyIds() {
    let derived = LensCastDerivation.derivedCharacterIds(
        resolvedIds: ["", "ghost", "a", "", "deleted", "b"],
        knownIds: ["a", "b"]
    )
    #expect(derived == ["a", "b"])
}

@Test
func derivedCharacterIdsHasNoCap() {
    let ids = (1...6).map { "c\($0)" }
    let derived = LensCastDerivation.derivedCharacterIds(
        resolvedIds: ids,
        knownIds: Set(ids)
    )
    #expect(derived == ids)
}

@Test
func derivedCharacterIdsEmptyInputs() {
    #expect(LensCastDerivation.derivedCharacterIds(resolvedIds: [], knownIds: ["a"]) == [])
    #expect(LensCastDerivation.derivedCharacterIds(resolvedIds: ["a"], knownIds: []) == [])
}

@Test
func purePlanRequiresQueuedAndNeverStarted() {
    var take = ProjectLensHeroImage(imageId: "img_1", status: "queued")
    take.generatedAt = ""
    take.renderVersion = nil
    take.reframe = nil
    #expect(take.isPurePlan)

    var rendered = take
    rendered.generatedAt = "2026-07-15T00:00:00Z"
    #expect(!rendered.isPurePlan)

    var versioned = take
    versioned.renderVersion = LensRenderVersionMetadata(renderVersionId: "v1")
    #expect(!versioned.isPurePlan)

    var reframed = take
    reframed.reframe = LensReframeSpec()
    #expect(!reframed.isPurePlan)

    for status in ["generating", "ready", "failed", "cancelled", "idle"] {
        var other = take
        other.status = status
        #expect(!other.isPurePlan, "status \(status) must not be a pure plan")
    }
}
