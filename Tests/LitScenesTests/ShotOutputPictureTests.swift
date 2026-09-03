import Foundation
import Testing
@testable import LitScenes

// The output-space picture reference drawn on the SOURCE lane, and the lane
// header resolver that keeps every track header exactly one width.

private func pictureFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor \(id)",
        status: "ready"
    )
}

private let pictureFrames: [String: ProjectLensHeroImage] = [
    "f1": pictureFrame("f1"),
    "f2": pictureFrame("f2"),
    "f3": pictureFrame("f3")
]

private func pictureAssembly(_ shot: ProjectShot, clipDurations: [String: Double]) -> ShotCutAssembly {
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: pictureFrames,
        mediaLookup: [:],
        meaningNodes: []
    )
    return shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: clipDurations,
        fileExists: { _ in true }
    )
}

/// Two generated segments, each with a saved clip on disk.
private func twoSegmentShot() -> ProjectShot {
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "t0",
        updatedAt: "t0"
    )
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/a.mp4",
        updatedAt: "t0"
    ))
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f2",
        endFrameImageId: "f3",
        clipPath: "/tmp/b.mp4",
        updatedAt: "t0"
    ))
    let shot = ProjectShot(
        shotId: "shot_picture",
        name: "Picture",
        entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
            ShotFrameEntry(entryId: "e3", frameImageId: "f3")
        ]
    )
    return shot.upsertingRenderVersion(artifact, activate: true, now: "t0")
}

@Test func outputPictureSegmentsCoverTheOutputTimelineInOrder() throws {
    let assembly = pictureAssembly(
        twoSegmentShot(),
        clipDurations: ["/tmp/a.mp4": 4, "/tmp/b.mp4": 6]
    )
    let segments = assembly.outputPictureSegments
    try #require(segments.count == 2)
    #expect(segments.map(\.ordinal) == [1, 2])
    #expect(segments[0].outputStartSeconds == 0)
    // Contiguous, and covering the whole output.
    #expect(abs(segments[1].outputStartSeconds - segments[0].outputEndSeconds) < 0.000_1)
    #expect(abs(segments[1].outputEndSeconds - assembly.outputSeconds) < 0.000_1)

    // One interior splice, where the two segments meet.
    let splices = assembly.outputSplices
    try #require(splices.count == 1)
    #expect(splices[0].kind == .segmentJoin)
    #expect(abs(splices[0].outputSeconds - segments[0].outputEndSeconds) < 0.000_1)
}

@Test func aRazorInsideOneBandStaysOnePictureSegmentWithASplice() throws {
    var shot = twoSegmentShot()
    // Remove a second out of the middle of the FIRST segment.
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(
            segmentKey: "f1>f2",
            clipPath: "/tmp/a.mp4",
            startSeconds: 1,
            endSeconds: 2
        )
    ])
    let assembly = pictureAssembly(shot, clipDurations: ["/tmp/a.mp4": 4, "/tmp/b.mp4": 6])

    // The razor split the band into two playback items, but the PICTURE is
    // continuous: one segment per band, marked by a zero-width splice.
    try #require(assembly.playbackItems.count == 3)
    let segments = assembly.outputPictureSegments
    try #require(segments.count == 2)
    #expect(segments.map(\.ordinal) == [1, 2])

    let splices = assembly.outputSplices
    try #require(splices.count == 2)
    #expect(splices.map(\.kind) == [.razorSplice, .segmentJoin])
    // A razor costs no output time — the splice sits where the two kept
    // stretches meet, not where the removed second used to be.
    #expect(abs(splices[0].outputSeconds - 1) < 0.000_1)
    #expect(splices[0].outputSeconds < splices[1].outputSeconds)
}

/// The bridge-drift pin. `planClips.outputStartSeconds` advances only over
/// keep ranges, so deriving the source lane from it put every band after a
/// generated bridge earlier than the picture it belongs to — against an
/// `outputSeconds` that DOES include the bridge.
@Test func aGeneratedBridgeIsItsOwnSegmentAndPushesEverythingAfterIt() throws {
    var shot = twoSegmentShot()
    let cut = ShotSegmentCutRange(
        cutId: "cut_1",
        segmentKey: "f1>f2",
        clipPath: "/tmp/a.mp4",
        startSeconds: 1,
        endSeconds: 2,
        joinRepair: ShotRazorJoinRepair(mode: .generatedBridge, activeBridgeVersionId: "bridge_1")
    )
    shot.cutList = ShotCutList(segmentCuts: [cut])
    shot.joinBridgeVersions = [ShotJoinBridgeArtifact(
        versionId: "bridge_1",
        cutId: cut.id,
        sourceSegmentKey: "f1>f2",
        sourceClipPath: "/tmp/a.mp4",
        cutStartSeconds: 1,
        cutEndSeconds: 2,
        durationSeconds: 2,
        status: "ready",
        videoPath: "/tmp/bridge.mp4"
    )]
    let assembly = pictureAssembly(
        shot,
        clipDurations: ["/tmp/a.mp4": 4, "/tmp/b.mp4": 6, "/tmp/bridge.mp4": 2]
    )

    let bridgeItem = try #require(assembly.playbackItems.first { $0.isBridge })
    #expect(abs(bridgeItem.durationSeconds - 2) < 0.000_1)

    let segments = assembly.outputPictureSegments
    let bridgeSegment = try #require(segments.first { $0.isBridge })
    #expect(abs(bridgeSegment.outputSeconds - 2) < 0.000_1)

    // Everything after the bridge starts after it — the drift this fixes.
    let afterBridge = segments.filter { $0.outputStartSeconds > bridgeSegment.outputStartSeconds }
    #expect(!afterBridge.isEmpty)
    for segment in afterBridge {
        #expect(segment.outputStartSeconds >= bridgeSegment.outputEndSeconds - 0.000_1)
    }
    // Segments stay contiguous and still cover the whole output.
    #expect(abs((segments.last?.outputEndSeconds ?? 0) - assembly.outputSeconds) < 0.000_1)
    for (index, segment) in segments.enumerated() where index > 0 {
        #expect(abs(segment.outputStartSeconds - segments[index - 1].outputEndSeconds) < 0.000_1)
    }

    #expect(assembly.outputSplices.contains { $0.kind == .bridgeIn })
    #expect(assembly.outputSplices.contains { $0.kind == .bridgeOut })
}

