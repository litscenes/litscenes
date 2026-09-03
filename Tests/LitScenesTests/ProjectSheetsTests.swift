import AppKit
import Foundation
import Testing
@testable import LitScenes

// MARK: - Drawing

private func sheetTestImage(width: CGFloat = 64, height: CGFloat = 48) -> NSImage {
    let image = NSImage(size: CGSize(width: width, height: height), flipped: true) { rect in
        NSColor.systemTeal.setFill()
        rect.fill()
        return true
    }
    return image
}

@Test
func coverSheetRendersFromClaimAndSkipsEmptyContent() {
    var content = ProjectSheet.CoverContent()
    // Nothing to say — no sheet.
    #expect(ProjectSheet.renderCoverPNG(content: content) == nil)

    content.projectTitle = "anger"
    content.claim = "This Scene asserts that rage is the only honest response."
    content.visualSummary = "A red-and-black descent through civic ruin."
    content.termLines = [("Motifs", ["tiered seating", "locked gates"]), ("Texture", [])]
    content.palette = [("Crimson", "#8E1B1B"), ("Ink", "#1B1711")]
    content.storyTitle = "The Rank That Screams"
    let png = ProjectSheet.renderCoverPNG(content: content)
    #expect(png != nil)
    if let png, let rep = NSBitmapImageRep(data: png) {
        #expect(CGFloat(rep.pixelsWide) == ProjectSheet.canvasSize.width)
        #expect(CGFloat(rep.pixelsHigh) == ProjectSheet.canvasSize.height)
    }
}

@Test
func gridSheetRendersUpToSixCellsAndRefusesEmpty() {
    #expect(ProjectSheet.renderGridPNG(kind: .frames, title: "anger", cells: []) == nil)
    let cells = (0..<8).map { (image: sheetTestImage(), caption: "PANEL \($0)") }
    let png = ProjectSheet.renderGridPNG(kind: .frames, title: "anger", cells: cells)
    #expect(png != nil)
    if let png, let rep = NSBitmapImageRep(data: png) {
        #expect(CGFloat(rep.pixelsWide) == ProjectSheet.canvasSize.width)
        #expect(CGFloat(rep.pixelsHigh) == ProjectSheet.canvasSize.height)
    }
}

// MARK: - Manifest

@Test
func manifestRoundTripsAndDecodesTolerantly() throws {
    var manifest = ProjectSheetManifest()
    manifest.projectId = "p1"
    manifest.projectTitle = "anger"
    manifest.claim = "Rage is the only honest response."
    manifest.motifTerms = ["tiered seating"]
    manifest.paletteSwatches = [.init(name: "Crimson", hex: "#8E1B1B")]
    manifest.cast = [.init(characterId: "char_1", name: "Mara Voss", referenceMediaIds: ["m1"])]
    manifest.frames = [.init(imageId: "img_1", label: "Rank Gate Approach", sourcePrompt: "@Mara Voss at the gate")]
    manifest.sheets = [.init(kind: "cover", mediaId: "genmedia_abc", filename: "project_sheet_cover.png")]

    let encoded = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(ProjectSheetManifest.self, from: encoded)
    #expect(decoded == manifest)

    // Tolerant decode: a minimal (older/foreign) payload still opens.
    let minimal = Data(#"{"projectId":"p2"}"#.utf8)
    let sparse = try JSONDecoder().decode(ProjectSheetManifest.self, from: minimal)
    #expect(sparse.projectId == "p2")
    #expect(sparse.schemaVersion == ProjectSheetManifest.currentSchemaVersion)
    #expect(sparse.frames.isEmpty)
}

// MARK: - Registration

@Test
func projectSheetKindIsGeneratedMediaSoRescansPreserveIt() {
    #expect(MediaItemRecord(
        mediaId: "m1",
        sourceId: MediaItemRecord.generatedMediaSourceId,
        kind: .image,
        filename: "project_sheet_cover.png",
        path: "/tmp/project_sheet_cover.png",
        relativePath: "project_sheet_cover.png",
        byteCount: 1,
        modifiedAt: "",
        width: 1_920,
        height: 1_080,
        durationSeconds: nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "",
        scanError: nil,
        derivativeKind: MediaItemRecord.projectSheetDerivativeKind,
        sourceMediaId: nil
    ).isGeneratedMedia)
}

