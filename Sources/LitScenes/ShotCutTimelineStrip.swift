import SwiftUI
import AVFoundation
import AppKit

// MARK: - Cut assembly (the single derivation playback, export, and the strip read)

/// One band of the shot timeline strip: a live plan segment resolved against
/// the active render version's saved clip. `clipPath` empty = not rendered
/// yet — the band occupies material time but plays nothing.
struct ShotStripBand: Identifiable {
    var segment: ShotRenderPlanSegment
    var segmentKey: String
    var displayIndex: Int
    var clipPath: String
    var label: String
    var isFootage: Bool
    /// The skip gesture's target (seam cut or entry skip); nil = unskippable.
    var skipTarget: ShotSkippedSegmentPlaceholder.RestoreAction?
    /// Footage only: the strip filmstrip / poster used as the band fill.
    var fillImagePath: String?
    /// Artifact band only: interior stitch-join offsets (band-local seconds),
    /// drawn as inert ticks — derived, ±3/24s, never snap magnets.
    var seamSeconds: [Double] = []

    var id: String { segment.id }
    var isRendered: Bool { !clipPath.isEmpty }
}

/// One ordered playback span. Source spans map one kept range back onto the
/// material strip; generated bridges map their inserted output duration
/// across the removed razor region that they repair.
struct ShotCutPlaybackItem: Identifiable {
    var itemId: String
    /// The DURABLE identity of the segment this span belongs to — the same
    /// placement key renders, prompt overrides, and razors already use, so it
    /// survives a re-render, a razor, and a reorder. `itemId` is positional
    /// and does not: anything persisted about "this segment" keys on THIS.
    /// Empty on bridges, which belong to a seam rather than a segment.
    var segmentKey: String = ""
    var url: URL
    var keepRange: ShotKeepRange?
    var trimFrames: Int = 0
    var transitionFramesBefore: Int = 0
    var includeAudio: Bool = true
    var outputStartSeconds: Double
    var durationSeconds: Double
    var materialStartSeconds: Double
    var materialEndSeconds: Double
    var cutId: String = ""
    /// This span shows its material back to front. Direction rides HERE and
    /// never on inverted bounds: `materialStartSeconds <= materialEndSeconds`
    /// holds on every item in both directions, which is what keeps
    /// `bandIndex(forMaterialSeconds:)` and the picture-segment merge working
    /// with no direction branch of their own.
    ///
    /// The span still plays FORWARD through its own file — the file is a baked
    /// reversed proxy and `keepRange` is in that proxy's coordinates — so the
    /// stitcher, the export, and `sourceCapture` need no direction branch
    /// either.
    var playsReversed: Bool = false
    /// Non-empty ⇒ this span is an ARRANGED COPY (a picture insertion), not
    /// base material. Output-segment merging must never fuse a copy with the
    /// material it copies.
    var insertionId: String = ""
    /// Output duration = kept span ÷ rate; the stitcher scales the inserted
    /// range (video AND audio) when this isn't 1.
    var playbackRate: Double = 1
    /// Which whole-output loop pass this span belongs to; 0 = the base pass.
    /// Repeated passes carry pass-suffixed `itemId`s (splice ids, re-chain
    /// maps, and SwiftUI identity all key on `itemId`) — `loopPass` is the
    /// honest marker segment merging and fingerprints filter on instead of
    /// parsing the id back apart.
    var loopPass: Int = 0

    var id: String { itemId }
    var isBridge: Bool { !cutId.isEmpty }
    var isInsertion: Bool { !insertionId.isEmpty }

    /// Where this span begins inside its own file. One definition, because two
    /// places deriving an in-point from `keepRange`/`trimFrames` is how a
    /// one-frame offset gets introduced later.
    var sourceHeadSeconds: Double {
        keepRange?.start ?? Double(trimFrames) / ShotAudioTiming.framesPerSecond
    }

    var stitchSpec: VideoChainMedia.StitchClipSpec {
        VideoChainMedia.StitchClipSpec(
            url: url,
            trimFrames: trimFrames,
            keepRanges: keepRange.map { [$0] },
            transitionFramesBefore: transitionFramesBefore,
            includeAudio: includeAudio,
            rate: playbackRate
        )
    }
}

/// Everything the cut layer derives from a shot: bands (1:1 with
/// `planClips`), the deterministic cut plan, ordered playback items, and the
/// material/output timeline mapping shared by strip, player, audio, export.
struct ShotCutAssembly {
    var bands: [ShotStripBand] = []
    var planClips: [ShotCutPlanClip] = []
    var playbackItems: [ShotCutPlaybackItem] = []
    /// Derived display state for every picture insertion — fresh copies also
    /// appear in `playbackItems`; inert copies appear ONLY here, badged.
    var insertionCells: [ShotInsertionCell] = []
    var outputSeconds: Double = 0
    var materialSeconds: Double = 0
    /// This assembly actually plays backwards — the cut layer asked for it AND
    /// the reversed proxies were ready. Deliberately not the same thing as
    /// `shot.cutList.isReversed`, which is only the request: while a bake is in
    /// flight the visible assembly is still the forward one. Cache keys read
    /// THIS, so the player reloads the moment the last proxy lands.
    var isReversed: Bool = false
    /// The whole-output repeat this assembly ACHIEVED (not the request): 1
    /// until `loopedShotCutAssembly` actually expanded the items — the same
    /// achieved-vs-requested doctrine as `isReversed` above.
    var outputLoopCount: Int = 1
    /// One pass's output length when looped; 0 ⇒ unlooped (read
    /// `outputSeconds`). Set exactly by the expansion, never derived by
    /// dividing, so float drift can't split the two.
    var baseOutputSeconds: Double = 0

    /// The playable clip specs for the player/export composition.
    var playableSpecs: [VideoChainMedia.StitchClipSpec] {
        playbackItems.map(\.stitchSpec)
    }

    var hasPlayableClips: Bool { !playbackItems.isEmpty }

    /// Output (player) time → material (strip) position. A reversed span walks
    /// its material from END down to START as output time advances.
    func materialSeconds(forOutputSeconds t: Double) -> Double {
        for item in playbackItems {
            guard t < item.outputStartSeconds + item.durationSeconds || item.id == playbackItems.last?.id else {
                continue
            }
            let progress = item.durationSeconds > 0
                ? min(max((t - item.outputStartSeconds) / item.durationSeconds, 0), 1)
                : 0
            let from = item.playsReversed ? item.materialEndSeconds : item.materialStartSeconds
            let to = item.playsReversed ? item.materialStartSeconds : item.materialEndSeconds
            return from + (to - from) * progress
        }
        return materialSeconds
    }

    /// Material (strip) position → output (player) time, snapping forward
    /// out of cut, skipped, or unrendered stretches.
    ///
    /// Scans in MATERIAL order, which is `playbackItems` order only while the
    /// cut plays forward — a reversed cut visits its material back to front, so
    /// walking the items in output order here would abandon the scan at the
    /// first span and pin every scrub to one band.
    func outputSeconds(forMaterialSeconds s: Double) -> Double {
        for item in materialOrderedItems {
            if s < item.materialStartSeconds {
                // The gap ends where this span's EARLIEST material appears,
                // which for a reversed span is the instant it finishes.
                return item.playsReversed
                    ? item.outputStartSeconds + item.durationSeconds
                    : item.outputStartSeconds
            }
            if s <= item.materialEndSeconds {
                let materialDuration = item.materialEndSeconds - item.materialStartSeconds
                let progress = materialDuration > 0
                    ? min(max((s - item.materialStartSeconds) / materialDuration, 0), 1)
                    : 0
                let travelled = item.playsReversed ? 1 - progress : progress
                return item.outputStartSeconds + item.durationSeconds * travelled
            }
        }
        return outputSeconds
    }

    /// `playbackItems` sorted by material position. Returns the array itself
    /// when nothing plays reversed — the forward derivation already emits
    /// material-ascending, and scrubbing calls this on every drag change.
    /// Output start breaks material ties deterministically: an arranged copy
    /// shares its source's material span, and Swift's sort is not stable.
    private var materialOrderedItems: [ShotCutPlaybackItem] {
        guard playbackItems.contains(where: \.playsReversed) else { return playbackItems }
        return playbackItems.sorted {
            $0.materialStartSeconds == $1.materialStartSeconds
                ? $0.outputStartSeconds < $1.outputStartSeconds
                : $0.materialStartSeconds < $1.materialStartSeconds
        }
    }

    /// Output (player) time → the SOURCE clip file and file-local seconds on
    /// screen there — razor, skip, and bridge aware (a bridge item maps into
    /// the bridge artifact's own file). Capture-grade, not frame-forensic: a
    /// dissolve overlap resolves to the incoming item, and the keepRange-less
    /// head uses the trimFrames offset.
    func sourceCapture(forOutputSeconds t: Double) -> (url: URL, fileSeconds: Double)? {
        for item in playbackItems {
            guard t < item.outputStartSeconds + item.durationSeconds
                || item.id == playbackItems.last?.id else {
                continue
            }
            let local = min(
                max(t - item.outputStartSeconds, 0),
                max(item.durationSeconds - 1.0 / 48.0, 0)
            )
            return (item.url, item.sourceHeadSeconds + local)
        }
        return nil
    }
}

/// One span of PICTURE on the output timeline — what actually plays, in the
/// order it plays. Distinct from `ShotStripBand`, which is material space and
/// keeps razored-out footage visible so cuts stay restorable.
struct ShotOutputPictureSegment: Identifiable, Equatable {
    /// Positional — fine for a ForEach within one render, never for anything
    /// persisted. `segmentKey` is the durable one.
    var id: String
    /// The durable placement key of the band this span came from; empty on a
    /// bridge, which belongs to a seam rather than a segment.
    var segmentKey: String = ""
    var ordinal: Int
    var outputStartSeconds: Double
    var outputEndSeconds: Double
    var isFootage: Bool
    var isBridge: Bool
    /// The band's file and label, carried so callers never re-derive them.
    var clipPath: String = ""
    var label: String = ""
    /// An arranged copy (picture insertion) — drawn as its own span, and never
    /// merged with the base material it copies.
    var isInsertion: Bool = false

    var outputSeconds: Double { max(outputEndSeconds - outputStartSeconds, 0) }
}

/// Where two output spans meet, and why. A razor splice costs zero output
/// time — which is exactly what the picture reference draws as a bare notch
/// while the strip above shows the same razor as an area of removed material.
enum ShotOutputSpliceKind: Equatable {
    case segmentJoin
    case razorSplice
    case bridgeIn
    case bridgeOut
}

struct ShotOutputSplice: Identifiable, Equatable {
    var id: String
    var outputSeconds: Double
    var kind: ShotOutputSpliceKind
}

extension ShotCutAssembly {
    /// Output-space picture spans, derived from `playbackItems` — the true,
    /// bridge-inclusive output ordering. Deliberately NOT from
    /// `planClips.outputStartSeconds`, whose cursor advances only over keep
    /// ranges: with a generated bridge in the shot those starts run early
    /// against an `outputSeconds` that does include the bridge.
    ///
    /// Consecutive source items from the same band merge into one span, so a
    /// razor inside a band reads as one continuous picture segment with a
    /// splice mark, not as two segments.
    ///
    /// `ordinal` numbers the MATERIAL band, not the play position, so a
    /// reversed cut reads 3, 2, 1 left to right. That is the honest statement:
    /// it tells the operator the cut now plays its last segment first.
    var outputPictureSegments: [ShotOutputPictureSegment] {
        var segments: [ShotOutputPictureSegment] = []
        var lastItemPass = 0
        for item in playbackItems {
            let bandIndex = bandIndex(forMaterialSeconds: item.materialStartSeconds)
            let isBridge = item.isBridge
            // An arranged copy shares its source's band and can sit output-
            // contiguous with it — it must never merge in either direction.
            // Loop passes must not merge either: a single-band shot's pass 2
            // starts band-adjacent and output-contiguous to pass 1's end, and
            // fusing them would draw one span across the loop seam.
            if !isBridge,
               !item.isInsertion,
               lastItemPass == item.loopPass,
               let bandIndex,
               let last = segments.last,
               !last.isBridge,
               !last.isInsertion,
               last.ordinal == bandIndex + 1,
               abs(last.outputEndSeconds - item.outputStartSeconds) < 1.0 / 240.0 {
                segments[segments.count - 1].outputEndSeconds =
                    item.outputStartSeconds + item.durationSeconds
                continue
            }
            lastItemPass = item.loopPass
            let band = bandIndex.flatMap { bands.indices.contains($0) ? bands[$0] : nil }
            segments.append(ShotOutputPictureSegment(
                id: item.itemId,
                segmentKey: isBridge ? "" : item.segmentKey,
                ordinal: isBridge ? 0 : ((bandIndex.map { $0 + 1 }) ?? segments.count + 1),
                outputStartSeconds: item.outputStartSeconds,
                outputEndSeconds: item.outputStartSeconds + item.durationSeconds,
                isFootage: band?.isFootage ?? false,
                isBridge: isBridge,
                clipPath: band?.clipPath ?? "",
                label: band?.label ?? "",
                isInsertion: item.isInsertion
            ))
        }
        return segments
    }

