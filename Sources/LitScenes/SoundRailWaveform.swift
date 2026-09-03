import AVFoundation
import Foundation
import SwiftUI

struct SoundWaveform: Equatable, Sendable {
    var soundId: String
    var path: String
    var modifiedAt: String
    var samples: [Double]
    var durationSeconds: Double
    var updatedAt: String

    var isSilent: Bool {
        samples.allSatisfy { $0 <= 0.001 }
    }
}

enum SoundWaveformLoadState: Equatable {
    case idle
    case loading
    case ready(SoundWaveform)
    case unavailable(String)
}

@MainActor
final class SoundWaveformLoader: ObservableObject {
    @Published private var states: [String: SoundWaveformLoadState] = [:]

    private var cache: [String: SoundWaveform] = [:]
    private var tasks: [String: Task<SoundWaveform, Error>] = [:]

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    func state(for asset: SoundSceneAsset, sampleCount: Int) -> SoundWaveformLoadState {
        let key = cacheKey(for: asset, sampleCount: sampleCount)
        if let state = states[key] {
            return state
        }
        if let waveform = cache[key] {
            return .ready(waveform)
        }
        return .idle
    }

    func loadIfNeeded(for asset: SoundSceneAsset, sampleCount: Int) {
        let normalizedSampleCount = Self.normalizedSampleCount(sampleCount)
        let key = cacheKey(for: asset, sampleCount: normalizedSampleCount)
        if let waveform = cache[key] {
            states[key] = .ready(waveform)
            return
        }
        if tasks[key] != nil {
            return
        }

        guard !asset.path.trimmed.isEmpty, FileManager.default.fileExists(atPath: asset.path) else {
            states[key] = .unavailable("Audio file missing.")
            return
        }

        states[key] = .loading
        let soundId = asset.soundId
        let path = asset.path
        let modifiedAt = asset.modifiedAt
        let durationSeconds = asset.durationSeconds
        let extractionTask = Task.detached(priority: .utility) {
            try await SoundWaveformExtractor.extract(
                soundId: soundId,
                path: path,
                modifiedAt: modifiedAt,
                durationSeconds: durationSeconds,
                sampleCount: normalizedSampleCount
            )
        }
        tasks[key] = extractionTask

        Task { [weak self] in
            do {
                let waveform = try await extractionTask.value
                self?.finish(key: key, waveform: waveform)
            } catch is CancellationError {
                self?.finishCancelled(key: key)
            } catch {
                self?.finishUnavailable(key: key)
            }
        }
    }

    private static func normalizedSampleCount(_ sampleCount: Int) -> Int {
        min(max(sampleCount, 24), 320)
    }

    private func cacheKey(for asset: SoundSceneAsset, sampleCount: Int) -> String {
        [
            asset.soundId,
            asset.path,
            asset.modifiedAt,
            "\(Self.normalizedSampleCount(sampleCount))"
        ].joined(separator: "|")
    }

    private func finish(key: String, waveform: SoundWaveform) {
        cache[key] = waveform
        states[key] = .ready(waveform)
        tasks[key] = nil
    }

    private func finishCancelled(key: String) {
        states[key] = .idle
        tasks[key] = nil
    }

    private func finishUnavailable(key: String) {
        states[key] = .unavailable("Waveform unavailable.")
        tasks[key] = nil
    }
}

private enum SoundWaveformExtractionError: Error {
    case missingFile
    case unsupportedFormat
}

enum SoundWaveformExtractor {
    static func extract(
        soundId: String,
        path: String,
        modifiedAt: String,
        durationSeconds: Double,
        sampleCount: Int
    ) async throws -> SoundWaveform {
        guard FileManager.default.fileExists(atPath: path) else {
            throw SoundWaveformExtractionError.missingFile
        }

        let url = URL(fileURLWithPath: path)
        let file = try AVAudioFile(forReading: url)
        let totalFrames = max(file.length, 1)
        let format = file.processingFormat
        let channelCount = max(Int(format.channelCount), 1)
        let chunkFrameCount = AVAudioFrameCount(min(Int64(8_192), totalFrames))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(chunkFrameCount, 1)) else {
            throw SoundWaveformExtractionError.unsupportedFormat
        }

