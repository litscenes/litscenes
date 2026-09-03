import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import LitScenes

// The reverse law: a CUT that plays backwards. Material space is direction-free
// (the strip still shows everything you have, in authored order), so direction
// rides `ShotCutPlaybackItem.playsReversed` and never on inverted span bounds.

// MARK: - Fixtures

/// Two spans, 4s then 6s, abutting in both output and material space.
private func forwardItems() -> [ShotCutPlaybackItem] {
    [
        ShotCutPlaybackItem(
            itemId: "a",
            url: URL(fileURLWithPath: "/tmp/a.mp4"),
            keepRange: ShotKeepRange(start: 0, end: 4),
            outputStartSeconds: 0,
            durationSeconds: 4,
            materialStartSeconds: 0,
            materialEndSeconds: 4
        ),
        ShotCutPlaybackItem(
            itemId: "b",
            url: URL(fileURLWithPath: "/tmp/b.mp4"),
            keepRange: ShotKeepRange(start: 0, end: 6),
            outputStartSeconds: 4,
            durationSeconds: 6,
            materialStartSeconds: 4,
            materialEndSeconds: 10
        )
    ]
}

/// What the transform will produce: order reversed, spans left as ordered
/// intervals in authored material space, direction on the flag.
private func reversedItems() -> [ShotCutPlaybackItem] {
    var b = forwardItems()[1]
    var a = forwardItems()[0]
    b.outputStartSeconds = 0
    b.playsReversed = true
    a.outputStartSeconds = 6
    a.playsReversed = true
    return [b, a]
}

private func assembly(_ items: [ShotCutPlaybackItem]) -> ShotCutAssembly {
    ShotCutAssembly(
        playbackItems: items,
        outputSeconds: items.reduce(0) { $0 + $1.durationSeconds },
        materialSeconds: 10
    )
}

// MARK: - Direction-aware mapping

@Test func forwardMappingIsUnchanged() {
    let forward = assembly(forwardItems())
    #expect(abs(forward.materialSeconds(forOutputSeconds: 0) - 0) < 1e-9)
    #expect(abs(forward.materialSeconds(forOutputSeconds: 10) - 10) < 1e-9)
    #expect(abs(forward.materialSeconds(forOutputSeconds: 4) - 4) < 1e-9)
    #expect(abs(forward.outputSeconds(forMaterialSeconds: 0) - 0) < 1e-9)
    #expect(abs(forward.outputSeconds(forMaterialSeconds: 10) - 10) < 1e-9)
}

/// The playhead sweeps forward through output time while walking BACKWARDS
/// through the material the strip draws.
@Test func reversedOutputTimeWalksMaterialBackwards() {
    let reversed = assembly(reversedItems())
    #expect(abs(reversed.materialSeconds(forOutputSeconds: 0) - 10) < 1e-9)
    #expect(abs(reversed.materialSeconds(forOutputSeconds: 10) - 0) < 1e-9)
    // The seam between the two reversed spans: material 4, reached at output 6.
    #expect(abs(reversed.materialSeconds(forOutputSeconds: 6) - 4) < 1e-9)
    // Monotonically descending through material as output advances.
    var previous = Double.infinity
    for step in stride(from: 0.0, through: 10.0, by: 0.25) {
        let material = reversed.materialSeconds(forOutputSeconds: step)
        #expect(material <= previous + 1e-9)
        previous = material
    }
}

/// The regression pin for the latent bug: `outputSeconds(forMaterialSeconds:)`
/// walked `playbackItems` in OUTPUT order, which is material-descending once a
/// cut is reversed. It abandoned the scan at the first span and pinned every
/// scrub to one band.
@Test func reversedMaterialToOutputRoundTrips() {
    let reversed = assembly(reversedItems())
    for step in stride(from: 0.0, through: 10.0, by: 0.1) {
        let material = reversed.materialSeconds(forOutputSeconds: step)
        let back = reversed.outputSeconds(forMaterialSeconds: material)
        #expect(abs(back - step) < 1e-6)
    }
}

@Test func reversedMaterialScrubResolvesToTheRightSpan() {
    let reversed = assembly(reversedItems())
    // Material 0 is the FIRST thing authored and the LAST thing played.
    #expect(abs(reversed.outputSeconds(forMaterialSeconds: 0) - 10) < 1e-9)
    // Material 10 is the last thing authored and the first thing played.
    #expect(abs(reversed.outputSeconds(forMaterialSeconds: 10) - 0) < 1e-9)
    // Mid-band, inside the span that plays second.
    #expect(abs(reversed.outputSeconds(forMaterialSeconds: 2) - 8) < 1e-9)
}