@Test func noSpliceIsDrawnAtTheStartOrEndOfTheOutput() {
    let assembly = pictureAssembly(
        twoSegmentShot(),
        clipDurations: ["/tmp/a.mp4": 4, "/tmp/b.mp4": 6]
    )
    for splice in assembly.outputSplices {
        #expect(splice.outputSeconds > 0)
        #expect(splice.outputSeconds < assembly.outputSeconds)
    }
}

// MARK: - Lane head resolver

private func headRegion(
    _ regionId: String,
    lane: String,
    label: String = "Song",
    mediaId: String = "m1"
) -> ShotAudioRegion {
    ShotAudioRegion(
        regionId: regionId,
        laneId: lane,
        label: label,
        path: "/tmp/\(regionId).mp3",
        mediaId: mediaId,
        durationSeconds: 2
    )
}

/// The Look-mode regression pin: with the timeline strip replaced by the Look
/// control bar, the mic lane's header is the ONLY recording affordance on
/// screen, so it must resolve in every control mode.
@Test func microphoneLaneAlwaysCarriesARecordAction() {
    for mode: ShotMicrophoneControlMode in [.idle, .countIn(3), .recording, .finalizing] {
        let head = shotAudioLaneHead(
            laneId: ShotAudioLaneId.microphone,
            laneLabel: "Mic",
            isEnabled: true,
            laneVolume: 1,
            regions: [],
            missingRegionIds: [],
            emptyText: "NO TAKES",
            unit: "TAKE",
            hasPickerTargets: false,
            microphoneMode: mode,
            microphoneLevel: 0.3
        )
        guard case .record = head.action else {
            Issue.record("microphone lane lost its record action in \(mode)")
            continue
        }
        #expect(head.inputLevel != nil)
    }

    let clip = shotAudioLaneHead(
        laneId: ShotAudioLaneId.clip,
        laneLabel: "Clip",
        isEnabled: true,
        laneVolume: 1,
        regions: [],
        missingRegionIds: [],
        emptyText: "NO CLIP",
        unit: "CLIP",
        hasPickerTargets: true
    )
    #expect(clip.action == .none)
    #expect(clip.inputLevel == nil)
}

@Test func chipTextIsTruthfulForEmptyOneAndMany() {
    func chip(_ regions: [ShotAudioRegion], missing: Set<String> = []) -> ShotAudioLaneHead.Chip {
        shotAudioLaneHead(
            laneId: ShotAudioLaneId.clip,
            laneLabel: "Clip",
            isEnabled: true,
            laneVolume: 1,
            regions: regions,
            missingRegionIds: missing,
            emptyText: "NO CLIP",
            unit: "CLIP",
            hasPickerTargets: true
        ).chip
    }
    #expect(chip([]).text == "NO CLIP")
    #expect(chip([]).tone == .faint)
    #expect(chip([headRegion("r1", lane: ShotAudioLaneId.clip)]).text == "SONG")
    #expect(chip([
        headRegion("r1", lane: ShotAudioLaneId.clip),
        headRegion("r2", lane: ShotAudioLaneId.clip)
    ]).text == "2 CLIPS")

    // A missing file outranks the count — it is the state that needs acting on.
    let withMissing = chip(
        [
            headRegion("r1", lane: ShotAudioLaneId.clip),
            headRegion("r2", lane: ShotAudioLaneId.clip),
            headRegion("r3", lane: ShotAudioLaneId.clip)
        ],
        missing: ["r2"]
    )
    #expect(withMissing.text == "MISSING CLIP")
    #expect(withMissing.tone == .rust)
}