    /// Interior splices only: a mark at t=0 or t=end would state a boundary
    /// the axis already draws.
    var outputSplices: [ShotOutputSplice] {
        var splices: [ShotOutputSplice] = []
        for (index, item) in playbackItems.enumerated() where index > 0 {
            let previous = playbackItems[index - 1]
            let seconds = item.outputStartSeconds
            guard seconds > 0.000_1, seconds < outputSeconds - 0.000_1 else { continue }
            let kind: ShotOutputSpliceKind
            if item.isBridge {
                kind = .bridgeIn
            } else if previous.isBridge {
                kind = .bridgeOut
            } else if bandIndex(forMaterialSeconds: previous.materialStartSeconds)
                == bandIndex(forMaterialSeconds: item.materialStartSeconds) {
                kind = .razorSplice
            } else {
                kind = .segmentJoin
            }
            splices.append(ShotOutputSplice(
                id: "\(previous.itemId)>\(item.itemId)",
                outputSeconds: seconds,
                kind: kind
            ))
        }
        return splices
    }

    /// Which band a playback item came from, by material containment.
    ///
    /// Bands abut exactly, so the LAST band starting at or before this instant
    /// owns it. An epsilon on the upper bound instead would make every
    /// boundary ambiguous — the next band's first item would match the
    /// previous band and the two would wrongly merge into one segment.
    ///
    /// Direction-free by construction, and it must stay that way: it is passed
    /// `item.materialStartSeconds`, and a reversed item keeps its span an
    /// ordered interval (start <= end) rather than inverting its bounds. Were
    /// direction ever carried by inverted bounds, a reversed item would arrive
    /// here holding the HIGH end of its span and resolve to the next band.
    private func bandIndex(forMaterialSeconds seconds: Double) -> Int? {
        let epsilon = 1.0 / 240.0
        var match: Int?
        for (index, clip) in planClips.enumerated()
            where clip.materialStartSeconds <= seconds + epsilon {
            match = index
        }
        return match
    }
}

/// Stable identity for the picture the operator currently sees as Original.
/// Audio and Look state are excluded so voice timing/mix edits never stale a
/// paid visual finish. Paths, kept spans, transitions, active render, and
/// source identity fully describe the executable visual composition. Duration
/// is persisted separately on the Look and deliberately excluded here: media
/// track lengths load asynchronously, so including an estimate would make a
/// brand-new Look appear stale as soon as exact metadata arrived.
func shotLookVisualFingerprint(shot: ProjectShot, assembly: ShotCutAssembly) -> String {
    // Pass 0 only: the Look's visual identity is the BASE edit — a whole-
    // output loop repeats the looked output, it does not change what was
    // looked. Filtering (rather than a conditional token) emits the byte-
    // identical historical string at every N, so applying or removing a loop
    // can never brand an active Look "OLDER EDIT".
    let spanIdentity = assembly.playbackItems.filter { $0.loopPass == 0 }.map { item in
        let keep = item.keepRange.map {
            "\(String(format: "%.4f", $0.start))-\(String(format: "%.4f", $0.end))"
        } ?? "all"
        // Conditional so every pre-insertion shot keeps its exact historical
        // fingerprint (Looks must not stale on upgrade). Rate is visual
        // timing; per-copy mute is audio and stays excluded by the law above.
        let arranged = item.isInsertion || item.playbackRate != 1
            ? "#rate=\(String(format: "%.3f", item.playbackRate))"
            : ""
        return "\(item.url.path)#\(keep)#trim=\(item.trimFrames)#transition=\(item.transitionFramesBefore)#cut=\(item.cutId)\(arranged)"
    }.joined(separator: "|")
    let legacyPath = shot.activeRenderVersion?.videoPath.trimmed ?? shot.renderArtifact?.videoPath.trimmed ?? ""
    return shortHash(
        "render=\(shot.activeRenderVersionId)|spans=\(spanIdentity)|legacy=\(legacyPath)|profile=1280x720@24",
        length: 32
    )
}