        var peaks = Array(repeating: Float(0), count: max(sampleCount, 1))
        while file.framePosition < totalFrames {
            let startFrame = file.framePosition
            let remainingFrames = max(totalFrames - startFrame, 0)
            let framesToRead = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remainingFrames))
            if framesToRead == 0 {
                break
            }

            try file.read(into: buffer, frameCount: framesToRead)
            let framesRead = Int(buffer.frameLength)
            guard framesRead > 0 else {
                break
            }
            guard let channelData = buffer.floatChannelData else {
                throw SoundWaveformExtractionError.unsupportedFormat
            }

            for frameIndex in 0..<framesRead {
                var framePeak = Float(0)
                for channelIndex in 0..<channelCount {
                    let value = abs(channelData[channelIndex][frameIndex])
                    if value.isFinite {
                        framePeak = max(framePeak, value)
                    }
                }

                let absoluteFrame = startFrame + AVAudioFramePosition(frameIndex)
                let progress = min(max(Double(absoluteFrame) / Double(totalFrames), 0), 0.999_999)
                let peakIndex = min(peaks.count - 1, Int(progress * Double(peaks.count)))
                peaks[peakIndex] = max(peaks[peakIndex], framePeak)
            }
        }

        let maxPeak = peaks.max() ?? 0
        let normalizedPeaks = peaks.map { peak -> Double in
            guard maxPeak > 0 else { return 0 }
            return min(max(Double(peak / maxPeak), 0), 1)
        }
        let fileDurationSeconds = format.sampleRate > 0 ? Double(totalFrames) / format.sampleRate : durationSeconds

        return SoundWaveform(
            soundId: soundId,
            path: path,
            modifiedAt: modifiedAt,
            samples: normalizedPeaks,
            durationSeconds: max(durationSeconds, fileDurationSeconds, 0),
            updatedAt: DateFormats.now()
        )
    }
}

struct SoundRailWaveformView: View {
    let state: SoundWaveformLoadState
    let progress: Double
    let isEnabled: Bool
    let onSeek: (Double) -> Void

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var samples: [Double] {
        switch state {
        case .ready(let waveform):
            return waveform.samples.isEmpty ? placeholderSamples : waveform.samples
        case .idle, .loading:
            return placeholderSamples
        case .unavailable:
            return mutedPlaceholderSamples
        }
    }

    private var isSilent: Bool {
        if case .ready(let waveform) = state {
            return waveform.isSilent
        }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(CanonColor.paper.opacity(0.52))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper.opacity(0.78)))

                waveformCanvas(size: geometry.size)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)

                if case .loading = state {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.62)
                }

                if isSilent {
                    Rectangle()
                        .fill(CanonColor.ink.opacity(0.22))
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        seek(to: value.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: 38)
        .opacity(isEnabled ? 1 : 0.58)
        .help(isEnabled ? "Seek audio" : "Load audio before seeking")
        .accessibilityLabel("Audio waveform")
    }

    private func waveformCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let insetWidth = max(canvasSize.width, 1)
            let insetHeight = max(canvasSize.height, 1)
            let count = max(samples.count, 1)
            let gap = CGFloat(count > 96 ? 0.75 : 1)
            let totalGap = gap * CGFloat(max(count - 1, 0))
            let barWidth = max((insetWidth - totalGap) / CGFloat(count), 1)
            let hasAudibleSamples = samples.contains { $0 > 0.001 }

            for index in 0..<count {
                let rawSample = samples[index]
                let visibleSample = hasAudibleSamples ? max(rawSample, 0.045) : 0.02
                let barHeight = max(1.2, insetHeight * CGFloat(visibleSample))
                let x = CGFloat(index) * (barWidth + gap)
                let y = (insetHeight - barHeight) / 2
                let midpointProgress = min(max(Double((x + (barWidth / 2)) / insetWidth), 0), 1)
                let active = midpointProgress <= clampedProgress
                let color = active ? CanonColor.brass.opacity(0.86) : CanonColor.ink.opacity(0.18)
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 1.8)), with: .color(color))
            }

            let playheadX = min(max(CGFloat(clampedProgress) * insetWidth, 0), insetWidth)
            let playheadRect = CGRect(x: playheadX, y: 1, width: 1.2, height: max(insetHeight - 2, 1))
            context.fill(Path(playheadRect), with: .color(CanonColor.ink.opacity(0.70)))
        }
    }

    private func seek(to locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let ratio = min(max(Double(locationX / width), 0), 1)
        onSeek(ratio)
    }

    private var placeholderSamples: [Double] {
        (0..<72).map { index in
            let phase = Double(index) / 8
            return 0.22 + (sin(phase) + 1) * 0.10
        }
    }

    private var mutedPlaceholderSamples: [Double] {
        (0..<72).map { index in
            index.isMultiple(of: 2) ? 0.12 : 0.05
        }
    }
}