@Test func sourceChipIsSelectorOnlyAndMicChipClosesWhileRecording() {
    let quietSource = shotAudioLaneHead(
        laneId: ShotAudioLaneId.source,
        laneLabel: "Source",
        isEnabled: true,
        laneVolume: 1,
        regions: [],
        missingRegionIds: [],
        emptyText: "NO SOURCE",
        unit: "SPAN",
        hasPickerTargets: false
    )
    // Source audio rides the picture: nothing to pick, so the chip is quiet.
    #expect(!quietSource.chip.isActionable)

    // Re-routing mid-take would rewrite what is being recorded.
    let recording = shotAudioLaneHead(
        laneId: ShotAudioLaneId.microphone,
        laneLabel: "Mic",
        isEnabled: true,
        laneVolume: 1,
        regions: [headRegion("r1", lane: ShotAudioLaneId.microphone)],
        missingRegionIds: [],
        emptyText: "NO TAKES",
        unit: "TAKE",
        hasPickerTargets: true,
        microphoneMode: .recording,
        microphoneLevel: 0.5
    )
    #expect(!recording.chip.isActionable)
}

@Test func regionSelectorAppearsOnlyAboveOneRegion() {
    #expect(!shotAudioLaneOffersRegionSelector(regionCount: 0))
    #expect(!shotAudioLaneOffersRegionSelector(regionCount: 1))
    #expect(shotAudioLaneOffersRegionSelector(regionCount: 2))
}

@Test func headKnowsWhichLaneOwnsTheSelection() {
    let regions = [
        headRegion("r1", lane: ShotAudioLaneId.clip),
        headRegion("r2", lane: ShotAudioLaneId.clip)
    ]
    func head(selected: String?) -> ShotAudioLaneHead {
        shotAudioLaneHead(
            laneId: ShotAudioLaneId.clip,
            laneLabel: "Clip",
            isEnabled: true,
            laneVolume: 1,
            regions: regions,
            missingRegionIds: [],
            emptyText: "NO CLIP",
            unit: "CLIP",
            hasPickerTargets: true,
            selectedRegionId: selected
        )
    }
    #expect(head(selected: "r2").ownsSelection)
    #expect(!head(selected: "elsewhere").ownsSelection)
    #expect(!head(selected: nil).ownsSelection)
}

// MARK: - The SOURCE header stops lying about its spans

@Test func sourceLaneHeaderCountsItsSpansAndGoesBrassWhenShaped() {
    func head(_ spans: [ShotAudioRegion]) -> ShotAudioLaneHead {
        shotAudioLaneHead(
            laneId: ShotAudioLaneId.source,
            laneLabel: "Source",
            isEnabled: true,
            laneVolume: 1,
            regions: spans,
            missingRegionIds: [],
            emptyText: "NO SOURCE",
            unit: "SPAN",
            hasPickerTargets: false,
            hasOperatorAttenuation: spans.contains { $0.isMuted || $0.gain < 1 }
        )
    }
    func span(_ id: String, gain: Double = 1, isMuted: Bool = false) -> ShotAudioRegion {
        ShotAudioRegion(
            regionId: "source_span:\(id)",
            laneId: ShotAudioLaneId.source,
            label: "SPAN \(id)",
            durationSeconds: 3,
            gain: gain,
            isMuted: isMuted
        )
    }

    // A rendered cut with three spans reads its real count, and the lane stops
    // printing permanently faint.
    let three = head([span("1"), span("2"), span("3")])
    #expect(three.chip.text == "3 SPANS")
    #expect(three.chip.tone == .ink)
    #expect(three.isAvailable)
    #expect(three.chip.isActionable)
    #expect(three.chip.help == "Select one of this cut's source spans")

    // One muted span colours the chip brass — never rust, which stays reserved
    // for a missing file.
    let shaped = head([span("1"), span("2", isMuted: true), span("3")])
    #expect(shaped.chip.tone == .brass)
    // Attenuation short of a mute counts too.
    #expect(head([span("1"), span("2", gain: 0.4)]).chip.tone == .brass)

    // An unrendered cut still has nothing to say.
    let none = head([])
    #expect(none.chip.text == "NO SOURCE")
    #expect(none.chip.tone == .faint)
    #expect(!none.isAvailable)

    // A single span offers no chooser, but is not empty either.
    let one = head([span("1")])
    #expect(one.isAvailable)
    #expect(!one.chip.isActionable)
}

@Test func sourceLaneSelectionIsOwnedBySpanIdsNotRegionIds() {
    let spans = [
        ShotAudioRegion(regionId: "source_span:entry:a>b", laneId: ShotAudioLaneId.source, durationSeconds: 2),
        ShotAudioRegion(regionId: "source_span:entry:b>c", laneId: ShotAudioLaneId.source, durationSeconds: 2)
    ]
    func head(selected: String?) -> ShotAudioLaneHead {
        shotAudioLaneHead(
            laneId: ShotAudioLaneId.source,
            laneLabel: "Source",
            isEnabled: true,
            laneVolume: 1,
            regions: spans,
            missingRegionIds: [],
            emptyText: "NO SOURCE",
            unit: "SPAN",
            hasPickerTargets: false,
            selectedRegionId: selected
        )
    }
    #expect(head(selected: "source_span:entry:b>c").ownsSelection)
    // A real region id must never light up the source lane's header.
    #expect(!head(selected: "audio_region_abc").ownsSelection)
    #expect(!head(selected: nil).ownsSelection)
}
