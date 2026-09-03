import Foundation
import Testing
@testable import LitScenes

// MARK: - THE LIP-SYNC ANCHOR LAW (pure verdict; the detector stays out)

@Test func lipSyncVerdictBlocksSmallAndMissingFacesButFailsOpen() {
    // Observed frozen-mouth anchors measured ≈4% of frame height — blocked.
    let small = shotAnchorLipSyncVerdict(
        report: ShotAnchorFaceReport(faceCount: 1, largestFaceHeightFraction: 0.04)
    )
    #expect(small == .small(faceHeightFraction: 0.04))
    #expect(small.blocksRender)
    #expect(shotAnchorLipSyncRefusal(verdict: small)?.contains("4%") == true)

    let none = shotAnchorLipSyncVerdict(
        report: ShotAnchorFaceReport(faceCount: 0, largestFaceHeightFraction: 0)
    )
    #expect(none == .noFace)
    #expect(none.blocksRender)
    #expect(shotAnchorLipSyncRefusal(verdict: none) != nil)

    let ready = shotAnchorLipSyncVerdict(
        report: ShotAnchorFaceReport(faceCount: 2, largestFaceHeightFraction: 0.4)
    )
    #expect(ready == .ready(faceHeightFraction: 0.4))
    #expect(!ready.blocksRender)
    #expect(shotAnchorLipSyncRefusal(verdict: ready) == nil)

    // Detector/image failure fails OPEN — a broken detector must never
    // block a legitimate render.
    let unavailable = shotAnchorLipSyncVerdict(report: nil)
    #expect(unavailable == .unavailable)
    #expect(!unavailable.blocksRender)
    #expect(shotAnchorLipSyncRefusal(verdict: unavailable) == nil)

    // The threshold is a boundary, not a band: exactly at it is ready.
    let atThreshold = shotAnchorLipSyncVerdict(
        report: ShotAnchorFaceReport(
            faceCount: 1,
            largestFaceHeightFraction: shotAnchorLipSyncMinimumFaceHeightFraction
        )
    )
    #expect(!atThreshold.blocksRender)
}

// MARK: - Anchor entry resolution (picked wins, stale falls back)

private func anchorFixtureShot() -> (ProjectShot, [String: ProjectLensHeroImage]) {
    let frames = [
        ProjectLensHeroImage(imageId: "img_wide", imagePath: "/frames/wide.png"),
        ProjectLensHeroImage(imageId: "img_close", imagePath: "/frames/close.png"),
        ProjectLensHeroImage(imageId: "img_gone", imagePath: "/frames/gone.png"),
    ]
    let shot = ProjectShot(
        shotId: "shot_anchor",
        entries: [
            ShotFrameEntry(entryId: "e_wide", frameImageId: "img_wide"),
            ShotFrameEntry(entryId: "e_close", frameImageId: "img_close"),
            ShotFrameEntry(entryId: "e_gone", frameImageId: "img_gone"),
        ]
    )
    let lookup = Dictionary(uniqueKeysWithValues: frames.map { ($0.imageId, $0) })
    return (shot, lookup)
}

@Test func narrationAnchorPrefersThePickAndFallsBackWhenStale() {
    let (base, lookup) = anchorFixtureShot()
    let exists: (String) -> Bool = { $0 != "/frames/gone.png" }

    // Default: first ready frame.
    #expect(
        shotNarrationAnchorEntry(shot: base, frameLookup: lookup, fileExists: exists)?
            .entry.entryId == "e_wide"
    )

    // A valid pick wins.
    var picked = base
    picked.narrationAnchorEntryId = "e_close"
    #expect(
        shotNarrationAnchorEntry(shot: picked, frameLookup: lookup, fileExists: exists)?
            .entry.entryId == "e_close"
    )

    // A pick whose file is missing falls back to first-ready, never refuses.
    var stale = base
    stale.narrationAnchorEntryId = "e_gone"
    #expect(
        shotNarrationAnchorEntry(shot: stale, frameLookup: lookup, fileExists: exists)?
            .entry.entryId == "e_wide"
    )

    // A skipped pick falls back the same way.
    var skipped = base
    skipped.narrationAnchorEntryId = "e_close"
    skipped.entries[1].isSkipped = true
    #expect(
        shotNarrationAnchorEntry(shot: skipped, frameLookup: lookup, fileExists: exists)?
            .entry.entryId == "e_wide"
    )
}