/// A razor leaves a stretch of material that plays at no output time. Scrubbing
/// into it must snap to the instant that material is adjacent to — for a
/// reversed span, the instant it FINISHES, not the instant it starts.
@Test func reversedGapSnapsToTheEdgeThatPlaysThatMaterial() {
    var late = forwardItems()[1]
    late.outputStartSeconds = 0
    late.playsReversed = true
    // Material [0, 4) is razored away entirely; only [4, 10] survives.
    let reversed = ShotCutAssembly(
        playbackItems: [late],
        outputSeconds: 6,
        materialSeconds: 10
    )
    // Material 2 sits in the removed stretch, below the surviving span.
    #expect(abs(reversed.outputSeconds(forMaterialSeconds: 2) - 6) < 1e-9)

    var forwardLate = forwardItems()[1]
    forwardLate.outputStartSeconds = 0
    let forward = ShotCutAssembly(
        playbackItems: [forwardLate],
        outputSeconds: 6,
        materialSeconds: 10
    )
    #expect(abs(forward.outputSeconds(forMaterialSeconds: 2) - 0) < 1e-9)
}

/// I2: direction never inverts span bounds, so the band resolver — which is
/// handed `materialStartSeconds` — needs no direction branch and cannot
/// misattribute a reversed item to the next band.
@Test func reversedSpansStayOrderedIntervals() {
    for item in reversedItems() {
        #expect(item.materialStartSeconds <= item.materialEndSeconds)
    }
}

/// I5: a frame-true reverse of the same spans is the same length. Every audio
/// overlay clamps against `composition.duration`, so this is what lets
/// narration, mic takes, and ambient beds stay exactly where they were placed.
@Test func reversingPreservesOutputDuration() {
    #expect(abs(assembly(forwardItems()).outputSeconds - assembly(reversedItems()).outputSeconds) < 1.0 / 240.0)
}

// MARK: - The pure transform

/// Proxies for the two-span fixture, both 4s/6s files reversed whole.
private func fixtureProxies(hasAudio: Bool = true) -> [String: ShotReverseProxyArtifact] {
    [
        "/tmp/a.mp4": ShotReverseProxyArtifact(
            proxyId: "pa",
            sourcePath: "/tmp/a.mp4",
            sourceDurationSeconds: 4,
            proxyDurationSeconds: 4,
            proxyPath: "/tmp/rev_a.mp4",
            hasReversedAudio: hasAudio,
            status: "ready"
        ),
        "/tmp/b.mp4": ShotReverseProxyArtifact(
            proxyId: "pb",
            sourcePath: "/tmp/b.mp4",
            sourceDurationSeconds: 6,
            proxyDurationSeconds: 6,
            proxyPath: "/tmp/rev_b.mp4",
            hasReversedAudio: hasAudio,
            status: "ready"
        )
    ]
}

@Test func mirroringReflectsAboutTheVisualDuration() {
    let mirrored = mirroredKeepRange(ShotKeepRange(start: 1, end: 3), sourceDurationSeconds: 5)
    #expect(abs(mirrored.start - 2) < 1e-9)
    #expect(abs(mirrored.end - 4) < 1e-9)
    #expect(abs(mirrored.seconds - 2) < 1e-9)
}

/// The overshoot guard. `shotCutPlan` fills `keep.end` from an integral
/// per-segment estimate before exact media durations load, so a 5.0s span can
/// name a 4.8s file. Reflecting about the file would push `start` negative, and
/// clamping that to zero would shorten the span and trip the player's assert.
@Test func mirroringAnOvershootingSpanKeepsItsLength() {
    let keep = ShotKeepRange(start: 0, end: 5)
    let mirrored = mirroredKeepRange(keep, sourceDurationSeconds: 4.8)
    #expect(mirrored.start >= 0)
    #expect(abs(mirrored.seconds - keep.seconds) < 1e-9)
}

@Test func reversingSwapsOrderAndPointsAtTheProxies() throws {
    let out = reversedShotCutPlaybackItems(forwardItems(), proxies: fixtureProxies())
    try #require(out.count == 2)
    #expect(out.map(\.itemId) == ["b", "a"])
    #expect(out.map(\.url.lastPathComponent) == ["rev_b.mp4", "rev_a.mp4"])
    #expect(out.allSatisfy { $0.playsReversed })
    // Spans keep their lengths and lay down back to back from zero.
    #expect(out.map(\.durationSeconds) == [6, 4])
    #expect(out.map(\.outputStartSeconds) == [0, 6])
    // I2: still ordered intervals, still in authored material space.
    #expect(out.allSatisfy { $0.materialStartSeconds <= $0.materialEndSeconds })
    #expect(out.map(\.materialStartSeconds) == [4, 0])
}

