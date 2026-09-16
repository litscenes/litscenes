import SwiftUI
import AppKit
@preconcurrency import AVFoundation

/// Two muted players started on one host clock. The longer take leads the
/// loop; the shorter holds its last frame until the leader wraps and both
/// restart together, so the eye compares the same beat on both sides.
@MainActor
final class ShotTakeComparePlayers: ObservableObject {
    let left = AVPlayer()
    let right = AVPlayer()
    @Published private(set) var isPlaying = false
    private var endObservers: [NSObjectProtocol] = []
    private var leaderIsLeft = true
    private var loadToken = 0

    init() {
        for player in [left, right] {
            player.isMuted = true
            player.actionAtItemEnd = .pause
            player.automaticallyWaitsToMinimizeStalling = false
        }
    }

    func load(leftPath: String, rightPath: String) {
        loadToken += 1
        let token = loadToken
        removeObservers()
        let leftItem = AVPlayerItem(url: URL(fileURLWithPath: leftPath))
        let rightItem = AVPlayerItem(url: URL(fileURLWithPath: rightPath))
        left.replaceCurrentItem(with: leftItem)
        right.replaceCurrentItem(with: rightItem)
        Task { [weak self] in
            let leftSeconds = (try? await leftItem.asset.load(.duration))?.seconds ?? 0
            let rightSeconds = (try? await rightItem.asset.load(.duration))?.seconds ?? 0
            guard let self, self.loadToken == token else { return }
            self.leaderIsLeft = shotCompareLoopLeaderIsLeft(leftSeconds: leftSeconds, rightSeconds: rightSeconds)
            self.observeEnds()
            await self.restartBoth()
        }
    }

    private func observeEnds() {
        removeObservers()
        for (player, isLeft) in [(left, true), (right, false)] {
            guard let item = player.currentItem else { continue }
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, isLeft == self.leaderIsLeft, self.isPlaying else { return }
                    await self.restartBoth()
                }
            }
            endObservers.append(observer)
        }
    }

    private func removeObservers() {
        endObservers.forEach { NotificationCenter.default.removeObserver($0) }
        endObservers.removeAll()
    }

    private var startHostTime: CMTime {
        CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: 0.05, preferredTimescale: 600)
    }

    func restartBoth() async {
        await left.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        await right.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        let host = startHostTime
        left.setRate(1, time: .zero, atHostTime: host)
        right.setRate(1, time: .zero, atHostTime: host)
        isPlaying = true
    }

    func togglePlayback() {
        if isPlaying {
            left.pause()
            right.pause()
            isPlaying = false
        } else {
            let host = startHostTime
            left.setRate(1, time: .invalid, atHostTime: host)
            right.setRate(1, time: .invalid, atHostTime: host)
            isPlaying = true
        }
    }

    func teardown() {
        removeObservers()
        left.pause()
        right.pause()
        left.replaceCurrentItem(with: nil)
        right.replaceCurrentItem(with: nil)
        isPlaying = false
    }
}

/// Side-by-side picture of two takes of one segment. Click a side (or press
/// 1 / 2) to put it in the film; the in-film side is ringed brass and inert.
struct ShotTakeCompareSurface: View {
    let compare: ShotTakeCompare
    @ObservedObject var players: ShotTakeComparePlayers
    var onUse: (ShotTakeOption) -> Void

    var body: some View {
        HStack(spacing: 2) {
            pane(compare.left, player: players.left, hint: "1")
            pane(compare.right, player: players.right, hint: "2")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(id: "\(compare.left.clipPath)|\(compare.right.clipPath)") {
            players.load(leftPath: compare.left.clipPath, rightPath: compare.right.clipPath)
        }
        .onDisappear { players.teardown() }
    }

    private func pane(_ option: ShotTakeOption, player: AVPlayer, hint: String) -> some View {
        VStack(spacing: 6) {
            Button { onUse(option) } label: {
                ShotComparePlayerView(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(option.isInFilm ? CanonColor.brass : PlateColor.cream.opacity(0.25),
                                    lineWidth: option.isInFilm ? 2 : 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(option.isInFilm)
            .help(option.isInFilm ? "Already in the film" : "Use Take \(option.takeNumber) in the film")
            PlateLabel(
                text: option.isInFilm ? "Take \(option.takeNumber) · In film" : "Take \(option.takeNumber) · Click or press \(hint) to use",
                size: 8,
                weight: .bold,
                color: option.isInFilm ? CanonColor.brass : PlateColor.cream
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

/// A bare player layer for one compare pane, reusing the scrub host view.
struct ShotComparePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> ScrubPlayerHostView {
        let view = ScrubPlayerHostView(frame: .zero)
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: ScrubPlayerHostView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