@Test func narrationAnchorEntryIdDecodesTolerantly() throws {
    let legacy = Data(#"{"shotId":"shot_x"}"#.utf8)
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: legacy)
    #expect(decoded.narrationAnchorEntryId == "")

    let picked = Data(#"{"shotId":"shot_x","narrationAnchorEntryId":"e_close"}"#.utf8)
    let decodedPick = try JSONDecoder().decode(ProjectShot.self, from: picked)
    #expect(decodedPick.narrationAnchorEntryId == "e_close")
}

// MARK: - Stale narration-driven override sweep (the version-escape law)

@Test func switchingOffNarrationDrivenSweepsItsSegmentOverrides() {
    let ltxRaw = "fal_ltx_2_3_audio_to_video"
    var shot = ProjectShot(shotId: "shot_sweep")
    shot.preferredRenderStack = ltxRaw
    shot.segmentRenderOverrides = [
        ShotSegmentRenderOverride(
            startFrameImageId: "a",
            endFrameImageId: "b",
            stack: ltxRaw,
            updatedAt: "t0"
        ),
        ShotSegmentRenderOverride(
            startFrameImageId: "c",
            endFrameImageId: "d",
            stack: ShotRenderStack.wan27Five.rawValue,
            updatedAt: "t0"
        ),
    ]
    let swept = shot.settingPreferredRenderStack(.fallback, now: "t1")
    // The stale whole-shot-only override is gone; the normal one survives.
    #expect(swept.segmentRenderOverrides.map(\.stack) == [ShotRenderStack.wan27Five.rawValue])
    #expect(!swept.renderStack.isNarrationDriven)

    // Switching TO the narration stack never sweeps normal overrides.
    let backToLTX = swept.settingPreferredRenderStack(
        ShotRenderStack(rawValue: ltxRaw) ?? .fallback,
        now: "t2"
    )
    #expect(backToLTX.segmentRenderOverrides.map(\.stack) == [ShotRenderStack.wan27Five.rawValue])
}

// MARK: - The face-check vouch (override CTA)

@Test func faceOverrideAppliesOnlyToTheVouchedEntry() {
    // The vouch names one entry and covers exactly that entry.
    #expect(shotAnchorFaceOverrideApplies(overrideEntryId: "e_close", anchorEntryId: "e_close"))
    // A different resolved anchor re-arms the check by construction.
    #expect(!shotAnchorFaceOverrideApplies(overrideEntryId: "e_close", anchorEntryId: "e_wide"))
    // No vouch, no skip — and a vouch can never match a missing anchor.
    #expect(!shotAnchorFaceOverrideApplies(overrideEntryId: "", anchorEntryId: "e_close"))
    #expect(!shotAnchorFaceOverrideApplies(overrideEntryId: "e_close", anchorEntryId: ""))
    #expect(!shotAnchorFaceOverrideApplies(overrideEntryId: "  ", anchorEntryId: "  "))
}

@Test func faceOverrideEntryIdDecodesTolerantly() throws {
    let legacy = Data(#"{"shotId":"shot_x"}"#.utf8)
    #expect(try JSONDecoder().decode(ProjectShot.self, from: legacy)
        .narrationAnchorFaceOverrideEntryId == "")

    let vouched = Data(#"{"shotId":"shot_x","narrationAnchorFaceOverrideEntryId":"e_close"}"#.utf8)
    #expect(try JSONDecoder().decode(ProjectShot.self, from: vouched)
        .narrationAnchorFaceOverrideEntryId == "e_close")
}