@Test
func creationsInventoryGroupsProjectSheets() {
    let sheet = MediaItemRecord(
        mediaId: "m_sheet",
        sourceId: MediaItemRecord.generatedMediaSourceId,
        kind: .image,
        filename: "project_sheet_cover.png",
        path: "/tmp/project_sheet_cover.png",
        relativePath: "project_sheet_cover.png",
        byteCount: 1,
        modifiedAt: "",
        width: 1_920,
        height: 1_080,
        durationSeconds: nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "",
        scanError: nil,
        derivativeKind: MediaItemRecord.projectSheetDerivativeKind,
        sourceMediaId: nil
    )
    let groups = creationsInventory(items: [sheet], lenses: [])
    #expect(groups.contains { $0.kind == .sheets && $0.refs.count == 1 })
}

/// A collected frame has no footage parent to nest under, so Creations is the
/// only place it can surface. Before this, `video_frame` fell through the
/// switch and the still was invisible everywhere in Scenes.
@Test
func creationsInventoryGroupsCollectedShotFramesUnderShotArtifacts() {
    let frame = MediaItemRecord(
        mediaId: "genmedia_collected",
        sourceId: MediaItemRecord.generatedMediaSourceId,
        kind: .image,
        filename: "Shot Opening @3.5s.png",
        path: "/tmp/shotframe_abc.png",
        relativePath: "shotframe_abc.png",
        byteCount: 1,
        modifiedAt: "",
        width: 1_920,
        height: 1_080,
        durationSeconds: nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "",
        scanError: nil,
        derivativeKind: MediaItemRecord.collectedShotFrameDerivativeKind,
        sourceMediaId: "m_source_video"
    )
    let groups = creationsInventory(items: [frame], lenses: [])
    #expect(groups.contains { $0.kind == .shotArtifacts && $0.refs.count == 1 })
    // It is NOT an automatic extraction: it must not try to nest in the
    // source's stills tray, which filters on isExtractedVideoFrame.
    #expect(!frame.isExtractedVideoFrame)
    #expect(frame.isCollectedShotFrame)
    // Load-bearing: the scan preservation filter keeps derived items via
    // (isExtractedVideoFrame || isGeneratedMedia || isVideoTrim). Since the
    // first clause is now false, this is the ONLY thing standing between a
    // media rescan and the deletion of every frame the user ever collected.
    #expect(frame.isGeneratedMedia)
}

/// Frames collected before the new kind existed are still on disk under
/// `video_frame` with no source — they must surface too, not just new ones.
@Test
func collectedFramesArchivedUnderTheOldKindMigrateAndStayPut() {
    func frame(kind: String, sourceMediaId: String?) -> MediaItemRecord {
        MediaItemRecord(
            mediaId: "genmedia_old",
            sourceId: MediaItemRecord.generatedMediaSourceId,
            kind: .image,
            filename: "Shot Opening @3.5s.png",
            path: "/tmp/shotframe_old.png",
            relativePath: "shotframe_old.png",
            byteCount: 1,
            modifiedAt: "",
            width: 1_920,
            height: 1_080,
            durationSeconds: nil,
            nominalFrameRate: nil,
            thumbnailPath: "",
            videoStripPath: nil,
            scannedAt: "",
            scanError: nil,
            derivativeKind: kind,
            sourceMediaId: sourceMediaId
        )
    }

    // The stranded pairing — video_frame with no parent — becomes a collected frame.
    let stranded = frame(kind: MediaItemRecord.videoFrameDerivativeKind, sourceMediaId: "")
    let migrated = migratingCollectedShotFrames([stranded])
    #expect(migrated.first?.isCollectedShotFrame == true)
    #expect(creationsInventory(items: migrated, lenses: []).contains { $0.kind == .shotArtifacts })
    // Idempotent.
    #expect(migratingCollectedShotFrames(migrated).first?.isCollectedShotFrame == true)

    // A genuine extraction has a parent to nest under and must be left alone,
    // or it would disappear from its source clip's stills tray.
    let extracted = frame(kind: MediaItemRecord.videoFrameDerivativeKind, sourceMediaId: "m_clip")
    let untouched = migratingCollectedShotFrames([extracted])
    #expect(untouched.first?.isExtractedVideoFrame == true)
    #expect(untouched.first?.isCollectedShotFrame == false)
}
