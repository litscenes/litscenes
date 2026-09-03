import Foundation
import Testing
@testable import LitScenes

private func item(_ id: String, kind: String? = nil) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id, sourceId: "src", kind: .image, filename: "\(id).png", path: "/tmp/\(id).png",
        relativePath: "\(id).png", byteCount: 1, modifiedAt: "", width: 10, height: 10,
        thumbnailPath: "", scannedAt: "", derivativeKind: kind, sourceMediaId: nil
    )
}

private func plannedRow(sourcePrompt: String = "@Auri waits at the quay with @Lantern.") -> ProjectLensHeroImage {
    var row = ProjectLensHeroImage(
        imageId: "plan_1",
        imageIndex: 0,
        label: "Quay · turn",
        prompt: "Auri waits at the quay.",
        sourcePrompt: sourcePrompt,
        status: "queued",
        sourceRouteKey: "lens_media_area_1_scene_1",
        imageKind: LensImageTaxonomyKind.sceneImage,
        sceneId: "scene_1"
    )
    row.promptEnrichmentDisabled = true
    row.stabilityStrength = 0.4
    return row
}

private let entries = [
    RosterMentionResolver.Entry(id: "char_auri", name: "Auri", kind: .character, referenceMediaIds: ["loose_1", "loose_2"], activeSheetMediaId: "sheet_auri"),
    RosterMentionResolver.Entry(id: "char_mara", name: "Mara", kind: .character, referenceMediaIds: ["loose_3"]),
    RosterMentionResolver.Entry(id: "obj_lantern", name: "Lantern", kind: .object, referenceMediaIds: ["l1", "l2", "l3"]),
]

private let items = [
    item("sheet_auri", kind: "character_sheet"),
    item("loose_1"), item("loose_2"), item("loose_3"),
    item("l1"), item("l2"), item("l3"),
]

private let lens = ProjectLens(lensId: "lens_1", heroImages: [plannedRow()])

@Suite("Planned frame defaults law")
struct PlannedFrameDefaultsTests {
    @Test("The request carries the cleaned prompt, the authored tokens, sheet-only characters, and the loose ladder for objects")
    func requestShape() throws {
        let stack = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase))
        let request = LensPlannedFrameDefaults.request(
            planned: plannedRow(), lens: lens, stack: stack,
            styleSlot: nil, styleCatalogVersion: "cat_9",
            mentionEntries: entries, mentionItems: items, fileExists: { _ in true }
        )
        #expect(request.prompt == "Auri waits at the quay with Lantern.")
        #expect(request.authoredPrompt == "@Auri waits at the quay with @Lantern.")
        #expect(request.styleMode == .none)
        #expect(request.styleOverrideSlot == nil)
        #expect(request.styleOverrideCatalogVersion == "")
        #expect(request.promptEnrichmentDisabled == true)
        #expect(request.stabilityStrength == nil)
        #expect(request.moodInfluences == nil)
        #expect(request.medium == nil)
        let ids = (request.promptImageAttachments ?? []).map(\.sourceId)
        #expect(ids == ["sheet_auri", "l1", "l2"])
        #expect(request.promptImageAttachments?.first?.label == "Auri — reference sheet")
    }

    @Test("A sheetless character attaches its leading source photos — never nothing while sources exist")
    func sheetlessCharacterAttachesLeadingSources() throws {
        let stack = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase))
        let request = LensPlannedFrameDefaults.request(
            planned: plannedRow(sourcePrompt: "@Mara at the pier."), lens: lens, stack: stack,
            styleSlot: nil, styleCatalogVersion: "",
            mentionEntries: entries, mentionItems: items, fileExists: { _ in true }
        )
        #expect(request.prompt == "Mara at the pier.")
        let attachments = request.promptImageAttachments ?? []
        #expect(attachments.map(\.sourceId) == ["loose_3"])
        #expect(attachments.first?.label == "Mara")
    }

    @Test("A roster composite sheet rides alone for its character")
    func compositeSheetRidesAlone() {
        let composite = item("comp_mara", kind: "roster_composite_sheet")
        let entry = RosterMentionResolver.Entry(id: "char_mara", name: "Mara", kind: .character, referenceMediaIds: ["comp_mara", "loose_3"])
        let attachments = LensPlannedFrameDefaults.mentionAttachments(
            for: [entry], items: items + [composite], fileExists: { _ in true }
        )
        #expect(attachments.map(\.sourceId) == ["comp_mara"])
        #expect(attachments.first?.label == "Mara — reference sheet")
    }

    @Test("The plan's style slot rides with describe-in-prompt and its catalog version")
    func styleSlotRides() throws {
        let stack = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase))
        let slot = LensStyleTreatmentSlot(styleId: "s9", label: "Sunlit", collection: "", hueHex: "", url: "", weight: 100)
        let request = LensPlannedFrameDefaults.request(
            planned: plannedRow(), lens: lens, stack: stack,
            styleSlot: slot, styleCatalogVersion: "cat_9",
            mentionEntries: entries, mentionItems: items, fileExists: { _ in true }
        )
        #expect(request.styleMode == .describeStyleInPrompt)
        #expect(request.styleOverrideSlot?.styleId == "s9")
        #expect(request.styleOverrideCatalogVersion == "cat_9")
    }

    @Test("Provider caps come from the shared merge law; Stability carries the row's strength")
    func providerCaps() throws {
        let fal = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.falFluxSchnell))
        let falRequest = LensPlannedFrameDefaults.request(
            planned: plannedRow(), lens: lens, stack: fal,
            styleSlot: nil, styleCatalogVersion: "",
            mentionEntries: entries, mentionItems: items, fileExists: { _ in true }
        )
        let falIds = (falRequest.promptImageAttachments ?? []).map(\.sourceId)
        // The stack's own capacity law decides: a text-only stack carries no
        // attachment at all; a slot-capped one keeps the sheet first.
        if case .textOnly = fal.frameReferenceCapacity {
            #expect(falIds.isEmpty)
        } else {
            #expect(falIds.count <= 3)
            #expect(falIds.first == "sheet_auri")
        }
        #expect(falRequest.stabilityStrength == nil)

        let stability = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.stabilityUltra))
        let stabilityRequest = LensPlannedFrameDefaults.request(
            planned: plannedRow(), lens: lens, stack: stability,
            styleSlot: nil, styleCatalogVersion: "",
            mentionEntries: entries, mentionItems: items, fileExists: { _ in true }
        )
        #expect(stabilityRequest.stabilityStrength == 0.4)
    }

    @Test("A missing sheet file falls back to the leading source photos instead of lying")
    func missingSheetFileFallsBackToSources() {
        let attachments = LensPlannedFrameDefaults.mentionAttachments(
            for: [entries[0]], items: items, fileExists: { !$0.contains("sheet_auri") }
        )
        #expect(attachments.map(\.sourceId) == ["loose_1", "loose_2"])
    }
}