/// A dissolve belongs to the join, not to the span that happens to sit on its
/// right — so reversing moves the frames one slot rather than carrying them
/// along with their old owner.
@Test func dissolveFramesShiftOneSlot() {
    var items = forwardItems()
    // Give the fixture four spans so the shift is unambiguous.
    var third = items[1]
    third.itemId = "c"
    third.outputStartSeconds = 10
    third.materialStartSeconds = 10
    third.materialEndSeconds = 16
    var fourth = items[1]
    fourth.itemId = "d"
    fourth.outputStartSeconds = 16
    fourth.materialStartSeconds = 16
    fourth.materialEndSeconds = 22
    items.append(contentsOf: [third, fourth])
    items[1].transitionFramesBefore = 12
    items[2].transitionFramesBefore = 0
    items[3].transitionFramesBefore = 6

    let out = reversedShotCutPlaybackItems(items, proxies: [:])
    #expect(out.map(\.transitionFramesBefore) == [0, 6, 0, 12])
}

/// The cap pass. A value that fit walking the joins one way can exceed the
/// frames available walking them the other, and the fingerprint records this
/// number — so it must never claim a dissolve that will not render.
@Test func reversedDissolvesAreRecappedAgainstTheNewNeighbours() throws {
    var items = forwardItems()
    // The 4s span now follows a very short one, which cannot fund 48 frames.
    items[0].durationSeconds = 0.25
    items[0].keepRange = ShotKeepRange(start: 0, end: 0.25)
    items[0].materialEndSeconds = 0.25
    items[1].transitionFramesBefore = 48

    let out = reversedShotCutPlaybackItems(items, proxies: [:])
    let frames = try #require(out.last?.transitionFramesBefore)
    // 0.25s of outgoing material is 6 frames, so at most 12 frames of overlap.
    #expect(frames <= 12)
    #expect(frames % 2 == 0)
}

@Test func aMissingProxyPlaysForwardAndSilentInItsNewSlot() throws {
    var proxies = fixtureProxies()
    proxies.removeValue(forKey: "/tmp/a.mp4")
    let out = reversedShotCutPlaybackItems(forwardItems(), proxies: proxies)
    let stranded = try #require(out.first { $0.itemId == "a" })
    #expect(stranded.url.lastPathComponent == "a.mp4")
    #expect(!stranded.playsReversed)
    #expect(!stranded.includeAudio)
    #expect(stranded.keepRange == ShotKeepRange(start: 0, end: 4))
    // I5 holds regardless: the span still occupies its own length.
    #expect(out.reduce(0) { $0 + $1.durationSeconds } == 10)
}

@Test func aProxyWithoutReversedAudioSilencesItsSpan() throws {
    let out = reversedShotCutPlaybackItems(forwardItems(), proxies: fixtureProxies(hasAudio: false))
    #expect(out.allSatisfy { $0.playsReversed })
    #expect(out.allSatisfy { !$0.includeAudio })
}

/// Reversing twice is the identity. Proxies of proxies stand in for the second
/// bake, which is exactly what the real machinery would produce.
@Test func reversingTwiceRestoresTheForwardCut() throws {
    let forward = forwardItems()
    let once = reversedShotCutPlaybackItems(forward, proxies: fixtureProxies())
    let backProxies: [String: ShotReverseProxyArtifact] = [
        "/tmp/rev_a.mp4": ShotReverseProxyArtifact(
            proxyId: "qa",
            sourcePath: "/tmp/rev_a.mp4",
            sourceDurationSeconds: 4,
            proxyDurationSeconds: 4,
            proxyPath: "/tmp/a.mp4",
            hasReversedAudio: true,
            status: "ready"
        ),
        "/tmp/rev_b.mp4": ShotReverseProxyArtifact(
            proxyId: "qb",
            sourcePath: "/tmp/rev_b.mp4",
            sourceDurationSeconds: 6,
            proxyDurationSeconds: 6,
            proxyPath: "/tmp/b.mp4",
            hasReversedAudio: true,
            status: "ready"
        )
    ]
    let twice = reversedShotCutPlaybackItems(once, proxies: backProxies)
    #expect(twice.map(\.itemId) == forward.map(\.itemId))
    #expect(twice.map(\.url.path) == forward.map(\.url.path))
    #expect(twice.map(\.outputStartSeconds) == forward.map(\.outputStartSeconds))
    for (restored, original) in zip(twice, forward) {
        let keep = try #require(restored.keepRange)
        let source = try #require(original.keepRange)
        #expect(abs(keep.start - source.start) < 1e-9)
        #expect(abs(keep.end - source.end) < 1e-9)
    }
}

@Test func reversingAnEmptyOrSingleSpanCutIsSafe() {
    #expect(reversedShotCutPlaybackItems([], proxies: [:]).isEmpty)
    let single = reversedShotCutPlaybackItems([forwardItems()[0]], proxies: fixtureProxies())
    #expect(single.count == 1)
    #expect(single[0].outputStartSeconds == 0)
    #expect(single[0].transitionFramesBefore == 0)
}

