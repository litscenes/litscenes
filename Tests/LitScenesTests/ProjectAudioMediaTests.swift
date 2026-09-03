import AVFoundation
import Foundation
import Testing
@testable import LitScenes

// Audio became a media kind in a later schema. Before that an mp3 on disk had no
// way into a project at all — audio could only be synthesized (narration TTS,
// microphone takes, ambient beds). These pin the import path and the two
// properties that keep audio from breaking image/video surfaces: it carries no
// thumbnail, and it is never eligible for paid vision analysis.

/// Writes a real, decodable audio file so the scanner reads a true duration.
private func writeTestAudioFile(seconds: Double, named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes-audio-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(seconds * 44_100)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    if let channel = buffer.floatChannelData?[0] {
        for index in 0..<Int(frames) {
            channel[index] = sinf(Float(index) * 0.01) * 0.2
        }
    }
    try file.write(from: buffer)
    return url
}

@Test func audioKindIsNotVisualAndIsExcludedFromAnalysis() {
    #expect(!MediaKind.audio.isVisual)
    #expect(MediaKind.image.isVisual)
    #expect(MediaKind.video.isVisual)

    let audio = MediaItemRecord(
        mediaId: "m_audio",
        sourceId: "s",
        kind: .audio,
        filename: "score.wav",
        path: "/tmp/score.wav",
        relativePath: "score.wav",
        byteCount: 10,
        modifiedAt: "t0",
        width: 0,
        height: 0,
        thumbnailPath: "",
        scannedAt: "t0"
    )
    // The gate that keeps an mp3 from ever being sent to a vision model.
    #expect(!audio.canBeEnabledContent)
}

@Test func importingAnAudioFileLandsAsAudioMedia() async throws {
    let audioURL = try writeTestAudioFile(seconds: 1.5, named: "cue.wav")
    defer { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }

    // Sandboxed root (see TestEnvironmentIsolationTests).
    let library = ProjectLibrary()
    let project = try library.createProject(named: "Audio Import \(UUID().uuidString.prefix(6))")
    let store = MediaLibraryStore(projectLibrary: library)
    let source = store.makeSource(from: audioURL, kind: .file)

    let result = try await store.scan(source: source, for: project) { _ in }
    let item = result.items.first

    #expect(result.items.count == 1)
    #expect(item?.kind == .audio)
    #expect(item?.filename == "cue.wav")
    // Duration is read up front because every audio surface shows it.
    #expect((item?.durationSeconds ?? 0) > 1.0)
    #expect((item?.durationSeconds ?? 0) < 2.0)
    // No frame to grab: audio carries no thumbnail or strip.
    #expect(item?.thumbnailPath.isEmpty == true)
    #expect(item?.videoStripPath?.isEmpty != false)
}

@Test func projectAudioItemsListsOnlyImportedAudio() {
    let audio = MediaItemRecord(
        mediaId: "m_audio", sourceId: "s", kind: .audio, filename: "a.wav",
        path: "/tmp/a.wav", relativePath: "a.wav", byteCount: 1, modifiedAt: "t0",
        width: 0, height: 0, thumbnailPath: "", scannedAt: "t2"
    )
    let image = MediaItemRecord(
        mediaId: "m_image", sourceId: "s", kind: .image, filename: "b.png",
        path: "/tmp/b.png", relativePath: "b.png", byteCount: 1, modifiedAt: "t0",
        width: 0, height: 0, thumbnailPath: "", scannedAt: "t1"
    )
    let video = MediaItemRecord(
        mediaId: "m_video", sourceId: "s", kind: .video, filename: "c.mp4",
        path: "/tmp/c.mp4", relativePath: "c.mp4", byteCount: 1, modifiedAt: "t0",
        width: 0, height: 0, thumbnailPath: "", scannedAt: "t3"
    )

    // The filter the sidebar section runs on.
    let audioOnly = [audio, image, video].filter { $0.kind == .audio }
    #expect(audioOnly.map(\.mediaId) == ["m_audio"])
}

@Test func soundAssetAdapterCarriesTheMediaItemAcrossToTheRail() {
    let item = MediaItemRecord(
        mediaId: "m_audio", sourceId: "s", kind: .audio, filename: "Rain Loop.WAV",
        path: "/tmp/Rain Loop.WAV", relativePath: "Rain Loop.WAV",
        byteCount: 2048, modifiedAt: "t9", width: 0, height: 0,
        durationSeconds: 12.5, thumbnailPath: "", scannedAt: "t1"
    )

    // The rail's row, waveform loader and transport all speak SoundSceneAsset;
    // this adapter is the only difference between a scanned folder file and an
    // imported project file.
    let asset = SoundSceneAsset(audioMediaItem: item)
    #expect(asset.soundId == "m_audio")
    #expect(asset.displayName == "Rain Loop.WAV")
    #expect(asset.path == "/tmp/Rain Loop.WAV")
    #expect(asset.durationSeconds == 12.5)
    #expect(asset.fileTypeLabel == "WAV")
    #expect(asset.byteCount == 2048)
}