/// Resolves the live plan against the PLAYABLE render version's saved clips
/// and the cut layer — the selected version when ready, else the newest ready
/// one, so playback survives an in-flight re-render instead of resolving the
/// generating version's empty clips. Durations come from `clipDurationsByPath`
/// when the caller has loaded them (honest lengths), else stack/footage
/// estimates.
func shotCutAssembly(
    shot: ProjectShot,
    planSegments: [ShotRenderPlanSegment],
    clipDurationsByPath: [String: Double],
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> ShotCutAssembly {
    let version = shot.playableRenderVersion
    let handoffTrimSeconds = 3.0 / 24.0
    let boundaryRightEntryIds = Set(shot.sourceBoundaries.map(\.rightEntryId))

    func seedClip(
        placementStartEntryId: String,
        placementEndEntryId: String,
        startFrameImageId: String,
        endFrameImageId: String
    ) -> ShotRenderSegmentClip? {
        if !placementStartEntryId.isEmpty || !placementEndEntryId.isEmpty,
           let exact = shot.seedSegmentClips.first(where: {
               $0.placementStartEntryId == placementStartEntryId
                   && $0.placementEndEntryId == placementEndEntryId
           }) {
            return exact
        }
        return shot.seedSegmentClips.first {
            $0.placementStartEntryId.isEmpty
                && $0.placementEndEntryId.isEmpty
                && $0.startFrameImageId == startFrameImageId
                && $0.endFrameImageId == endFrameImageId
        }
    }

    var bands: [ShotStripBand] = []
    var inputs: [ShotCutPlanClipInput] = []
    var seenPlayable = false

    for segment in planSegments {
        switch segment {
        case .footage(let footageSegment):
            let clip = footageSegment.clip
            let saved = version?.segmentClip(
                placementStartEntryId: clip.entryId,
                placementEndEntryId: "",
                forStart: clip.footageKey,
                end: ""
            ) ?? seedClip(
                placementStartEntryId: clip.entryId,
                placementEndEntryId: "",
                startFrameImageId: clip.footageKey,
                endFrameImageId: ""
            )
            let path = (saved?.clipPath.trimmed.nilIfEmpty).flatMap { fileExists($0) ? $0 : nil } ?? ""
            let duration = clipDurationsByPath[path]
                ?? ((saved?.durationSeconds ?? 0) > 0 ? saved?.durationSeconds : nil)
                ?? clip.resolvedDurationSeconds
            let resetsHandoff = boundaryRightEntryIds.contains(clip.entryId)
            let trim = (seenPlayable && footageSegment.joinsPrevious && !resetsHandoff)
                ? handoffTrimSeconds
                : 0
            let segmentKey = saved?.placementKey ?? footageSegment.placementKey
            bands.append(ShotStripBand(
                segment: segment,
                segmentKey: segmentKey,
                displayIndex: footageSegment.displayIndex,
                clipPath: path,
                label: "\(footageSegment.displayIndex + 1) · FOOTAGE",
                isFootage: true,
                skipTarget: .entry(entryId: clip.entryId),
                fillImagePath: clip.videoStripPath ?? clip.thumbnailPath.nilIfEmpty
            ))
            inputs.append(ShotCutPlanClipInput(
                segmentKey: segmentKey,
                clipPath: path,
                durationSeconds: duration,
                leadingTrimSeconds: trim
            ))
            if !path.isEmpty { seenPlayable = true }
        case .generated(let item):
            let saved = version?.segmentClip(
                placementStartEntryId: item.pair.startPlacementEntryId,
                placementEndEntryId: item.pair.endPlacementEntryId,
                forStart: item.pair.start?.imageId ?? "",
                end: item.pair.end?.imageId ?? ""
            ) ?? seedClip(
                placementStartEntryId: item.pair.startPlacementEntryId,
                placementEndEntryId: item.pair.endPlacementEntryId,
                startFrameImageId: item.pair.start?.imageId ?? "",
                endFrameImageId: item.pair.end?.imageId ?? ""
            )
            let path = (saved?.clipPath.trimmed.nilIfEmpty).flatMap { fileExists($0) ? $0 : nil } ?? ""
            let duration = clipDurationsByPath[path]
                ?? ((saved?.durationSeconds ?? 0) > 0 ? saved?.durationSeconds : nil)
                ?? Double(item.renderStack.segmentSeconds)
            let resetsHandoff = boundaryRightEntryIds.contains(item.pair.startPlacementEntryId)
            let trim = seenPlayable && !resetsHandoff ? handoffTrimSeconds : 0
            let segmentKey = saved?.placementKey ?? item.pair.placementKey
            let genLabel = item.pair.start == nil
                ? "GEN · LEAD-IN"
                : "GEN\(item.touchesFootage ? " · BRIDGE" : "")"
            bands.append(ShotStripBand(
                segment: segment,
                segmentKey: segmentKey,
                displayIndex: item.displayIndex,
                clipPath: path,
                label: "\(item.displayIndex + 1) · \(genLabel)",
                isFootage: false,
                skipTarget: item.skipTarget,
                fillImagePath: nil
            ))
            inputs.append(ShotCutPlanClipInput(
                segmentKey: segmentKey,
                clipPath: path,
                durationSeconds: duration,
                leadingTrimSeconds: trim
            ))
            if !path.isEmpty { seenPlayable = true }
        case .artifactFallback:
            // Never produced by the plan generator — the fallback below is
            // this case's only constructor.
            break
        }
    }

    // THE ARTIFACT BAND FALLBACK ("cut what plays"): when the live plan
    // resolves NO playable clip but the playable version's full video exists,
    // the assembly emits one band over that mp4. Razor, trim, seek, export,
    // Send to Footage, YouTube, and the reel bake all operate on what is
    // actually on screen instead of going silently inert. Cuts key on
    // "artifact:<versionId>" and pin the videoPath — superseded by the next
    // resolving render (the take-pin doctrine), never migrated. Legacy
    // versionless artifacts stay on the whole-file fallback.
    if !inputs.contains(where: { !$0.clipPath.isEmpty }),
       let artifact = version,
       !artifact.versionId.trimmed.isEmpty {
        let videoPath = artifact.videoPath.trimmed
        let geometry = shotArtifactBandGeometry(artifact)
        let duration = clipDurationsByPath[videoPath] ?? geometry.durationSeconds
        if !videoPath.isEmpty, fileExists(videoPath), duration > 0 {
            let segmentKey = shotArtifactSegmentKey(versionId: artifact.versionId)
            let segmentCount = max(artifact.segmentCount, artifact.clipPaths.count)
            let roman = artifact.versionNumber > 0
                ? " \(FrameCreatorModal.romanNumeral(artifact.versionNumber))"
                : ""
            bands = [ShotStripBand(
                segment: .artifactFallback(ShotArtifactPlanSegment(
                    versionId: artifact.versionId,
                    versionNumber: artifact.versionNumber,
                    videoPath: videoPath,
                    segmentCount: segmentCount,
                    durationSeconds: duration,
                    seamSeconds: geometry.seamSeconds
                )),
                segmentKey: segmentKey,
                displayIndex: 0,
                clipPath: videoPath,
                label: "RENDER\(roman) · \(segmentCount) SEGMENT\(segmentCount == 1 ? "" : "S")",
                isFootage: false,
                // Skipping the only playable thing is meaningless; razor and
                // in/out are the honest tools here.
                skipTarget: nil,
                fillImagePath: nil,
                seamSeconds: geometry.seamSeconds
            )]
            inputs = [ShotCutPlanClipInput(
                segmentKey: segmentKey,
                clipPath: videoPath,
                durationSeconds: duration,
                leadingTrimSeconds: 0
            )]
        }
    }

    let plan = shotCutPlan(clips: inputs, cutList: shot.cutList)
    var playbackItems: [ShotCutPlaybackItem] = []
    var outputCursor = 0.0
    let epsilon = 1.0 / 240.0

    for (clipIndex, clip) in plan.clips.enumerated() where clip.isPlayable {
        let cuts = shot.cutList.segmentCuts
            .filter { $0.applies(toSegmentKey: clip.segmentKey, clipPath: clip.clipPath) }
        var transitionFramesIntoPreviousKeep = 0
        for (keepIndex, keep) in clip.keepRanges.enumerated() {
            var transitionFramesBefore = 0
            if keepIndex > 0 {
                let previous = clip.keepRanges[keepIndex - 1]
                let separatingCut = cuts.first {
                    abs($0.startSeconds - previous.end) <= epsilon
                        && abs($0.endSeconds - keep.start) <= epsilon
                }
                if let cut = separatingCut {
                    switch cut.joinRepair.mode {
                    case .hardCut:
                        break
                    case .dissolve:
                        let outgoingFrameCapacity = Int(floor(previous.seconds * 24 + 0.000_1))
                        let remainingAfterIncomingTransition = max(
                            outgoingFrameCapacity - transitionFramesIntoPreviousKeep / 2,
                            0
                        )
                        transitionFramesBefore = min(
                            cut.joinRepair.gapCappedDissolveFrames(gapSeconds: cut.seconds),
                            Int(floor(previous.seconds * 24 * 2 + 0.000_1)),
                            Int(floor(keep.seconds * 24 * 2 + 0.000_1)),
                            remainingAfterIncomingTransition * 2
                        )
                        transitionFramesBefore -= transitionFramesBefore % 2
                    case .generatedBridge:
                        if let artifact = shot.joinBridgeVersion(cut.joinRepair.activeBridgeVersionId),
                           artifact.isReady,
                           artifact.cutId == cut.id,
                           artifact.sourceSegmentKey == clip.segmentKey,
                           (cut.clipPath.isEmpty || artifact.sourceClipPath == clip.clipPath),
                           abs(artifact.cutStartSeconds - cut.startSeconds) <= epsilon,
                           abs(artifact.cutEndSeconds - cut.endSeconds) <= epsilon,
                           fileExists(artifact.videoPath) {
                            let materialStart = clip.materialStartSeconds + (cut.startSeconds - clip.headSeconds)
                            let materialEnd = clip.materialStartSeconds + (cut.endSeconds - clip.headSeconds)
                            let duration = clipDurationsByPath[artifact.videoPath] ?? artifact.durationSeconds
                            playbackItems.append(ShotCutPlaybackItem(
                                itemId: "bridge_\(artifact.versionId)",
                                // A bridge repairs a SEAM, not a segment — it
                                // belongs to no segment's audio.
                                segmentKey: "",
                                url: URL(fileURLWithPath: artifact.videoPath),
                                includeAudio: false,
                                outputStartSeconds: outputCursor,
                                durationSeconds: duration,
                                materialStartSeconds: materialStart,
                                materialEndSeconds: materialEnd,
                                cutId: cut.id
                            ))
                            outputCursor += duration
                        }
                    }
                }
            }

            let materialStart = clip.materialStartSeconds + (keep.start - clip.headSeconds)
            let materialEnd = clip.materialStartSeconds + (keep.end - clip.headSeconds)
            playbackItems.append(ShotCutPlaybackItem(
                itemId: "source_\(clipIndex)_\(keepIndex)_\(String(format: "%.3f", keep.start))",
                segmentKey: clip.segmentKey,
                url: URL(fileURLWithPath: clip.clipPath),
                keepRange: keep,
                transitionFramesBefore: transitionFramesBefore,
                outputStartSeconds: outputCursor,
                durationSeconds: keep.seconds,
                materialStartSeconds: materialStart,
                materialEndSeconds: materialEnd
            ))
            outputCursor += keep.seconds
            transitionFramesIntoPreviousKeep = transitionFramesBefore
        }
    }
    // THE ARRANGEMENT SPLICE: picture insertions land here, inside the one
    // forward derivation, so the player, export, Look flatten, Send to
    // Footage, and audio windows all see the same arranged output.
    let spliced = shotPictureInsertionSplice(
        insertions: shot.pictureInsertions,
        entries: shot.entries,
        planClips: plan.clips,
        playbackItems: playbackItems,
        // THE MATERIAL-WINDOW LAW: the same in/out pair `shotCutPlan` just
        // clamped the base keeps with — copies obey the trim handles too.
        shotInSeconds: shot.cutList.shotInSeconds,
        shotOutSeconds: shot.cutList.shotOutSeconds,
        activeTakePathsBySegmentKey: shotActiveTakePathsBySegmentKey(shot: shot),
        fileExists: fileExists
    )
    return ShotCutAssembly(
        bands: bands,
        planClips: plan.clips,
        playbackItems: spliced.playbackItems,
        insertionCells: spliced.cells,
        outputSeconds: spliced.outputSeconds,
        materialSeconds: plan.materialSeconds
    )
}

/// The assembly as the operator currently SEES it: `shotCutAssembly`, played
/// backwards when the cut layer says so.
///
/// Reverse is all-or-nothing. A cut whose proxies are still baking keeps
/// playing FORWARD rather than showing some spans backwards and some not — the
/// half-reversed state is not a smaller version of what was asked for, it is a
/// different thing, and it would be on screen for the length of an encode.
///
/// The proxies are read off the `ProjectShot` already in scope and gated by the
/// same injected `fileExists` that ready join bridges use, so this needs no new
/// parameters and no caller has to learn about reversal.
///
/// Deliberately separate from `shotCutAssembly`, which stays the pure forward
/// derivation: the Look flatten must resolve in the direction its Look was
/// made in.
///
/// The whole-output loop expands HERE, after direction — looped(reversed(base))
/// — so each pass plays the cut the operator sees. `includeOutputLoop: false`
/// is for derivations that must stay base-length: join/insertion ripple math,
/// Look source prep and its cost estimate, narration planning.
func shotVisibleCutAssembly(
    shot: ProjectShot,
    planSegments: [ShotRenderPlanSegment],
    clipDurationsByPath: [String: Double],
    includeOutputLoop: Bool = true,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> ShotCutAssembly {
    let forward = shotCutAssembly(
        shot: shot,
        planSegments: planSegments,
        clipDurationsByPath: clipDurationsByPath,
        fileExists: fileExists
    )
    let directed: ShotCutAssembly = {
        guard shot.cutList.isReversed else { return forward }
        let proxies = shot.readyReverseProxiesBySourcePath(fileExists: fileExists)
        let sources = Set(forward.playbackItems.map(\.url.path))
        guard !sources.isEmpty, sources.allSatisfy({ proxies[$0] != nil }) else { return forward }
        return reversedShotCutAssembly(forward, proxies: proxies)
    }()
    guard includeOutputLoop else { return directed }
    return loopedShotCutAssembly(directed, count: shot.cutList.outputLoopCount)
}

/// The strip's DISPLAY geometry: where each band and sliver sits, and the two
/// conversions between display x and material seconds.
///
/// Pure and value-typed so the mirror can be tested without a view. The mirror
/// lives HERE and nowhere else — the strip's interior is always forward
/// material seconds, and the cut list it writes is always forward clip-local
/// file seconds, which is why razor authoring never learns about reverse.
/// The strip's transient span selection, in forward material seconds — view
/// state only, never persisted. THE WYSIWYG COPY LAW resolves it to kept
/// material spans at copy time.
struct ShotStripSpanSelection: Equatable {
    var startMaterialSeconds: Double
    var endMaterialSeconds: Double

    var lowSeconds: Double { min(startMaterialSeconds, endMaterialSeconds) }
    var highSeconds: Double { max(startMaterialSeconds, endMaterialSeconds) }
    var seconds: Double { highSeconds - lowSeconds }
}

struct ShotStripLayout {
    var bandFrames: [Int: (x: CGFloat, width: CGFloat)] = [:]
    var sliverFrames: [(placeholder: ShotSkippedSegmentPlaceholder, x: CGFloat)] = []
    /// Arranged-copy cells (consolidated runs), keyed by the run leader's
    /// insertion id.
    var insertionFrames: [String: (x: CGFloat, width: CGFloat)] = [:]
    var contentStart: CGFloat = 0
    var contentEnd: CGFloat = 0
    var scale: CGFloat = 1
    /// Display x runs right to left. ONLY display x.
    var isReversed = false
    var planClips: [ShotCutPlanClip] = []
    var materialSeconds: Double = 0

    func x(forMaterialSeconds seconds: Double) -> CGFloat {
        for (index, clip) in planClips.enumerated() {
            guard let frame = bandFrames[index] else { continue }
            if seconds < clip.materialStartSeconds + clip.materialSeconds || index == planClips.count - 1 {
                let within = min(max(CGFloat(seconds - clip.materialStartSeconds) * scale, 0), frame.width)
                return isReversed ? frame.x + frame.width - within : frame.x + within
            }
        }
        return isReversed ? contentStart : contentEnd
    }

    func materialSeconds(atX x: CGFloat) -> Double {
        let atStartEdge = isReversed ? x >= contentEnd : x <= contentStart
        var best: Double = atStartEdge ? 0 : materialSeconds
        for (index, clip) in planClips.enumerated() {
            guard let frame = bandFrames[index] else { continue }
            if x < frame.x {
                best = isReversed
                    ? max(best, clip.materialStartSeconds + clip.materialSeconds)
                    : min(best, clip.materialStartSeconds)
                continue
            }
            if x <= frame.x + frame.width {
                let within = isReversed ? (frame.x + frame.width - x) : (x - frame.x)
                return clip.materialStartSeconds + Double(within / scale)
            }
        }
        return best
    }

    /// Pure frame containment on the already-mirrored layout, so this needs no
    /// direction branch of its own.
    func bandIndex(atX x: CGFloat) -> Int? {
        for (index, frame) in bandFrames where x >= frame.x && x <= frame.x + frame.width {
            return index
        }
        return nil
    }
}

// MARK: - Timeline strip

/// The shot's cut-layer instrument, under the player: provenance bands
/// (footage filmstrip vs generated plate), seam glyphs (≈ generated handoff,
/// ‖ hard splice), restorable skip slivers, brass in/out handles, razor
/// ranges, and the playhead. Every gesture here is FREE — it re-assembles
/// saved clips and never renders.
struct ShotCutTimelineStrip: View {
    let shot: ProjectShot
    let assembly: ShotCutAssembly
    let placeholders: [ShotSkippedSegmentPlaceholder]
    let playheadOutputSeconds: Double
    var onSeek: (Double) -> Void
    /// THE WINDOW COROLLARY: the modal's one viewport, panning this strip's
    /// display span in lockstep with the ruler and lanes.
    var viewport: ShotTimelineViewport = .fit
    /// The B blade's first mark (material seconds), drawn brass until the
    /// second press commits the razor range or ⎋ cancels it.
    var pendingBladeMaterialSeconds: Double? = nil
    /// Pauses playback before a picture edit lands (the pause law's picture
    /// half: razor commits and in/out trims change WHEN picture plays).
    var onPictureEditBegan: () -> Void = { }
    /// The strip's refusal voice: gestures that cannot act (razor on an
    /// unrendered band, seek with nothing playable) say why instead of
    /// silently doing nothing. The host shows it on its transport status.
    var onNotice: (String) -> Void = { _ in }
    /// Output-space audio landmarks pulled back into MATERIAL seconds by the
    /// owner (region edges, mic take bounds) — extra snap magnets so "cut
    /// where the audio ends" is a click, not an eyeball across the seam.
    var audioSnapMaterialSeconds: [Double] = []
    /// THE PROJECTION GHOST feed: the live draft's material seconds (+ snap
    /// state) during any picture-edit drag; (nil, false) on end. The owner
    /// projects through `assembly.outputSeconds(forMaterialSeconds:)` and the
    /// lane stack draws the re-projected brass line — the seam-law-honest way
    /// to show where a material drag lands against the audio.
    var onDragMaterialSecondsChanged: (_ seconds: Double?, _ isSnapped: Bool) -> Void = { _, _ in }
    /// Hoisted to the modal so THE ESCAPE LADDER can walk armed-razor and
    /// cut-selection rungs before closing.
    @Binding var isRazorMode: Bool
    @Binding var selectedCutId: String?
    /// The span selection (plain drag paints it; click still seeks) and the
    /// selected arranged-copy cell — hoisted so ⌘C/⌘V/⌘D/⌫ and THE ESCAPE
    /// LADDER live at the modal with the other transport state.
    @Binding var selectedSpan: ShotStripSpanSelection?
    @Binding var selectedInsertionId: String?
    /// nil = paste is possible right now; a string = the disabled reason
    /// (empty clipboard, paste-rung refusal) shown on the button.
    var cannotPasteReason: String? = nil
    var onCopySelection: () -> Void = { }
    var onPasteAtPlayhead: () -> Void = { }
    /// ⌘D — duplicate the selection right after itself (the loop gesture;
    /// copies are born muted per THE HYBRID AUDIO DEFAULT).
    var onDuplicateSelection: () -> Void = { }
    var onInsertionSetRate: (Set<String>, Double) -> Void = { _, _ in }
    var onInsertionSetMuted: (Set<String>, Bool) -> Void = { _, _ in }
    var onInsertionDelete: (Set<String>) -> Void = { _ in }
    var onInsertionRecopy: (String) -> Void = { _ in }
    var onInsertionAddLoopCopy: (ShotPictureInsertion) -> Void = { _ in }
    /// SECTION SPEED: the selected span razors out and a born-muted copy of
    /// it plays in the gap at this rate — one gesture, one undo.
    var onSetSectionRate: (Double) -> Void = { _ in }
    /// THE SCRUB LATCH: strip seeks pause on begin, resume on release iff
    /// playback was running. Razor drags are edits, not scrubs.
    var onScrubBegan: () -> Void = { }
    var onScrubEnded: () -> Void = { }
    var onSetCutList: (ShotCutList) -> Void
    var onSetEntrySkipped: (String, Bool) -> Void
    var onSetSeamStyle: (String, ShotSeamStyle) -> Void
    /// Restoring a skipped SEAM is not the explicit ≈ toggle: it must never
    /// delete a combined-cut boundary (THE SEAM BOUNDARY LAW), so it rides
    /// its own closure and the host applies the restore intent.
    var onRestoreSkippedSeam: (String) -> Void = { _ in }
    var hasFALCredential = false
    var isVideoRenderBlocked = false
    var activeShotJoinRenderId = ""
    var onSetJoinRepair: (String, ShotRazorJoinRepair) -> Void = { _, _ in }
    var onRestoreRazorCut: (String) -> Void = { _ in }
    var onRenderJoinBridge: (String, ShotJoinBridgeProvider, Int, String) -> Void = { _, _, _, _ in }
    var onPrepareJoinFrames: (String) async -> ShotJoinBoundaryPreview? = { _ in nil }
    var microphoneControlMode: ShotMicrophoneControlMode = .idle
    var isMicrophoneAvailable = true
    var onToggleMicrophoneRecording: () -> Void = {}
    /// Whether the CUT is REQUESTED reversed. Distinct from
    /// `assembly.isReversed`, which is whether it is actually playing that way
    /// yet — between the two sits the bake.
    var isReversed = false
    /// Whether the picture on screen is ACTUALLY running backwards.
    var isPlayingReversed = false
    /// Set only while a bake is queued or running. A value here disables the
    /// control, so it must never outlive the work.
    var reverseBakeProgress: Double?
    var onSetReversed: (Bool) -> Void = { _ in }

    /// Live drag state (material seconds); committed to the cut list on end.
    @State private var draftInSeconds: Double?
    @State private var draftOutSeconds: Double?
    @State private var isDraggingIn = false
    @State private var isDraggingOut = false
    @State private var razorDraft: (bandIndex: Int, start: Double, end: Double)?
    /// The live drag's chip position + snap state (material seconds) — feeds
    /// the timing chip and mirrors what `onDragMaterialSecondsChanged` told
    /// the owner, so chip, ghost, and magnet emphasis can never disagree.
    @State private var dragChipMaterialSeconds: Double?
    @State private var dragChipIsSnapped = false
    /// One refusal per razor gesture — onChanged streams, the notice must not.
    @State private var hasSentRazorRefusalNotice = false
    /// The selection being painted (plain drag, unarmed). Committed to
    /// `selectedSpan` on release; a sub-threshold drag is a click and seeks.
    @State private var selectionDraft: (start: Double, end: Double)?
    @State private var isSpeedPopoverOpen = false
    @State private var isLoopPopoverOpen = false
    /// The filmstrip's tile generator; the tile STORE is process-wide, so a
    /// remount (Look open/close, modal reopen) redraws from cache.
    @StateObject private var filmstripLoader = ShotFilmstripLoader()

    /// The strip's leading/trailing reserve IS the shared axis content inset,
    /// so its time-zero and time-end land at the same absolute x as the ruler
    /// and every audio lane below. Its interior mapping stays material space.
    private let handleWidth: CGFloat = ShotTimelineAxis.contentInset
    private let sliverWidth: CGFloat = 22
    private let stripHeight: CGFloat = 64

    private var inSeconds: Double {
        isDraggingIn ? (draftInSeconds ?? 0) : (shot.cutList.shotInSeconds ?? 0)
    }

    private var outSeconds: Double {
        let fallback = assembly.materialSeconds
        let stored = shot.cutList.shotOutSeconds ?? fallback
        return isDraggingOut ? (draftOutSeconds ?? fallback) : min(stored, fallback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            runtimeRow
            // Head and tail gutters put the strip's time axis in the same
            // column as the ruler and audio lanes. The tail slot is a real
            // reservation, not decoration: drop it and the axis breaks.
            HStack(spacing: 0) {
                pictureHead
                    .frame(width: ShotTimelineAxis.headWidth, alignment: .leading)
                GeometryReader { geometry in
                    stripBody(width: geometry.size.width)
                        // A panned window pushes bands past the plate; they
                        // clip away rather than smearing over the gutters.
                        .clipped()
                }
                Color.clear.frame(width: ShotTimelineAxis.tailWidth)
            }
            .frame(height: stripHeight)
            legendRow
        }
    }

    /// Names this block's space. The strip measures MATERIAL time so razors
    /// and restore-slivers stay visible; the lanes below measure OUTPUT time.
    /// Saying so is what makes two honest axes legible instead of confusing.
    private var pictureHead: some View {
        VStack(alignment: .leading, spacing: 2) {
            PlateLabel(text: "Picture", size: 7.5, weight: .semibold, color: PlateColor.ink)
            PlateLabel(
                text: "Material ~\(Int(assembly.materialSeconds.rounded()))s",
                size: 6.5,
                color: PlateColor.inkFaint
            )
        }
        .help("This strip measures material time — everything you have, including razored-out stretches, so cuts stay restorable. The ruler and audio lanes below measure output time: what actually plays. Both blocks start and end at the same place.")
    }

    // MARK: Rows

    private var runtimeRow: some View {
        HStack(spacing: 10) {
            PlateLabel(
                text: "Output · ~\(Int(assembly.outputSeconds.rounded()))s",
                size: 8.5,
                weight: .semibold,
                color: PlateColor.ink
            )
            if wasSecondsDiffers {
                PlateLabel(text: "(was ~\(Int(wasSeconds.rounded()))s)", size: 8.5, color: PlateColor.inkFaint)
            }
            if !placeholders.isEmpty {
                PlateLabel(text: "\(placeholders.count) skip\(placeholders.count == 1 ? "" : "s")", size: 8.5, color: PlateColor.inkFaint)
            }
            if !shot.cutList.segmentCuts.isEmpty {
                PlateLabel(text: "\(shot.cutList.segmentCuts.count) razor\(shot.cutList.segmentCuts.count == 1 ? "" : "s")", size: 8.5, color: PlateColor.inkFaint)
            }
            if !shot.cutList.markers.isEmpty {
                PlateLabel(text: "\(shot.cutList.markers.count) marker\(shot.cutList.markers.count == 1 ? "" : "s")", size: 8.5, color: PlateColor.inkFaint)
            }
            // The rust tag is the house mark for "the picture is not what you
            // would naively assume" — which includes a reverse that was asked
            // for and is NOT on screen.
            if isPlayingReversed {
                PlateLabel(text: "REVERSED", size: 8.5, weight: .bold, color: CanonColor.rust)
            } else if isReversed {
                PlateLabel(
                    text: reverseBakeProgress == nil ? "REVERSE UNAVAILABLE — PLAYING FORWARD" : "REVERSING",
                    size: 8.5,
                    weight: .bold,
                    color: CanonColor.rust
                )
            }
            // THE ARTIFACT BAND FALLBACK made visible: the strip is showing
            // (and cutting) the last render's video because the current plan
            // has no rendered segments. Cuts made here pin to that render and
            // are superseded when a re-render lands.
            if let fallback = artifactFallbackSegment {
                PlateLabel(
                    text: "SHOWING RENDER\(fallback.versionNumber > 0 ? " \(FrameCreatorModal.romanNumeral(fallback.versionNumber))" : "") — PLAN NOT RENDERED",
                    size: 8.5,
                    weight: .bold,
                    color: CanonColor.rust
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help("The current frame plan has no rendered segments, so the strip shows the last render's video — razor, trim, and seek apply to it. A re-render replaces this band and retires its cuts")
            }
            // Unrendered bands leave the cut layer partially (or wholly)
            // inert; rust says so up front instead of letting the razor
            // refuse mutely and trims land on a playback that ignores them.
            if unrenderedBandCount > 0 {
                PlateLabel(
                    text: "\(unrenderedBandCount) NOT RENDERED",
                    size: 8.5,
                    weight: .bold,
                    color: CanonColor.rust
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help("\(unrenderedBandCount) of \(assembly.bands.count) segment\(assembly.bands.count == 1 ? "" : "s") ha\(unrenderedBandCount == 1 ? "s" : "ve") no rendered clip — razor, trim, and seek work on rendered material only. Render the shot to edit the hatched bands")
            }
            Spacer(minLength: 0)
            Button(microphoneControlMode.buttonLabel) {
                onToggleMicrophoneRecording()
            }
            .buttonStyle(PlateButtonStyle(isProminent: microphoneControlMode.isActive))
            .disabled(!isMicrophoneAvailable || microphoneControlMode == .finalizing)
            .help(microphoneControlMode == .recording
                ? "Stop and keep this microphone take"
                : "Record a microphone take from the current playhead after a 3-second count-in")
            Button(reverseButtonLabel) {
                onSetReversed(!isReversed)
            }
            .buttonStyle(PlateButtonStyle(isProminent: isPlayingReversed))
            .disabled(reverseBakeProgress != nil)
            .help(reverseHelp)
            Button(isRazorMode ? "Razor On" : "Razor") {
                isRazorMode.toggle()
            }
            .buttonStyle(PlateButtonStyle(isProminent: isRazorMode))
            .help(isRazorMode
                ? "Razor is armed — drag across a band to cut that range out. Click to disarm (B blades at the playhead without arming)"
                : "Arm the razor — drag across a band to cut a range out of the shot. Free, and always restorable. B blades at the playhead without arming")
            Button(markerAtPlayhead == nil ? "Mark" : "Unmark") {
                toggleMarkerAtPlayhead()
            }
            .buttonStyle(PlateButtonStyle())
            .help(markerAtPlayhead == nil
                ? "Drop a reference marker at the playhead — visual only, never changes playback, render, or export. Click a marker's cap to remove it"
                : "Remove the marker at the playhead")
            clipboardButtons
            inOutFields
        }
    }

    /// COPY · PASTE · DUPLICATE · SPEED · LOOP — the guaranteed clipboard path
    /// (plate buttons beside the razor; menu ⌘C/⌘V and ⌘D mirror them at the
    /// modal). Disabled states carry their reasons. LOOP is the odd one out:
    /// it needs no selection — it repeats the ENTIRE output ×N.
    @ViewBuilder
    private var clipboardButtons: some View {
        let hasSelection = selectedSpan != nil || selectedInsertionId != nil
        Button("Copy") {
            onCopySelection()
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!hasSelection)
        .help(hasSelection
            ? "Copy the selected picture span to the clipboard (⌘C) — what you see is what rides"
            : "Drag across the strip to select a span first — or click an arranged copy")
        Button("Paste") {
            onPasteAtPlayhead()
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(cannotPasteReason != nil)
        .help(cannotPasteReason ?? "Paste the copied span at the playhead (⌘V) — free, assembled at play time")
        Button("Duplicate") {
            onDuplicateSelection()
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(selectedSpan == nil)
        .keyboardShortcut("d", modifiers: .command)
        .help(selectedSpan == nil
            ? "Select a span to duplicate it in place"
            : "Duplicate the selection right after itself (⌘D) — the copy is born muted; the base keeps its sound")
        Button("Speed") {
            isSpeedPopoverOpen = true
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(selectedSpan == nil)
        .help(selectedSpan == nil
            ? "Select a span to change its speed in place"
            : "Speed up or slow down the selected section in place — free; the copy is born muted")
        .popover(isPresented: $isSpeedPopoverOpen, arrowEdge: .bottom) {
            ShotSpeedSectionPopover(
                selectionSeconds: selectedSpan?.seconds ?? 0,
                onCommit: { rate in
                    isSpeedPopoverOpen = false
                    onSetSectionRate(rate)
                }
            )
        }
        Button(loopButtonLabel) {
            isLoopPopoverOpen = true
        }
        .buttonStyle(PlateButtonStyle(isProminent: outputLoopCount > 1))
        .disabled(!assembly.hasPlayableClips)
        .help(outputLoopCount > 1
            ? "Looping the whole output ×\(outputLoopCount) — preview and export. Click to change or remove"
            : "Repeat the entire cut end to end — free, assembled at play time, one ⌘Z")
        .popover(isPresented: $isLoopPopoverOpen, arrowEdge: .bottom) {
            ShotOutputLoopPopover(
                baseOutputSeconds: assembly.baseOutputSeconds > 0
                    ? assembly.baseOutputSeconds
                    : assembly.outputSeconds,
                currentCount: outputLoopCount,
                onCommit: { count in
                    isLoopPopoverOpen = false
                    guard count != outputLoopCount else { return }
                    onPictureEditBegan()
                    var list = shot.cutList
                    list.outputLoopCount = count
                    onSetCutList(list)
                }
            )
        }
    }

    /// Asked for, not achieved — the popover commit funnels through
    /// `onSetCutList`, and normalization clamps before anything plays.
    private var outputLoopCount: Int {
        shot.cutList.normalized().outputLoopCount
    }

    /// Bands with no resolvable clip file — the plan has moved past the last
    /// render (frames added, a re-render in flight or failed).
    private var unrenderedBandCount: Int {
        assembly.bands.filter { !$0.isRendered }.count
    }

    /// Non-nil when the strip is the ARTIFACT BAND FALLBACK — one synthetic
    /// band over the playable version's full video.
    private var artifactFallbackSegment: ShotArtifactPlanSegment? {
        guard let band = assembly.bands.first,
              case .artifactFallback(let segment) = band.segment else { return nil }
        return segment
    }

    private var loopButtonLabel: String {
        outputLoopCount > 1 ? "Loop ×\(outputLoopCount)" : "Loop"
    }

    /// Typed material timecodes for the shot in/out — the same clamps as the
    /// brass handles, reachable even when a zoomed window has panned a handle
    /// offscreen. I/O set them at the playhead; ⌥I/⌥O clear.
    @ViewBuilder
    private var inOutFields: some View {
        if assembly.materialSeconds > 0 {
            ShotTimecodeField(
                label: "IN",
                // Draft-aware: tracks the handle live during a drag instead
                // of freezing on the committed value.
                seconds: inSeconds,
                isEnabled: true
            ) { parsed in
                onPictureEditBegan()
                onSetCutList(shotCutListSettingIn(
                    shot.cutList,
                    materialSeconds: parsed,
                    assemblyMaterialSeconds: assembly.materialSeconds
                ))
            }
            .help("Shot IN — material timecode, same clamps as the brass handle. I sets it at the playhead; ⌥I clears")
            ShotTimecodeField(
                label: "OUT",
                // Draft-aware, like IN.
                seconds: outSeconds,
                isEnabled: true
            ) { parsed in
                onPictureEditBegan()
                onSetCutList(shotCutListSettingOut(
                    shot.cutList,
                    materialSeconds: parsed,
                    assemblyMaterialSeconds: assembly.materialSeconds
                ))
            }
            .help("Shot OUT — material timecode, same clamps as the brass handle. O sets it at the playhead; ⌥O clears")
        }
    }

    private func stripSnapTargets() -> [Double] {
        shotStripSnapTargets(
            assembly: assembly,
            cutList: shot.cutList,
            playheadMaterialSeconds: assembly.materialSeconds(forOutputSeconds: playheadOutputSeconds),
            audioLandmarkMaterialSeconds: audioSnapMaterialSeconds
        )
    }

    /// One funnel for every drag report: keeps the chip state, the ghost
    /// callback, and the snapped emphasis in lockstep (nil = drag ended).
    private func reportDrag(_ seconds: Double?, isSnapped: Bool) {
        dragChipMaterialSeconds = seconds
        dragChipIsSnapped = seconds == nil ? false : isSnapped
        onDragMaterialSecondsChanged(seconds, seconds == nil ? false : isSnapped)
    }

    private var legendRow: some View {
        HStack(spacing: 12) {
            PlateLabel(text: "≈ generated handoff", size: 7.5, color: PlateColor.inkFaint)
            PlateLabel(text: "‖ hard splice", size: 7.5, color: PlateColor.inkFaint)
            PlateLabel(text: "▨ razor cut · slivers restore", size: 7.5, color: PlateColor.inkFaint)
            PlateLabel(text: "⟳ arranged copy · drag selects", size: 7.5, color: PlateColor.inkFaint)
            PlateLabel(text: "▾ marker · reference only", size: 7.5, color: PlateColor.inkFaint)
            Spacer(minLength: 0)
            PlateLabel(text: "Free: trim · skip · razor · reverse · copy · loop — One render: new bridge · prompt", size: 7.5, color: PlateColor.inkFaint)
        }
    }

    private var reverseButtonLabel: String {
        if let progress = reverseBakeProgress {
            return "Reversing… \(Int((progress * 100).rounded()))%"
        }
        if isPlayingReversed { return "Reverse On" }
        // Asked for, not achieved: name the state rather than claiming it is on.
        return isReversed ? "Reverse Off" : "Reverse"
    }

    private var reverseHelp: String {
        if reverseBakeProgress != nil {
            return "Baking a backwards copy of every clip. Playback stays forward until they are all ready"
        }
        if isPlayingReversed {
            return "Reverse is on — the strip reads in play order. Audio you placed stays where you placed it: "
                + "only the picture and its own source audio mirror. Click to play forward again"
        }
        if isReversed {
            return "Reverse was asked for but a clip could not be baked backwards, so this CUT is playing "
                + "FORWARD. Reopening the shot tries again; click to turn reverse off"
        }
        return "Play this whole CUT backwards — picture and its source audio. Narration, microphone, ambient, "
            + "and clip lanes stay forward where you placed them. Free, and always reversible"
    }

    /// The pre-cut-layer length, for the "(was ~Ns)" honesty tag: material
    /// plus everything skipped.
    private var wasSeconds: Double {
        let skippedSeconds = placeholders.reduce(0.0) { total, placeholder in
            total + (placeholder.isFootage
                ? placeholder.footageSeconds
                : Double(shot.renderStack.segmentSeconds))
        }
        return assembly.materialSeconds + skippedSeconds
    }

    private var wasSecondsDiffers: Bool {
        abs(wasSeconds - assembly.outputSeconds) >= 1
    }

    // MARK: Strip geometry

    private enum StripCell {
        case band(Int)
        case sliver(ShotSkippedSegmentPlaceholder)
        /// A consolidated run of arranged copies (⟳ ×N when uniform).
        case insertions([ShotInsertionCell])
    }

    /// Arranged-copy cell runs grouped by the band they follow (nil = before
    /// band 0), in paste order.
    private var insertionRunsByBand: [Int?: [[ShotInsertionCell]]] {
        var byBand: [Int?: [ShotInsertionCell]] = [:]
        for cell in assembly.insertionCells {
            byBand[cell.afterBandIndex, default: []].append(cell)
        }
        return byBand.mapValues { shotInsertionCellRuns($0) }
    }

    private var orderedCells: [StripCell] {
        var cells: [StripCell] = []
        let insertionRuns = insertionRunsByBand
        for run in insertionRuns[nil] ?? [] {
            cells.append(.insertions(run))
        }
        for placeholder in placeholders where placeholder.afterDisplayIndex < 0 {
            cells.append(.sliver(placeholder))
        }
        for (index, band) in assembly.bands.enumerated() {
            cells.append(.band(index))
            for run in insertionRuns[index] ?? [] {
                cells.append(.insertions(run))
            }
            for placeholder in placeholders where placeholder.afterDisplayIndex == band.displayIndex {
                cells.append(.sliver(placeholder))
            }
        }
        // Play order. A skip that trailed band N now precedes it, which IS its
        // place in play order, so slivers land correctly with no further work.
        return playsReversed ? cells.reversed() : cells
    }

    /// The strip mirrors when the cut is REQUESTED reversed, not when the bake
    /// finishes: the operator asked for a backwards edit and the instrument
    /// should read that way while the proxies encode. Playback is the thing
    /// that must wait.
    private var playsReversed: Bool { isReversed }

    /// THE WINDOW COROLLARY on the strip: bands lay out at `scale × zoom`
    /// (slivers stay fixed 22pt — chrome, not time), then the whole run
    /// translates left so the viewport's offset pans the DISPLAY span.
    /// Display-space panning is what keeps a REVERSED strip honest: its
    /// display is already mirrored, so f=0 shows what plays first on every
    /// row and f=max shows what plays last, forward or backward. Interiors
    /// between the edges differ from the lanes' output window exactly as the
    /// axis contract already allows at 1×.
    private func layout(width: CGFloat, assembly: ShotCutAssembly) -> ShotStripLayout {
        var result = ShotStripLayout()
        let cells = orderedCells
        let sliverCount = CGFloat(cells.filter { if case .sliver = $0 { return true } else { return false } }.count)
        let contentWidth = max(width - handleWidth * 2 - sliverCount * sliverWidth, 40)
        let clean = viewport.normalized()
        let zoom = max(clean.zoom, 1)
        result.scale = contentWidth * zoom / CGFloat(max(assembly.materialSeconds, 0.1))
        var x = handleWidth
        for cell in cells {
            switch cell {
            case .band(let index):
                let material = index < assembly.planClips.count ? assembly.planClips[index].materialSeconds : 0
                let bandWidth = CGFloat(material) * result.scale
                result.bandFrames[index] = (x, bandWidth)
                x += bandWidth
            case .sliver(let placeholder):
                result.sliverFrames.append((placeholder, x))
                x += sliverWidth
            case .insertions(let run):
                guard let leaderId = run.first?.insertion.insertionId else { continue }
                // Fresh runs earn output-proportional width; inert runs are a
                // fixed chip (they play nothing). Both keep a legible floor.
                // Measured with the PLACED seconds (window-clamped), never the
                // authored span — the cell must shrink with the OUT handle.
                let playing = run.filter(\.state.isFresh)
                    .reduce(0.0) { $0 + $1.placedOutputSeconds }
                let cellWidth = max(CGFloat(playing) * result.scale, 26)
                result.insertionFrames[leaderId] = (x, cellWidth)
                x += cellWidth
            }
        }
        // Pan: offsetFraction ∈ [0, 1 − 1/zoom] maps linearly onto the
        // overhang, so f=0 shows the display start and f=max the display end
        // with no blank overscroll on either side.
        let span = x - handleWidth
        let visible = contentWidth + sliverCount * sliverWidth
        let overhang = max(span - visible, 0)
        let shift: CGFloat = zoom > 1
            ? CGFloat(clean.offsetFraction) * zoom / (zoom - 1) * overhang
            : 0
        if shift > 0 {
            for (index, frame) in result.bandFrames {
                result.bandFrames[index] = (frame.x - shift, frame.width)
            }
            result.sliverFrames = result.sliverFrames.map { ($0.placeholder, $0.x - shift) }
            for (leaderId, frame) in result.insertionFrames {
                result.insertionFrames[leaderId] = (frame.x - shift, frame.width)
            }
        }
        result.contentStart = handleWidth - shift
        result.contentEnd = x - shift
        result.isReversed = playsReversed
        result.planClips = assembly.planClips
        result.materialSeconds = assembly.materialSeconds
        return result
    }

    private func materialX(_ seconds: Double, layout: ShotStripLayout) -> CGFloat {
        layout.x(forMaterialSeconds: seconds)
    }

    private func materialSeconds(atX x: CGFloat, layout: ShotStripLayout) -> Double {
        layout.materialSeconds(atX: x)
    }

    private func bandIndex(atX x: CGFloat, layout: ShotStripLayout) -> Int? {
        layout.bandIndex(atX: x)
    }

    // MARK: Strip body

    @ViewBuilder
    private func stripBody(width: CGFloat) -> some View {
        let layout = layout(width: width, assembly: assembly)
        let inX = materialX(inSeconds, layout: layout)
        let outX = materialX(outSeconds, layout: layout)

        // The filmstrip's shared per-pass inputs: one ladder rung for the
        // whole strip and one culling window (strip-body x, prefetch margin
        // on both sides) — tiles outside it are never planned or generated.
        let filmstripRung = ShotFilmstripLadder.rung(
            scale: layout.scale,
            tileWidth: stripHeight * 16 / 9
        )
        let filmstripMargin = min(width / 2, 400)
        let filmstripVisibleX = (-filmstripMargin)...(width + filmstripMargin)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(PlateColor.creamDeep.opacity(0.35))

            // Bands + slivers + arranged copies
            ForEach(Array(orderedCells.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case .band(let index):
                    if let frame = layout.bandFrames[index] {
                        bandView(
                            assembly.bands[index],
                            planClip: assembly.planClips[index],
                            frame: frame,
                            layout: layout,
                            filmstripRung: filmstripRung,
                            filmstripVisibleX: filmstripVisibleX
                        )
                    }
                case .sliver(let placeholder):
                    if let frame = layout.sliverFrames.first(where: { $0.placeholder.id == placeholder.id }) {
                        sliverView(placeholder, x: frame.x)
                    }
                case .insertions(let run):
                    if let leaderId = run.first?.insertion.insertionId,
                       let frame = layout.insertionFrames[leaderId] {
                        insertionCellView(run, frame: frame)
                    }
                }
            }

            // Span selection: the painted draft, then the committed span.
            ForEach(Array(selectionRects(layout: layout).enumerated()), id: \.offset) { _, rect in
                Rectangle()
                    .fill(CanonColor.brass.opacity(0.22))
                    .overlay(
                        HStack(spacing: 0) {
                            Rectangle().fill(CanonColor.brass).frame(width: 1.5)
                            Spacer(minLength: 0)
                            Rectangle().fill(CanonColor.brass).frame(width: 1.5)
                        }
                    )
                    .frame(width: max(rect.width, 2), height: stripHeight)
                    .offset(x: rect.x)
                    .allowsHitTesting(false)
            }

            // Anchor leader ticks: where a mid-band copy actually splices.
            ForEach(assembly.insertionCells.filter { $0.anchorMaterialSeconds != nil }) { cell in
                if let tick = cell.anchorMaterialSeconds {
                    Rectangle()
                        .fill(CanonColor.brass.opacity(0.8))
                        .frame(width: 1.5, height: stripHeight * 0.45)
                        .offset(x: materialX(tick, layout: layout), y: stripHeight * 0.55)
                        .allowsHitTesting(false)
                }
            }

            // Seam glyphs at band junctions
            ForEach(seamGlyphs(layout: layout), id: \.id) { glyph in
                seamGlyphView(glyph)
            }

            // Shot in/out dim + handles. Expressed as the two stretches
            // OUTSIDE the kept span, which is correct in both directions
            // without a branch.
            let keptLowX = min(inX, outX)
            let keptHighX = max(inX, outX)
            Rectangle()
                .fill(PlateColor.cream.opacity(0.72))
                .frame(width: max(keptLowX - layout.contentStart, 0), height: stripHeight)
                .offset(x: layout.contentStart)
                .allowsHitTesting(false)
            Rectangle()
                .fill(PlateColor.cream.opacity(0.72))
                .frame(width: max(layout.contentEnd - keptHighX, 0), height: stripHeight)
                .offset(x: keptHighX)
                .allowsHitTesting(false)

            // Reference markers — inert brass pins: never snap magnets, never
            // read by playback or export. The cap is the remove control; the
            // line ignores the pointer so seeks, selections, and razor drags
            // pass straight through it.
            ForEach(shot.cutList.markers) { marker in
                markerView(marker, layout: layout)
            }

            playheadView(layout: layout)

            if let razorDraft, layout.bandFrames[razorDraft.bandIndex] != nil {
                // Through `materialX`, so the draft cannot disagree with the
                // cut it is about to become.
                let startX = materialX(razorDraft.start, layout: layout)
                let endX = materialX(razorDraft.end, layout: layout)
                Rectangle()
                    .fill(PlateColor.ink.opacity(0.35))
                    .frame(width: max(endX - startX, 1), height: stripHeight)
                    .offset(x: min(startX, endX))
                    .allowsHitTesting(false)
            }

            // The B blade's armed first mark — brass, operator intent.
            if let pendingBladeMaterialSeconds {
                Rectangle()
                    .fill(CanonColor.brass)
                    .frame(width: 2, height: stripHeight)
                    .offset(x: materialX(pendingBladeMaterialSeconds, layout: layout) - 1)
                    .allowsHitTesting(false)
            }

            // The plate always sits OUTSIDE the material it keeps. Reversed,
            // the shot-in handle therefore draws on the right — and the handle
            // on the left is the one that trims the start of what you watch,
            // which is the expected feel. The gestures are unchanged.
            trimHandle(atX: layout.isReversed ? inX : inX - handleWidth, layout: layout, isIn: true)
            trimHandle(atX: layout.isReversed ? outX - handleWidth : outX, layout: layout, isIn: false)

            // Live timecode while a picture edit drags — the lanes' timing
            // chip grammar, so the operator never trims blind again.
            if let chipSeconds = dragChipMaterialSeconds, let text = dragChipText {
                dragTimingChip(
                    text: text,
                    atX: materialX(chipSeconds, layout: layout),
                    width: width
                )
            }
        }
        .frame(width: width, height: stripHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline))
        .contentShape(Rectangle())
        // The one space every strip drag reads its x in — handles are offset
        // subviews whose own local space is not the strip body's.
        .coordinateSpace(name: Self.bodySpaceName)
        .gesture(stripGesture(layout: layout))
    }

    static let bodySpaceName = "shotCutStripBody"

    private var dragChipText: String? {
        if isDraggingIn {
            return "IN · \(ShotAudioTiming.timecode(inSeconds))"
        }
        if isDraggingOut {
            return "OUT · \(ShotAudioTiming.timecode(outSeconds))"
        }
        if let razorDraft {
            return "▨ \(ShotAudioTiming.timecode(razorDraft.start)) – \(ShotAudioTiming.timecode(razorDraft.end))"
        }
        return nil
    }

    private func dragTimingChip(text: String, atX x: CGFloat, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(PlateColor.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.cream.opacity(0.95)))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(dragChipIsSnapped ? CanonColor.brass : PlateColor.hairline, lineWidth: 1)
            )
            .position(
                x: min(max(x + 28, handleWidth + 34), max(width - handleWidth - 34, handleWidth + 34)),
                y: 9
            )
            .allowsHitTesting(false)
    }

    // MARK: Bands

    @ViewBuilder
    private func bandView(
        _ band: ShotStripBand,
        planClip: ShotCutPlanClip,
        frame: (x: CGFloat, width: CGFloat),
        layout: ShotStripLayout,
        filmstripRung: Double,
        filmstripVisibleX: ClosedRange<CGFloat>
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            if band.isRendered {
                // THE FILMSTRIP: real frames from the band's own clip file,
                // on-demand and zoom-aware. Footage keeps its import-time
                // 5-tile strip as the loading placeholder.
                ShotFilmstripBandFill(
                    band: band,
                    planClip: planClip,
                    bandFrame: frame,
                    isReversed: layout.isReversed,
                    scale: layout.scale,
                    rung: filmstripRung,
                    visibleX: filmstripVisibleX,
                    tileHeight: stripHeight,
                    loader: filmstripLoader
                )
            } else {
                // Not rendered: hatched like the skip slivers — "no real
                // material here" — so the state reads even when the band is
                // too narrow to carry its NOT RENDERED label.
                StripedHatchFill().opacity(0.45)
            }

            // Derived stitch seams (artifact band only): where the render's
            // segments actually join inside the one video — inert hairlines,
            // honest to ±3/24s, top-anchored so markers keep the bottom.
            ForEach(Array(band.seamSeconds.enumerated()), id: \.offset) { _, seam in
                Rectangle()
                    .fill(PlateColor.ink.opacity(0.55))
                    .frame(width: 1, height: stripHeight * 0.4)
                    .offset(
                        x: layout.isReversed
                            ? frame.width - CGFloat(seam) * layout.scale
                            : CGFloat(seam) * layout.scale,
                        y: -(stripHeight * 0.6)
                    )
                    .allowsHitTesting(false)
            }

            // Razor cuts already on this band — at their TRUE offsets (the
            // band clips), never clamped to x=0: the old clamp drew an
            // out-of-band cut flush left, hiding where it really bites.
            // Overlapping/abutting cuts (one BLOCK) inset per depth so every
            // member stays visible, the label carries the block size, and
            // RESTORE clears the whole block (THE RAZOR BLOCK LAW).
            ForEach(bandCuts(band, planClip: planClip)) { cut in
                let block = shotRazorCutIdsInSameBlock(cutList: shot.cutList, cutId: cut.id)
                let depth = CGFloat(min(block.firstIndex(of: cut.id) ?? 0, 3))
                let width = CGFloat(cut.seconds) * layout.scale
                let startX = layout.isReversed
                    ? frame.width - CGFloat(cut.endSeconds - planClip.headSeconds) * layout.scale
                    : CGFloat(cut.startSeconds - planClip.headSeconds) * layout.scale
                Button {
                    selectedCutId = cut.id
                } label: {
                    ZStack {
                        Rectangle()
                            .fill(cutFill(cut))
                            .overlay(Rectangle().stroke(PlateColor.ink, lineWidth: 1))
                        if width >= 38 {
                            PlateLabel(
                                text: cutLabel(cut, planClip: planClip)
                                    + (block.count > 1 ? " ×\(block.count)" : ""),
                                size: 6.5,
                                weight: .bold,
                                color: cut.joinRepair.mode == .generatedBridge ? PlateColor.cream : PlateColor.ink
                            )
                            .lineLimit(1)
                            .padding(.horizontal, 3)
                        }
                    }
                    .frame(width: max(width, 2), height: stripHeight - depth * 6)
                }
                .buttonStyle(.plain)
                .offset(x: startX, y: -depth * 3)
                .help(block.count > 1
                    ? "Razor block ×\(block.count) — this cut \(String(format: "%.1f", cut.seconds))s; RESTORE clears the whole block"
                    : "Razor cut \(String(format: "%.1f", cut.seconds))s — click to repair or restore")
                .popover(isPresented: cutPopoverBinding(cut.id), arrowEdge: .bottom) {
                    ShotJoinRepairPopover(
                        shot: shot,
                        cut: cut,
                        effectiveDissolveFrames: effectiveDissolveFrames(cut, planClip: planClip),
                        hasFALCredential: hasFALCredential,
                        isRendering: activeShotJoinRenderId == cut.id,
                        isRenderBlocked: isVideoRenderBlocked || (!activeShotJoinRenderId.isEmpty && activeShotJoinRenderId != cut.id),
                        onSetRepair: { repair in onSetJoinRepair(cut.id, repair) },
                        onRestoreCut: {
                            selectedCutId = nil
                            onRestoreRazorCut(cut.id)
                        },
                        onRenderBridge: { provider, duration, prompt in
                            onRenderJoinBridge(cut.id, provider, duration, prompt)
                        },
                        onPrepareBoundaryFrames: {
                            await onPrepareJoinFrames(cut.id)
                        },
                        assembly: assembly,
                        onSetCutRange: { start, end in
                            if let list = shotCutListReplacingRazorRange(
                                shot.cutList,
                                cutId: cut.id,
                                materialStart: start,
                                materialEnd: end,
                                assembly: assembly,
                                now: DateFormats.now()
                            ) {
                                onPictureEditBegan()
                                onSetCutList(list)
                            }
                        }
                    )
                }
            }

            // A cut biting past this band's visible edges gets an honest
            // notch at the edge it crosses, where the old clamp used to
            // silently redraw it flush-left.
            let overflow = cutOverflow(band, planClip: planClip, frame: frame, layout: layout)
            if overflow.leading {
                Rectangle()
                    .fill(PlateColor.ink.opacity(0.85))
                    .frame(width: 3, height: stripHeight)
                    .allowsHitTesting(false)
                    .help("A razor cut continues past this band's start")
            }
            if overflow.trailing {
                Rectangle()
                    .fill(PlateColor.ink.opacity(0.85))
                    .frame(width: 3, height: stripHeight)
                    .offset(x: max(frame.width - 3, 0))
                    .allowsHitTesting(false)
                    .help("A razor cut continues past this band's end")
            }

            // Every rendered band now sits on thumbnails, so every rendered
            // band earns the ink chip the footage strip already wore.
            PlateLabel(
                text: band.isRendered ? band.label : "\(band.label) · NOT RENDERED",
                size: 7,
                weight: .semibold,
                color: band.isRendered ? PlateColor.cream : PlateColor.inkFaint
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(band.isRendered ? PlateColor.ink.opacity(0.45) : Color.clear)
            .lineLimit(1)
        }
        .frame(width: max(frame.width, 1), height: stripHeight)
        .clipped()
        .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 0.5))
        .offset(x: frame.x)
    }

    private func bandCuts(_ band: ShotStripBand, planClip: ShotCutPlanClip) -> [ShotSegmentCutRange] {
        shot.cutList.segmentCuts.filter { $0.applies(toSegmentKey: band.segmentKey, clipPath: band.clipPath) }
    }

    // MARK: Arranged copies (picture insertions)

    private func insertionPopoverBinding(_ leaderId: String) -> Binding<Bool> {
        Binding(
            get: { selectedInsertionId == leaderId },
            set: { open in
                if !open, selectedInsertionId == leaderId { selectedInsertionId = nil }
            }
        )
    }

    /// The committed span and the live paint, as display rects.
    private func selectionRects(layout: ShotStripLayout) -> [(x: CGFloat, width: CGFloat)] {
        var rects: [(CGFloat, CGFloat)] = []
        var spans: [(Double, Double)] = []
        if let selectedSpan {
            spans.append((selectedSpan.lowSeconds, selectedSpan.highSeconds))
        }
        if let selectionDraft {
            spans.append((min(selectionDraft.start, selectionDraft.end), max(selectionDraft.start, selectionDraft.end)))
        }
        for span in spans {
            let lowX = materialX(span.0, layout: layout)
            let highX = materialX(span.1, layout: layout)
            rects.append((min(lowX, highX), abs(highX - lowX)))
        }
        return rects
    }

    @ViewBuilder
    private func insertionCellView(
        _ run: [ShotInsertionCell],
        frame: (x: CGFloat, width: CGFloat)
    ) -> some View {
        let leader = run[0]
        let leaderId = leader.insertion.insertionId
        let isSelected = selectedInsertionId == leaderId
        Button {
            selectedSpan = nil
            selectedInsertionId = leaderId
        } label: {
            ZStack {
                Rectangle()
                    .fill(leader.state.isFresh
                        ? CanonColor.brass.opacity(isSelected ? 0.5 : 0.3)
                        : PlateColor.creamDeep.opacity(0.3))
                    .overlay(Rectangle().stroke(
                        leader.state.isFresh ? CanonColor.brass : CanonColor.rust,
                        lineWidth: isSelected ? 1.5 : 1
                    ))
                VStack(spacing: 1) {
                    PlateLabel(
                        text: run.count > 1 ? "⟳×\(run.count)" : "⟳",
                        size: 8,
                        weight: .bold,
                        color: leader.state.isFresh ? PlateColor.ink : CanonColor.rust
                    )
                    if frame.width >= 34 {
                        PlateLabel(
                            text: insertionChip(leader),
                            size: 6,
                            weight: .semibold,
                            color: leader.state.isFresh ? PlateColor.ink : CanonColor.rust
                        )
                        .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(width: max(frame.width, 2), height: stripHeight)
        }
        .buttonStyle(.plain)
        .offset(x: frame.x)
        .help(insertionHelp(run))
        .popover(isPresented: insertionPopoverBinding(leaderId), arrowEdge: .bottom) {
            ShotInsertionPopover(
                run: run,
                onSetRate: onInsertionSetRate,
                onSetMuted: onInsertionSetMuted,
                onDelete: { ids in
                    selectedInsertionId = nil
                    onInsertionDelete(ids)
                },
                onRecopy: onInsertionRecopy,
                onAddLoopCopy: onInsertionAddLoopCopy
            )
        }
    }

    private func insertionChip(_ cell: ShotInsertionCell) -> String {
        guard cell.state.isFresh else { return cell.state.badge }
        var parts: [String] = []
        if cell.insertion.playbackRate != 1 {
            parts.append(shotInsertionRateLabel(cell.insertion.playbackRate))
        }
        if cell.insertion.muteSourceAudio {
            parts.append("♪̶")
        }
        if parts.isEmpty {
            parts.append("\(String(format: "%.1f", cell.insertion.sourceSeconds))s")
        }
        return parts.joined(separator: " ")
    }

    private func insertionHelp(_ run: [ShotInsertionCell]) -> String {
        guard let leader = run.first else { return "" }
        let base = run.count > 1
            ? "Loop ×\(run.count) — \(String(format: "%.1f", leader.insertion.sourceSeconds))s per copy at \(shotInsertionRateLabel(leader.insertion.playbackRate))"
            : "Arranged copy — \(String(format: "%.1f", leader.insertion.sourceSeconds))s at \(shotInsertionRateLabel(leader.insertion.playbackRate))"
        switch leader.state {
        case .fresh:
            return base + ". Click for speed, sound, loop, delete — all free"
        case .olderTake:
            return base + ". OLDER TAKE — the segment re-rendered; click to Re-copy onto the current take"
        case .sourceMissing:
            return base + ". SOURCE MISSING — the copied file is gone from disk"
        case .unsupportedTransform:
            return base + ". UNSUPPORTED — asks for a transform this build doesn't run"
        case .trimmedOut:
            return base + ". TRIMMED OUT — the shot IN/OUT trim excludes it; move the handles to bring it back"
        }
    }

    /// Whether any razor on this band bites past its visible edges.
    private func cutOverflow(
        _ band: ShotStripBand,
        planClip: ShotCutPlanClip,
        frame: (x: CGFloat, width: CGFloat),
        layout: ShotStripLayout
    ) -> (leading: Bool, trailing: Bool) {
        var leading = false
        var trailing = false
        for cut in bandCuts(band, planClip: planClip) {
            let width = CGFloat(cut.seconds) * layout.scale
            let startX = layout.isReversed
                ? frame.width - CGFloat(cut.endSeconds - planClip.headSeconds) * layout.scale
                : CGFloat(cut.startSeconds - planClip.headSeconds) * layout.scale
            if startX < -0.5 { leading = true }
            if startX + width > frame.width + 0.5 { trailing = true }
        }
        return (leading, trailing)
    }

    private func cutPopoverBinding(_ cutId: String) -> Binding<Bool> {
        Binding(
            get: { selectedCutId == cutId },
            set: { isPresented in
                if isPresented {
                    selectedCutId = cutId
                } else if selectedCutId == cutId {
                    selectedCutId = nil
                }
            }
        )
    }

    private func cutFill(_ cut: ShotSegmentCutRange) -> Color {
        switch cut.joinRepair.mode {
        case .hardCut: return PlateColor.ink.opacity(0.22)
        case .dissolve: return CanonColor.brass.opacity(0.48)
        case .generatedBridge: return PlateColor.ink.opacity(0.78)
        }
    }

    private func cutLabel(_ cut: ShotSegmentCutRange, planClip: ShotCutPlanClip) -> String {
        switch cut.joinRepair.mode {
        case .hardCut: return "CUT"
        case .dissolve: return "DISSOLVE · \(effectiveDissolveFrames(cut, planClip: planClip))F"
        case .generatedBridge:
            let seconds = shot.joinBridgeVersion(cut.joinRepair.activeBridgeVersionId)?.durationSeconds ?? 0
            return seconds > 0 ? "AI BRIDGE · \(String(format: "%.1f", seconds))S" : "AI BRIDGE"
        }
    }

    private func effectiveDissolveFrames(
        _ cut: ShotSegmentCutRange,
        planClip: ShotCutPlanClip
    ) -> Int {
        let cuts = shot.cutList.segmentCuts.filter {
            $0.applies(toSegmentKey: planClip.segmentKey, clipPath: planClip.clipPath)
        }
        var transitionFramesIntoPreviousKeep = 0
        for incomingIndex in planClip.keepRanges.indices where incomingIndex > 0 {
            let outgoing = planClip.keepRanges[incomingIndex - 1]
            let incoming = planClip.keepRanges[incomingIndex]
            guard let separatingCut = cuts.first(where: {
                abs($0.startSeconds - outgoing.end) <= 1.0 / 240.0
                    && abs($0.endSeconds - incoming.start) <= 1.0 / 240.0
            }) else {
                transitionFramesIntoPreviousKeep = 0
                continue
            }
            var frames = 0
            if separatingCut.joinRepair.mode == .dissolve {
                let outgoingFrameCapacity = Int(floor(outgoing.seconds * 24 + 0.000_1))
                let remainingAfterIncomingTransition = max(
                    outgoingFrameCapacity - transitionFramesIntoPreviousKeep / 2,
                    0
                )
                frames = min(
                    separatingCut.joinRepair.gapCappedDissolveFrames(gapSeconds: separatingCut.seconds),
                    Int(floor(outgoing.seconds * 24 * 2 + 0.000_1)),
                    Int(floor(incoming.seconds * 24 * 2 + 0.000_1)),
                    remainingAfterIncomingTransition * 2
                )
                frames -= frames % 2
            }
            if separatingCut.id == cut.id { return frames }
            transitionFramesIntoPreviousKeep = frames
        }
        return 0
    }

    // MARK: Slivers (skipped, restorable)

    private func sliverView(_ placeholder: ShotSkippedSegmentPlaceholder, x: CGFloat) -> some View {
        Button {
            restore(placeholder)
        } label: {
            ZStack {
                StripedHatchFill()
                VStack(spacing: 2) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                    PlateLabel(text: "SKIP", size: 6, weight: .semibold, color: PlateColor.inkFaint)
                }
            }
            .frame(width: sliverWidth, height: stripHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x)
        .help("\(placeholder.label) — skipped, seams healed to hard cuts. Click to restore")
    }

    private func restore(_ placeholder: ShotSkippedSegmentPlaceholder) {
        switch placeholder.restore {
        case .entry(let entryId):
            onSetEntrySkipped(entryId, false)
        case .seam(let rightEntryId):
            // NOT the explicit toggle: a restore returns what skip hid and
            // must never delete a combined-cut boundary.
            onRestoreSkippedSeam(rightEntryId)
        }
    }

    // MARK: Seam glyphs

    private struct SeamGlyph: Identifiable {
        var id: String
        var x: CGFloat
        var style: ShotSeamStyle
        var toggleEntryId: String?
    }

    private func seamGlyphs(layout: ShotStripLayout) -> [SeamGlyph] {
        var glyphs: [SeamGlyph] = []
        let cells = orderedCells
        for (cellIndex, cell) in cells.enumerated() {
            guard cellIndex + 1 < cells.count,
                  case .band(let leftIndex) = cell,
                  case .band(let rightIndex) = cells[cellIndex + 1],
                  let rightFrame = layout.bandFrames[rightIndex] else {
                continue
            }
            // Position follows the display, but the SEMANTICS stay material:
            // which band hands off to which is a fact about the edit, not about
            // the direction it is being watched in.
            let left = assembly.bands[layout.isReversed ? rightIndex : leftIndex]
            let right = assembly.bands[layout.isReversed ? leftIndex : rightIndex]
            guard let glyph = seamGlyph(between: left, and: right, atX: rightFrame.x) else { continue }
            glyphs.append(glyph)
        }
        return glyphs
    }

    /// The seam at a band junction, when it can be derived unambiguously:
    /// a generated pair touching adjacent footage IS that seam (≈, toggle =
    /// cut); adjacent footage↔footage or footage↔non-touching-generated is a
    /// hard splice (‖, toggle = bridge). Generated↔generated sharing a
    /// keyframe is continuous — no seam, no glyph.
    private func seamGlyph(between left: ShotStripBand, and right: ShotStripBand, atX x: CGFloat) -> SeamGlyph? {
        let id = "seam_\(left.id)_\(right.id)"
        func pairItem(_ band: ShotStripBand) -> ShotSegmentPromptPlanItem? {
            if case .generated(let item) = band.segment { return item }
            return nil
        }
        func footageClip(_ band: ShotStripBand) -> ShotFootageClip? {
            if case .footage(let segment) = band.segment { return segment.clip }
            return nil
        }

        // Extension segments (lead-in ">x", trailing "x>") join their anchor
        // by construction and the plan never bridges across one — no seam
        // touching them is toggleable. (This also retires the dishonest
        // toggle glyph that used to render after a trailing extension.)
        if let item = pairItem(left), item.pair.start == nil || item.pair.end == nil {
            return nil
        }
        if let item = pairItem(right), item.pair.start == nil || item.pair.end == nil {
            return nil
        }

        // Bridge pair beside the footage it touches: the pair IS the seam.
        if let item = pairItem(right), item.touchesFootage, footageClip(left) != nil,
           case .seam(let rightEntryId)? = item.skipTarget {
            return SeamGlyph(id: id, x: x, style: .bridge, toggleEntryId: rightEntryId)
        }
        if let item = pairItem(left), item.touchesFootage, let clip = footageClip(right) {
            return SeamGlyph(id: id, x: x, style: .bridge, toggleEntryId: clip.entryId)
        }
        // Footage against footage: clip↔clip seam (cut by default).
        if footageClip(left) != nil, let rightClip = footageClip(right) {
            return SeamGlyph(id: id, x: x, style: .cut, toggleEntryId: rightClip.entryId)
        }
        // Footage against a generated pair that does NOT touch it: hard cut.
        // Bridging means bridging footage-out into the next surviving entry
        // (the one owning the pair's start frame).
        if footageClip(left) != nil, let item = pairItem(right), !item.touchesFootage {
            return SeamGlyph(id: id, x: x, style: .cut, toggleEntryId: nextSurvivingEntryId(afterFootage: left))
        }
        if let clip = footageClip(right), let item = pairItem(left), !item.touchesFootage {
            return SeamGlyph(id: id, x: x, style: .cut, toggleEntryId: clip.entryId)
        }
        // Generated against generated: shared keyframe = continuous.
        if let leftItem = pairItem(left), let rightItem = pairItem(right),
           let leftEnd = leftItem.pair.end?.imageId, leftEnd == rightItem.pair.start?.imageId {
            return nil
        }
        return nil
    }

    /// The entry after this footage band's entry, skipping skipped entries —
    /// the right entry of the footage's OUT seam.
    private func nextSurvivingEntryId(afterFootage band: ShotStripBand) -> String? {
        guard case .footage(let segment) = band.segment,
              let index = shot.entries.firstIndex(where: { $0.entryId == segment.clip.entryId }) else {
            return nil
        }
        for candidate in shot.entries.dropFirst(index + 1) where !candidate.isSkipped {
            return candidate.entryId
        }
        return nil
    }

    private func seamGlyphView(_ glyph: SeamGlyph) -> some View {
        Button {
            if let entryId = glyph.toggleEntryId {
                onSetSeamStyle(entryId, glyph.style.toggled)
            }
        } label: {
            Text(glyph.style == .bridge ? "≈" : "‖")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(glyph.style == .bridge ? PlateColor.cream : PlateColor.ink)
                .frame(width: 15, height: 15)
                .background(Circle().fill(glyph.style == .bridge ? PlateColor.ink : PlateColor.cream))
                .overlay(Circle().stroke(PlateColor.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(glyph.toggleEntryId == nil)
        .offset(x: glyph.x - 7.5, y: (stripHeight - 15) / 2)
        .help(glyph.style == .bridge
            ? "Generated handoff — click to hard-cut this seam (free)"
            : "Hard splice — click to bridge this seam (one segment render)")
    }

    // MARK: Playhead

    /// The same instant as the lanes' playhead, at a DIFFERENT x — this block
    /// is material space. The brass cap here and the brass cap atop the ruler
    /// below are deliberately not joined by a line: a vertical one would claim
    /// the two x's are equal, and a kinked one would be worse. Two facing
    /// marks across the declared seam say "re-projected", which is the truth.
    @ViewBuilder
    private func playheadView(layout: ShotStripLayout) -> some View {
        let x = materialX(assembly.materialSeconds(forOutputSeconds: playheadOutputSeconds), layout: layout)
        ZStack(alignment: .top) {
            // Backing + bright line (the VideoScrubComponents precedent): a
            // bare dark hairline vanished over photographic filmstrip tiles.
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 4.5, height: stripHeight)
            Rectangle()
                .fill(CanonColor.bone)
                .frame(width: 2, height: stripHeight)
            ShotTimelinePlayheadCap()
                .offset(y: -1)
            // Re-projection tick: where this instant leaves material space.
            RoundedRectangle(cornerRadius: 0.5)
                .fill(CanonColor.brass)
                .frame(width: 2, height: 5)
                .offset(y: stripHeight - 5)
        }
        .frame(width: 10, height: stripHeight, alignment: .top)
        .offset(x: x - 5)
        .allowsHitTesting(false)
    }

    // MARK: Reference markers

    private var playheadMaterialSeconds: Double {
        assembly.materialSeconds(forOutputSeconds: playheadOutputSeconds)
    }

    private var markerAtPlayhead: ShotStripMarker? {
        shotMarkerAtPlayhead(
            cutList: shot.cutList,
            playheadMaterialSeconds: playheadMaterialSeconds
        )
    }

    /// The Mark button's toggle: a marker under the playhead lifts, otherwise
    /// one drops there. Deliberately no `onPictureEditBegan` — markers change
    /// nothing that plays, so dropping one must not pause playback.
    private func toggleMarkerAtPlayhead() {
        var list = shot.cutList
        if let hit = markerAtPlayhead {
            list.markers.removeAll { $0.id == hit.id }
        } else {
            list.markers.append(ShotStripMarker(
                materialSeconds: playheadMaterialSeconds,
                updatedAt: DateFormats.now()
            ))
        }
        onSetCutList(list)
    }

    private func removeMarker(_ markerId: String) {
        var list = shot.cutList
        list.markers.removeAll { $0.id == markerId }
        onSetCutList(list)
    }

    @ViewBuilder
    private func markerView(_ marker: ShotStripMarker, layout: ShotStripLayout) -> some View {
        let x = materialX(marker.materialSeconds, layout: layout)
        Rectangle()
            .fill(CanonColor.brass.opacity(0.9))
            .frame(width: 2, height: stripHeight)
            .offset(x: x - 1)
            .allowsHitTesting(false)
        Button {
            removeMarker(marker.id)
        } label: {
            ShotStripMarkerCapShape()
                .fill(CanonColor.brass)
                .overlay(ShotStripMarkerCapShape().stroke(PlateColor.ink.opacity(0.4), lineWidth: 0.5))
                .frame(width: 9, height: 7)
        }
        .buttonStyle(.plain)
        .offset(x: x - 4.5)
        .help("Marker — reference only; never plays, renders, or exports. Click to remove")
    }

    // MARK: Gestures

    private func trimHandle(atX x: CGFloat, layout: ShotStripLayout, isIn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(CanonColor.brass)
            .frame(width: handleWidth, height: stripHeight)
            .overlay(
                Rectangle()
                    .fill(PlateColor.ink.opacity(0.5))
                    .frame(width: 1.5, height: stripHeight * 0.4)
            )
            .offset(x: x)
            .gesture(
                // Named space (the VideoScrubComponents precedent): the
                // handle is a 13pt offset view, so its own local space is
                // ambiguous — the strip body's space is the one
                // `materialSeconds(atX:)` expects.
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.bodySpaceName))
                    .onChanged { value in
                        if !isDraggingIn, !isDraggingOut { onPictureEditBegan() }
                        let snapped = ShotAudioTiming.snappedSeconds(
                            candidate: materialSeconds(atX: value.location.x, layout: layout),
                            targets: stripSnapTargets(),
                            timelineWidth: Double(layout.scale) * assembly.materialSeconds,
                            timelineDuration: assembly.materialSeconds,
                            bypass: NSEvent.modifierFlags.contains(.option)
                        )
                        let seconds = min(max(snapped.seconds, 0), assembly.materialSeconds)
                        let applied: Double
                        if isIn {
                            isDraggingIn = true
                            applied = min(seconds, outSeconds - ShotCutList.minimumRangeSeconds)
                            draftInSeconds = applied
                        } else {
                            isDraggingOut = true
                            applied = max(seconds, inSeconds + ShotCutList.minimumRangeSeconds)
                            draftOutSeconds = applied
                        }
                        // Report the APPLIED draft (post-clamp), so chip and
                        // ghost show where the trim will actually land.
                        reportDrag(applied, isSnapped: snapped.snapped)
                    }
                    .onEnded { _ in
                        var list = shot.cutList
                        if isIn {
                            list.shotInSeconds = draftInSeconds
                        } else {
                            if let draft = draftOutSeconds, draft < assembly.materialSeconds - ShotCutList.minimumRangeSeconds {
                                list.shotOutSeconds = draft
                            } else {
                                list.shotOutSeconds = nil
                            }
                        }
                        isDraggingIn = false
                        isDraggingOut = false
                        draftInSeconds = nil
                        draftOutSeconds = nil
                        reportDrag(nil, isSnapped: false)
                        onSetCutList(list)
                    }
            )
            .help(isIn
                ? "Shot in point — drag to trim the head. Free, never a render"
                : "Shot out point — drag to trim the tail. Free, never a render")
    }

    private func stripGesture(layout: ShotStripLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isRazorMode {
                    guard let bandIndex = bandIndex(atX: value.startLocation.x, layout: layout),
                          assembly.planClips[bandIndex].isPlayable else {
                        // Refusing mutely reads as "the razor broke" — say why.
                        if !hasSentRazorRefusalNotice,
                           let refused = bandIndex(atX: value.startLocation.x, layout: layout) {
                            hasSentRazorRefusalNotice = true
                            onNotice("Segment \(assembly.bands[refused].displayIndex + 1) has no rendered clip — the razor cuts rendered material only. Render the shot first")
                        }
                        return
                    }
                    if razorDraft == nil { onPictureEditBegan() }
                    let clip = assembly.planClips[bandIndex]
                    let lower = clip.materialStartSeconds
                    let upper = clip.materialStartSeconds + clip.materialSeconds
                    let start = min(max(materialSeconds(atX: value.startLocation.x, layout: layout), lower), upper)
                    // The moving edge snaps to material magnets (band edges,
                    // razor edges, the playhead's projection); Option bypasses,
                    // matching the audio lanes' convention.
                    let snapped = ShotAudioTiming.snappedSeconds(
                        candidate: materialSeconds(atX: value.location.x, layout: layout),
                        targets: stripSnapTargets(),
                        timelineWidth: Double(layout.scale) * assembly.materialSeconds,
                        timelineDuration: assembly.materialSeconds,
                        bypass: NSEvent.modifierFlags.contains(.option)
                    )
                    let current = min(max(snapped.seconds, lower), upper)
                    razorDraft = (bandIndex, min(start, current), max(start, current))
                    // The razor's moving edge feeds the same chip + ghost as
                    // the trim handles — a cut painted against the audio.
                    reportDrag(current, isSnapped: snapped.snapped)
                } else {
                    // PLAIN DRAG PAINTS THE SELECTION (locked);
                    // a sub-threshold press stays a click and seeks on
                    // release. Continuous drag-scrub moved to the ruler and
                    // the J/K/L transport — the strip's drag now selects.
                    let travelled = abs(value.translation.width)
                    guard travelled >= 4 || selectionDraft != nil else { return }
                    let start = min(
                        max(materialSeconds(atX: value.startLocation.x, layout: layout), 0),
                        assembly.materialSeconds
                    )
                    let snapped = ShotAudioTiming.snappedSeconds(
                        candidate: materialSeconds(atX: value.location.x, layout: layout),
                        targets: stripSnapTargets(),
                        timelineWidth: Double(layout.scale) * assembly.materialSeconds,
                        timelineDuration: assembly.materialSeconds,
                        bypass: NSEvent.modifierFlags.contains(.option)
                    )
                    let current = min(max(snapped.seconds, 0), assembly.materialSeconds)
                    selectionDraft = (start, current)
                }
            }
            .onEnded { value in
                reportDrag(nil, isSnapped: false)
                if !isRazorMode {
                    if let draft = selectionDraft {
                        selectionDraft = nil
                        selectedInsertionId = nil
                        let low = min(draft.start, draft.end)
                        let high = max(draft.start, draft.end)
                        if high - low >= ShotCutList.minimumRangeSeconds {
                            selectedSpan = ShotStripSpanSelection(
                                startMaterialSeconds: low,
                                endMaterialSeconds: high
                            )
                        } else {
                            selectedSpan = nil
                        }
                    } else if assembly.hasPlayableClips {
                        // A click: one seek, latched like a momentary scrub.
                        onScrubBegan()
                        let seconds = materialSeconds(atX: value.location.x, layout: layout)
                        onSeek(assembly.outputSeconds(forMaterialSeconds: seconds))
                        onScrubEnded()
                    } else {
                        // A dead assembly maps every click to ~0s — refusing
                        // out loud beats a seek that "does nothing".
                        onNotice("Strip seek is offline — no rendered segments match the current plan. Render the shot first")
                    }
                }
                hasSentRazorRefusalNotice = false
                guard isRazorMode, let draft = razorDraft else {
                    razorDraft = nil
                    return
                }
                razorDraft = nil
                guard draft.end - draft.start >= ShotCutList.minimumRangeSeconds else { return }
                let clip = assembly.planClips[draft.bandIndex]
                let band = assembly.bands[draft.bandIndex]
                var list = shot.cutList
                list.segmentCuts.append(ShotSegmentCutRange(
                    segmentKey: band.segmentKey,
                    // Generated cuts pin to the exact rendered take; footage
                    // cuts persist across renders.
                    clipPath: band.isFootage ? "" : band.clipPath,
                    startSeconds: clip.headSeconds + (draft.start - clip.materialStartSeconds),
                    endSeconds: clip.headSeconds + (draft.end - clip.materialStartSeconds),
                    updatedAt: DateFormats.now()
                ))
                onSetCutList(list)
            }
    }
}

/// The reference marker's cap — a small brass pennant pointing down its
/// line. It is the marker's only hit target.
private struct ShotStripMarkerCapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// One band's thumbnail fill: real frames from the band's clip, drawn into
/// the tile slots the pure plan decides, over the cream base — with footage's
/// import-time 5-tile strip as the loading placeholder. Inert by law
/// (`allowsHitTesting(false)`): every razor/seek/selection gesture passes
/// straight through to the strip.
private struct ShotFilmstripBandFill: View {
    let band: ShotStripBand
    let planClip: ShotCutPlanClip
    let bandFrame: (x: CGFloat, width: CGFloat)
    let isReversed: Bool
    let scale: CGFloat
    let rung: Double
    let visibleX: ClosedRange<CGFloat>
    let tileHeight: CGFloat
    @ObservedObject var loader: ShotFilmstripLoader

    private var tiles: [ShotFilmstripTile] {
        shotFilmstripTilePlan(
            planClip: planClip,
            bandFrame: bandFrame,
            isReversed: isReversed,
            scale: scale,
            rung: rung,
            visibleX: visibleX
        )
    }

    /// Retina-doubled generation height, bucketed by the loader.
    private var heightPixels: Int { Int(tileHeight * 2) }

    /// `.task(id:)`'s debounce key: re-request only when the plan's shape
    /// actually moves (rung swap, band resize, culling window shift) — the
    /// request itself is a cheap diff against the cache.
    private var tilePlanKey: String {
        "\(band.clipPath)|\(rung)|\(Int(bandFrame.x))|\(Int(bandFrame.width))|\(Int(visibleX.lowerBound))|\(Int(visibleX.upperBound))"
    }

    var body: some View {
        // Reading `revision` ties this body to tile arrival; the store read
        // in the Canvas is synchronous and never enqueues work.
        let _ = loader.revision
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(PlateColor.creamDeep.opacity(0.85))
            )
            if let path = band.fillImagePath,
               let placeholder = StripThumbnailCache.shared.image(path: path, maxPixel: 800) {
                context.draw(Image(nsImage: placeholder), in: CGRect(origin: .zero, size: size))
            }
            for tile in tiles {
                guard let image = loader.tile(
                    clipPath: tile.clipPath,
                    rung: rung,
                    rungIndex: tile.rungIndex,
                    heightPixels: heightPixels
                ) else { continue }
                let rect = CGRect(x: tile.x, y: 0, width: tile.width, height: size.height)
                let imageSize = image.size
                guard imageSize.width > 0, imageSize.height > 0 else { continue }
                // Aspect-fill crop into the slot: a copied context scopes the
                // clip to this tile.
                var tileContext = context
                tileContext.clip(to: Path(rect))
                let fillScale = max(rect.width / imageSize.width, rect.height / imageSize.height)
                let drawSize = CGSize(
                    width: imageSize.width * fillScale,
                    height: imageSize.height * fillScale
                )
                tileContext.draw(
                    Image(nsImage: image),
                    in: CGRect(
                        x: rect.midX - drawSize.width / 2,
                        y: rect.midY - drawSize.height / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    )
                )
            }
        }
        .task(id: tilePlanKey) {
            loader.requestTiles(tiles, rung: rung, heightPixels: heightPixels)
        }
        .allowsHitTesting(false)
    }
}

/// The skip sliver's hatch: diagonal plate-tone stripes.
private struct StripedHatchFill: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PlateColor.creamDeep.opacity(0.5)))
            var x: CGFloat = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(PlateColor.inkFaint.opacity(0.5)), lineWidth: 1.5)
                x += 5
            }
        }
    }
}