@Test func theAssemblyKeepsItsMaterialSpaceAndReportsItReversed() {
    let forward = ShotCutAssembly(
        playbackItems: forwardItems(),
        outputSeconds: 10,
        materialSeconds: 10
    )
    let reversed = reversedShotCutAssembly(forward, proxies: fixtureProxies())
    #expect(reversed.isReversed)
    // I1: material space is direction-free.
    #expect(reversed.materialSeconds == forward.materialSeconds)
    #expect(reversed.bands.count == forward.bands.count)
    #expect(reversed.planClips.count == forward.planClips.count)
    // I5: same length.
    #expect(abs(reversed.outputSeconds - forward.outputSeconds) < 1.0 / 240.0)
}

/// Falling back to forward playback must not claim to be reversed — the
/// player's cache key reads this to know when the last bake landed.
@Test func anAssemblyWithNoProxiesDoesNotClaimToBeReversed() {
    let forward = ShotCutAssembly(
        playbackItems: forwardItems(),
        outputSeconds: 10,
        materialSeconds: 10
    )
    #expect(!reversedShotCutAssembly(forward, proxies: [:]).isReversed)
}

// MARK: - Persistence

@Test func reverseFlagRoundTripsAndDefaultsOffForLegacyDocuments() throws {
    let list = ShotCutList(segmentCuts: [], isReversed: true)
    let data = try JSONEncoder().encode(list)
    let decoded = try JSONDecoder().decode(ShotCutList.self, from: data)
    #expect(decoded.isReversed)

    // A cut list written before reverse existed carries no key at all.
    let legacy = try JSONDecoder().decode(
        ShotCutList.self,
        from: Data(#"{"segmentCuts":[]}"#.utf8)
    )
    #expect(!legacy.isReversed)
}

/// `isEmpty` is load-bearing beyond tidiness: the download path uses it to
/// decide whether the file earns its `_cut` suffix, so a reversed CUT must not
/// look like an untouched one.
@Test func aReversedCutListIsNotEmpty() {
    #expect(ShotCutList().isEmpty)
    #expect(!ShotCutList(segmentCuts: [], isReversed: true).isEmpty)
    #expect(ShotCutList(segmentCuts: [], isReversed: true).normalized().isReversed)
}

private func proxy(
    _ id: String,
    source: String,
    status: String = "ready",
    proxyPath: String? = nil
) -> ShotReverseProxyArtifact {
    ShotReverseProxyArtifact(
        proxyId: id,
        sourcePath: source,
        sourceDurationSeconds: 5,
        proxyDurationSeconds: 5,
        proxyPath: proxyPath ?? "/tmp/\(id).mp4",
        hasReversedAudio: true,
        bakerVersion: 1,
        status: status
    )
}

@Test func onlyReadyProxiesWithFilesOnDiskResolve() {
    var shot = ProjectShot(shotId: "s1", name: "Shot")
    shot.reverseProxies = [
        proxy("p1", source: "/tmp/a.mp4"),
        proxy("p2", source: "/tmp/b.mp4", status: "baking"),
        proxy("p3", source: "/tmp/c.mp4", proxyPath: "/tmp/gone.mp4")
    ]
    let resolved = shot.readyReverseProxiesBySourcePath { $0 != "/tmp/gone.mp4" }
    #expect(resolved.keys.sorted() == ["/tmp/a.mp4"])
    #expect(shot.reverseProxy(forSourcePath: "/tmp/b.mp4")?.status == "baking")
    #expect(shot.reverseProxy(forSourcePath: "") == nil)
}

@Test func upsertingAProxyReplacesByIdentity() {
    var shot = ProjectShot(shotId: "s1", name: "Shot")
    shot = shot.upsertingReverseProxy(proxy("p1", source: "/tmp/a.mp4", status: "baking"), now: "t1")
    shot = shot.upsertingReverseProxy(proxy("p1", source: "/tmp/a.mp4"), now: "t2")
    #expect(shot.reverseProxies.count == 1)
    #expect(shot.reverseProxies[0].isReady)
}

/// A dead local encode has no remote job to resume, so relaunch must not leave
/// it claiming to be in flight.
@Test func interruptedBakesFailOnRelaunch() {
    var shot = ProjectShot(shotId: "s1", name: "Shot")
    shot.reverseProxies = [proxy("p1", source: "/tmp/a.mp4", status: "baking")]
    let (recovered, changed) = shot.failingInFlightRenderVersions(now: "t9")
    #expect(changed)
    #expect(recovered.reverseProxies[0].status == "failed")
}

/// A duplicate has no clips yet, so it can have no proxies — but it is still a
/// reversed CUT, and re-bakes as soon as it renders.
@Test func duplicatingKeepsTheReverseFlagAndDropsTheProxies() {
    var shot = ProjectShot(shotId: "s1", name: "Shot")
    shot.cutList = ShotCutList(segmentCuts: [], isReversed: true)
    shot.reverseProxies = [proxy("p1", source: "/tmp/a.mp4")]
    let copy = shot.duplicated(now: "t2")
    #expect(copy.cutList.isReversed)
    #expect(copy.reverseProxies.isEmpty)
}

// MARK: - The baker

/// Reversing interleaved audio one SAMPLE at a time would swap left and right
/// on every frame — audible as a stereo image that flips, and the single
/// likeliest defect in the whole feature.
@Test func reversingAudioKeepsChannelsTogether() {
    let stereo: [Float] = [1, -1, 2, -2, 3, -3]
    #expect(ReverseProxyBaker.reversedByFrame(stereo, channelCount: 2) == [3, -3, 2, -2, 1, -1])

    let mono: [Float] = [1, 2, 3]
    #expect(ReverseProxyBaker.reversedByFrame(mono, channelCount: 1) == [3, 2, 1])
}

private func fixturePixelBuffer(size: CGSize, level: UInt8) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(size.width),
        Int(size.height),
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary] as CFDictionary,
        &buffer
    )
    guard status == kCVReturnSuccess, let buffer else {
        throw ScreenGraphError.capture("Could not allocate a fixture frame.")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    if let base = CVPixelBufferGetBaseAddress(buffer) {
        let bytes = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
        memset(base, Int32(level), bytes)
    }
    return buffer
}

