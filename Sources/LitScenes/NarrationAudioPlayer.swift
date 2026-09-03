import SwiftUI
import AVFoundation

/// Lightweight AVAudioPlayer wrapper for narration play bars: play/pause with
/// live progress. One player per surface; switching sources stops playback.
@MainActor
final class NarrationAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var loadedPath = ""

    func toggle(path: String) {
        if isPlaying {
            pause()
        } else {
            play(path: path)
        }
    }

    func play(path: String) {
        if loadedPath != path || player == nil {
            stop()
            guard let loaded = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else { return }
            loaded.delegate = self
            player = loaded
            loadedPath = path
            duration = loaded.duration
        }
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        refresh()
    }

    func stop() {
        player?.stop()
        player = nil
        loadedPath = ""
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        guard let player else { return }
        currentTime = player.currentTime
        duration = player.duration
        progress = player.duration > 0 ? min(1, max(0, player.currentTime / player.duration)) : 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.progress = 0
            self.currentTime = 0
            self.stopTimer()
        }
    }
}