/// A clip whose every frame is a distinct flat grey, so frame order is
/// readable straight off the decoded picture.
private func writeFixtureVideo(to url: URL, frameCount: Int, levelStep: Int = 4) async throws {
    let size = CGSize(width: 160, height: 120)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: 6
            ]
        ]
    )
    input.expectsMediaDataInRealTime = false
    writer.add(input)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
    )
    guard writer.startWriting() else {
        throw writer.error ?? ScreenGraphError.capture("Could not start the fixture writer.")
    }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(2))
        }
        let pixels = try fixturePixelBuffer(size: size, level: UInt8(4 + frame * levelStep))
        guard adaptor.append(
            pixels,
            withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 24)
        ) else {
            throw ScreenGraphError.capture("Could not append a fixture frame.")
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status == .failed {
        throw writer.error ?? ScreenGraphError.capture("The fixture writer failed.")
    }
}

/// The grey level of each frame, in presentation order.
private func frameLevels(of url: URL) async throws -> [Int] {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    reader.add(output)
    guard reader.startReading() else {
        throw reader.error ?? ScreenGraphError.capture("Could not read the fixture back.")
    }
    defer { reader.cancelReading() }

    var levels: [Int] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            let row = CVPixelBufferGetBytesPerRow(pixels)
            let middle = base
                .advanced(by: row * (CVPixelBufferGetHeight(pixels) / 2))
                .advanced(by: 4 * (CVPixelBufferGetWidth(pixels) / 2))
                .assumingMemoryBound(to: UInt8.self)
            levels.append(Int(middle[0]))
        }
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
    }
    return levels
}

/// The end-to-end pin: 60 frames at 24fps spans 2.5s, which exceeds the baker's
/// per-chunk second cap, so this also exercises the cross-chunk stamp handoff
/// where an off-by-one would show up as a duplicated or dropped frame.
@Test func bakingProducesAFrameExactReversedCopy() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("reverse-fixture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.mp4")
    let proxy = directory.appendingPathComponent("proxy.mp4")
    try await writeFixtureVideo(to: source, frameCount: 60)

    let sourceLevels = try await frameLevels(of: source)
    try #require(sourceLevels.count == 60)

    let result = try await ReverseProxyBaker.bake(sourceURL: source, outputURL: proxy)
    #expect(result.frameCount == 60)
    #expect(!result.hasReversedAudio)
    // Duration is preserved EXACTLY, not merely to within a frame: the gaps
    // telescope to D, so any drift means a frame was dropped or invented.
    #expect(abs(result.proxyDurationSeconds - result.sourceDurationSeconds) < 1.0 / 240.0)

    let proxyLevels = try await frameLevels(of: proxy)
    #expect(proxyLevels.count == sourceLevels.count)
    for (index, level) in proxyLevels.enumerated() where index < sourceLevels.count {
        let expected = sourceLevels[sourceLevels.count - 1 - index]
        #expect(abs(level - expected) <= 12, "frame \(index) read \(level), expected ~\(expected)")
    }
}

@Test func theCacheKeyTracksTheSourceFileAndTheBakerVersion() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("reverse-key-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("clip.mp4")
    try Data(repeating: 7, count: 2048).write(to: file)
    let first = try ReverseProxyBaker.cacheKey(sourcePath: file.path)
    #expect(first.hasPrefix("revx_"))
    #expect(try ReverseProxyBaker.cacheKey(sourcePath: file.path) == first)

    // A different file of a different size is a different bake.
    let other = directory.appendingPathComponent("other.mp4")
    try Data(repeating: 7, count: 4096).write(to: other)
    #expect(try ReverseProxyBaker.cacheKey(sourcePath: other.path) != first)
}

// MARK: - Strip geometry

/// Two 4s/6s bands laid out across 226pt (13pt inset each side, 200pt content).
private func stripLayout(reversed: Bool) -> ShotStripLayout {
    var layout = ShotStripLayout()
    layout.scale = 20            // 200pt over 10s of material
    layout.contentStart = 13
    layout.contentEnd = 213
    layout.isReversed = reversed
    layout.materialSeconds = 10
    layout.planClips = [
        ShotCutPlanClip(
            segmentKey: "a",
            clipPath: "/tmp/a.mp4",
            keepRanges: [ShotKeepRange(start: 0, end: 4)],
            materialStartSeconds: 0,
            materialSeconds: 4,
            outputStartSeconds: 0,
            headSeconds: 0
        ),
        ShotCutPlanClip(
            segmentKey: "b",
            clipPath: "/tmp/b.mp4",
            keepRanges: [ShotKeepRange(start: 0, end: 6)],
            materialStartSeconds: 4,
            materialSeconds: 6,
            outputStartSeconds: 4,
            headSeconds: 0
        )
    ]
    // Reversed, band b is drawn first.
    layout.bandFrames = reversed
        ? [1: (x: 13, width: 120), 0: (x: 133, width: 80)]
        : [0: (x: 13, width: 80), 1: (x: 93, width: 120)]
    return layout
}

@Test func theStripMirrorIsAnInvolution() {
    for reversed in [false, true] {
        let layout = stripLayout(reversed: reversed)
        for seconds in stride(from: 0.0, through: 10.0, by: 0.25) {
            let back = layout.materialSeconds(atX: layout.x(forMaterialSeconds: seconds))
            #expect(abs(back - seconds) < 1e-6, "reversed=\(reversed) at \(seconds)s")
        }
    }
}

@Test func reversingPutsTheLastMaterialAtTheLeftEdge() {
    let forward = stripLayout(reversed: false)
    let reversed = stripLayout(reversed: true)
    // t=0 and t=end land at the same absolute x on every row — the axis
    // contract — so mirroring means the strip's left edge is what plays FIRST.
    #expect(abs(forward.x(forMaterialSeconds: 0) - 13) < 1e-6)
    #expect(abs(reversed.x(forMaterialSeconds: 10) - 13) < 1e-6)
    #expect(abs(forward.x(forMaterialSeconds: 10) - 213) < 1e-6)
    #expect(abs(reversed.x(forMaterialSeconds: 0) - 213) < 1e-6)
}

/// THE test for this feature. A razor dragged across the same picture content
/// must persist identically whichever way the operator happens to be watching,
/// because the cut list is forward clip-local file seconds and the mirror never
/// leaves display space.
@Test func razorAuthoringIsDirectionBlind() throws {
    /// Exactly what `stripGesture` does: read display x back into forward
    /// material seconds, order the pair, then offset by the band's head.
    func authoredCut(fromX startX: CGFloat, toX endX: CGFloat, layout: ShotStripLayout) -> ShotSegmentCutRange? {
        guard let bandIndex = layout.bandIndex(atX: startX) else { return nil }
        let clip = layout.planClips[bandIndex]
        let lower = clip.materialStartSeconds
        let upper = clip.materialStartSeconds + clip.materialSeconds
        let a = min(max(layout.materialSeconds(atX: startX), lower), upper)
        let b = min(max(layout.materialSeconds(atX: endX), lower), upper)
        let draftStart = min(a, b)
        let draftEnd = max(a, b)
        return ShotSegmentCutRange(
            segmentKey: clip.segmentKey,
            clipPath: clip.clipPath,
            startSeconds: clip.headSeconds + (draftStart - clip.materialStartSeconds),
            endSeconds: clip.headSeconds + (draftEnd - clip.materialStartSeconds)
        )
    }

    let forward = stripLayout(reversed: false)
    let reversed = stripLayout(reversed: true)

    // The same PICTURE: material 1.0s to 2.5s inside the first band.
    let forwardCut = try #require(authoredCut(
        fromX: forward.x(forMaterialSeconds: 1.0),
        toX: forward.x(forMaterialSeconds: 2.5),
        layout: forward
    ))
    let reversedCut = try #require(authoredCut(
        fromX: reversed.x(forMaterialSeconds: 1.0),
        toX: reversed.x(forMaterialSeconds: 2.5),
        layout: reversed
    ))

    #expect(forwardCut.segmentKey == reversedCut.segmentKey)
    #expect(forwardCut.clipPath == reversedCut.clipPath)
    #expect(abs(forwardCut.startSeconds - reversedCut.startSeconds) < 1e-6)
    #expect(abs(forwardCut.endSeconds - reversedCut.endSeconds) < 1e-6)
    // And it is the cut the operator actually drew.
    #expect(abs(forwardCut.startSeconds - 1.0) < 1e-6)
    #expect(abs(forwardCut.endSeconds - 2.5) < 1e-6)
}

/// Dragging right-to-left on screen is the same gesture as dragging
/// left-to-right, in both directions: the draft is ordered before it persists.
@Test func aBackwardsDragAuthorsTheSameCut() {
    let reversed = stripLayout(reversed: true)
    let low = reversed.materialSeconds(atX: reversed.x(forMaterialSeconds: 1.0))
    let high = reversed.materialSeconds(atX: reversed.x(forMaterialSeconds: 2.5))
    #expect(abs(min(low, high) - 1.0) < 1e-6)
    #expect(abs(max(low, high) - 2.5) < 1e-6)
}

// MARK: - Frame boundaries

/// The invariant the whole feature rests on: the gaps telescope to `D`, so a
/// reversed proxy is exactly as long as the picture it came from.
@Test func boundaryGapsAlwaysTelescopeToTheSourceDuration() {
    let duration = 97.0 / 24.0
    let clean = (0..<97).map { Double($0) / 24.0 }
    let boundaries = ReverseProxyBaker.frameBoundaries(
        stamps: clean,
        visualDurationSeconds: duration
    )
    #expect(boundaries.count == 98)
    #expect(abs((boundaries.last ?? 0) - (boundaries.first ?? 0) - duration) < 1e-9)
}

/// The reported failure: a clip whose first reported stamp sits two frames in
/// produced a proxy short by exactly that offset — 3.958s against 4.042s —
/// because the gaps telescope to `D − p₀`. The opening frame displays from the
/// start of the track whatever its own stamp says.
@Test func aLeadingStampOffsetDoesNotShortenTheProxy() {
    let duration = 97.0 / 24.0
    // Stamps starting at frame 2, as the reader reported them.
    let offset = (2..<97).map { Double($0) / 24.0 }
    let boundaries = ReverseProxyBaker.frameBoundaries(
        stamps: offset,
        visualDurationSeconds: duration
    )
    #expect(boundaries.first == 0)
    let total = (boundaries.last ?? 0) - (boundaries.first ?? 0)
    #expect(abs(total - duration) < 1e-9)
    // Specifically NOT the 3.958s the bake produced.
    #expect(abs(total - 3.958_333) > 0.05)
}

@Test func boundariesRejectSamplesThePictureTimelineCannotContain() {
    let duration = 4.0
    let noisy: [Double] = [0, 0, .nan, 1, -0.5, 2, 4.0, 3, .infinity]
    let boundaries = ReverseProxyBaker.frameBoundaries(
        stamps: noisy,
        visualDurationSeconds: duration
    )
    // Four real frames plus the sentinel: the duplicate zero, the NaN, the
    // negative, the infinity, and the stamp sitting exactly on the end all go.
    #expect(boundaries == [0, 1, 2, 3, 4])
}

@Test func degenerateBoundaryInputsAreEmptyRatherThanWrong() {
    #expect(ReverseProxyBaker.frameBoundaries(stamps: [], visualDurationSeconds: 4).isEmpty)
    #expect(ReverseProxyBaker.frameBoundaries(stamps: [0, 1], visualDurationSeconds: 0).isEmpty)
    // Every stamp out of range leaves nothing to reverse.
    #expect(ReverseProxyBaker.frameBoundaries(stamps: [9, 10], visualDurationSeconds: 4).isEmpty)
}

/// The reported failure's shape: an odd frame count that is not a whole number
/// of seconds, spanning several chunks. This is the case that produced
/// "3.958s against 4.042s" — a proxy two frames short.
@Test func bakingAnOddLengthClipPreservesItsDurationExactly() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("reverse-odd-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.mp4")
    let proxy = directory.appendingPathComponent("proxy.mp4")
    try await writeFixtureVideo(to: source, frameCount: 97, levelStep: 2)

    let sourceLevels = try await frameLevels(of: source)
    try #require(sourceLevels.count == 97)

    let result = try await ReverseProxyBaker.bake(sourceURL: source, outputURL: proxy)
    #expect(result.frameCount == 97)
    // The assertion the reported failure would have tripped.
    #expect(abs(result.proxyDurationSeconds - result.sourceDurationSeconds) < 1.0 / 240.0)

    // 97 distinct greys in 8 bits leaves steps too small to survive H.264
    // frame by frame, so this checks ORDER: the sequence runs the other way,
    // and the ends have swapped.
    let proxyLevels = try await frameLevels(of: proxy)
    #expect(proxyLevels.count == sourceLevels.count)
    #expect(abs((proxyLevels.first ?? 0) - (sourceLevels.last ?? 0)) <= 6)
    #expect(abs((proxyLevels.last ?? 0) - (sourceLevels.first ?? 0)) <= 6)
    for (index, level) in proxyLevels.enumerated() where index > 0 {
        #expect(level <= proxyLevels[index - 1] + 6, "frame \(index) rose to \(level)")
    }
}

// MARK: - Non-destructiveness

/// The crash-recovery pin. A bake killed mid-write leaves a truncated proxy at
/// exactly the path the retry wants, and `AVAssetWriter` refuses a URL that
/// already exists — so without pre-removal one interrupted bake would make
/// every future bake of that clip fail forever.
@Test func bakingOverACrashLeftoverSucceeds() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("reverse-leftover-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.mp4")
    let proxy = directory.appendingPathComponent("proxy.mp4")
    try await writeFixtureVideo(to: source, frameCount: 24)

    // Exactly what a crash mid-bake leaves behind: a partial, unplayable file.
    try Data(repeating: 0, count: 4096).write(to: proxy)
    #expect(FileManager.default.fileExists(atPath: proxy.path))

    let result = try await ReverseProxyBaker.bake(sourceURL: source, outputURL: proxy)
    #expect(result.frameCount == 24)
    #expect(abs(result.proxyDurationSeconds - result.sourceDurationSeconds) < 1.0 / 240.0)
}

/// Reversing must never touch the material it reverses: the source file is
/// opened read-only and has to come back byte-identical.
@Test func bakingNeverModifiesTheSourceClip() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("reverse-readonly-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.mp4")
    let proxy = directory.appendingPathComponent("proxy.mp4")
    try await writeFixtureVideo(to: source, frameCount: 24)

    let before = try Data(contentsOf: source)
    let beforeModified = (try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate]) as? Date

    _ = try await ReverseProxyBaker.bake(sourceURL: source, outputURL: proxy)

    let after = try Data(contentsOf: source)
    let afterModified = (try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate]) as? Date
    #expect(before == after)
    #expect(beforeModified == afterModified)
}

/// A failed bake leaves nothing playable behind — a truncated proxy would read
/// as corrupt media long after the failure was forgotten.
@Test func aFailedBakeLeavesNoProxyFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("reverse-failure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // Not a video at all.
    let source = directory.appendingPathComponent("source.mp4")
    try Data(repeating: 9, count: 8192).write(to: source)
    let proxy = directory.appendingPathComponent("proxy.mp4")

    await #expect(throws: (any Error).self) {
        _ = try await ReverseProxyBaker.bake(sourceURL: source, outputURL: proxy)
    }
    #expect(!FileManager.default.fileExists(atPath: proxy.path))
    // And the unreadable source is still exactly as it was.
    #expect(try Data(contentsOf: source) == Data(repeating: 9, count: 8192))
}

/// Reverse is view state: turning it on records a Bool and a cache pointer, and
/// touches nothing that holds the operator's work.
@Test func reversingChangesNoEditableShotState() {
    var shot = ProjectShot(
        shotId: "s1",
        name: "Shot",
        entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "e2", frameImageId: "f2")
        ]
    )
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/a.mp4", startSeconds: 1, endSeconds: 2)
    ])
    let before = shot

    var reversed = shot
    reversed.cutList.isReversed = true
    reversed = reversed.upsertingReverseProxy(proxy("p1", source: "/tmp/a.mp4"), now: "t2")

    // Everything that represents work survives untouched.
    #expect(reversed.entries == before.entries)
    #expect(reversed.cutList.segmentCuts == before.cutList.segmentCuts)
    #expect(reversed.cutList.shotInSeconds == before.cutList.shotInSeconds)
    #expect(reversed.cutList.shotOutSeconds == before.cutList.shotOutSeconds)
    #expect(reversed.renderVersions == before.renderVersions)
    #expect(reversed.audioMix == before.audioMix)
    #expect(reversed.audioRegions == before.audioRegions)
    #expect(reversed.lookVersions == before.lookVersions)

    // And turning it off restores the original state exactly.
    var restored = reversed
    restored.cutList.isReversed = false
    restored.reverseProxies = []
    #expect(restored.cutList == before.cutList)
}
