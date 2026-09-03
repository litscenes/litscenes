import AVFoundation
import AppKit
import Foundation

// MARK: - Filmstrip tile generation (the loader renders, the plan decides)

/// Process-wide tile store, so the strip unmounting for a Look — or the
/// modal reopening — never refetches what it already showed. NSCache is
/// thread-safe; background waves write, the main-actor Canvas reads (the
/// same contract `StripThumbnailCache` already relies on).
final class ShotFilmstripTileStore: @unchecked Sendable {
    static let shared = ShotFilmstripTileStore()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 1200
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: NSImage, forKey key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

/// On-demand, zoom-aware frame generation for the Picture strip — modeled on
/// `SoundWaveformLoader` (published state on the main actor, detached work,
/// deinit cancels), with per-clip "waves": one `images(for:)` pass walks the
/// file in decode order and yields tiles incrementally, and cancelling the
/// wave's task abandons the remainder structurally.
@MainActor
final class ShotFilmstripLoader: ObservableObject {
    /// Bumped once per landed batch (coalesced). Publishing an image dict
    /// would copy per pass; a revision counter + synchronous store reads is
    /// the cheap equivalent for a Canvas body.
    @Published private(set) var revision = 0

    private struct Wave {
        var rung: Double
        var keys: Set<String>
        var task: Task<Void, Never>
    }

    private static let maxConcurrentWaves = 3

    private var waves: [String: Wave] = [:]
    private var pending: [(clipPath: String, tiles: [ShotFilmstripTile], rung: Double, heightPixels: Int)] = []
    /// Clips whose whole wave failed this session — don't hot-loop on them.
    private var unavailableClipPaths: Set<String> = []
    private var mtimeByPath: [String: Int] = [:]
    private var revisionBumpPending = false

    deinit {
        for wave in waves.values {
            wave.task.cancel()
        }
    }

    static func heightBucket(_ heightPixels: Int) -> Int {
        max((heightPixels + 31) / 32 * 32, 32)
    }

    static func tileKey(clipPath: String, mtime: Int, rung: Double, rungIndex: Int, heightBucket: Int) -> String {
        "\(clipPath)|\(mtime)|\(rung)|\(rungIndex)|\(heightBucket)"
    }

    /// Synchronous cache read; never enqueues — safe from a Canvas body.
    func tile(clipPath: String, rung: Double, rungIndex: Int, heightPixels: Int) -> NSImage? {
        ShotFilmstripTileStore.shared.image(forKey: Self.tileKey(
            clipPath: clipPath,
            mtime: mtime(for: clipPath),
            rung: rung,
            rungIndex: rungIndex,
            heightBucket: Self.heightBucket(heightPixels)
        ))
    }

    /// Diff wanted vs cached vs in-flight; cancel superseded waves; launch or
    /// queue the rest. Called from `.task(id:)`, never during view update.
    func requestTiles(_ tiles: [ShotFilmstripTile], rung: Double, heightPixels: Int) {
        let byClip = Dictionary(grouping: tiles, by: \.clipPath)
        for (clipPath, clipTiles) in byClip {
            guard !clipPath.isEmpty, !unavailableClipPaths.contains(clipPath) else { continue }
            let bucket = Self.heightBucket(heightPixels)
            let fileMTime = mtime(for: clipPath)
            let missing = clipTiles.filter { tile in
                ShotFilmstripTileStore.shared.image(forKey: Self.tileKey(
                    clipPath: clipPath,
                    mtime: fileMTime,
                    rung: rung,
                    rungIndex: tile.rungIndex,
                    heightBucket: bucket
                )) == nil
            }
            guard !missing.isEmpty else { continue }
            let missingKeys = Set(missing.map { Self.tileKey(
                clipPath: clipPath,
                mtime: fileMTime,
                rung: rung,
                rungIndex: $0.rungIndex,
                heightBucket: bucket
            ) })
            if let wave = waves[clipPath] {
                // Same rung and already covering everything wanted: let it run.
                if wave.rung == rung, missingKeys.isSubset(of: wave.keys) { continue }
                wave.task.cancel()
                waves[clipPath] = nil
            }
            if waves.count < Self.maxConcurrentWaves {
                launchWave(clipPath: clipPath, tiles: missing, rung: rung, heightPixels: heightPixels)
            } else {
                pending.removeAll { $0.clipPath == clipPath }
                pending.append((clipPath, missing, rung, heightPixels))
            }
        }
    }

    private func mtime(for clipPath: String) -> Int {
        if let cached = mtimeByPath[clipPath] { return cached }
        let date = (try? FileManager.default.attributesOfItem(atPath: clipPath)[.modificationDate]) as? Date
        let mtime = Int(date?.timeIntervalSince1970 ?? 0)
        mtimeByPath[clipPath] = mtime
        return mtime
    }

    private func launchWave(clipPath: String, tiles: [ShotFilmstripTile], rung: Double, heightPixels: Int) {
        let bucket = Self.heightBucket(heightPixels)
        let fileMTime = mtime(for: clipPath)
        // Sorted ascending so the generator walks the file once in decode
        // order — the case `images(for:)` exists for.
        let slots = tiles
            .sorted { $0.fileSeconds < $1.fileSeconds }
            .map { (seconds: $0.fileSeconds, key: Self.tileKey(
                clipPath: clipPath,
                mtime: fileMTime,
                rung: rung,
                rungIndex: $0.rungIndex,
                heightBucket: bucket
            )) }
        let keys = Set(slots.map(\.key))
        let tolerance = ShotFilmstripLadder.tolerance(forRung: rung)
        let task = Task.detached(priority: .utility) { [weak self] in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: clipPath)))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 0, height: CGFloat(bucket))
            generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)
            var keyByRequestedValue: [Int: String] = [:]
            var times: [CMTime] = []
            for slot in slots {
                let time = CMTime(seconds: slot.seconds, preferredTimescale: 600)
                keyByRequestedValue[Int(time.value)] = slot.key
                times.append(time)
            }
            var landedAny = false
            for await result in generator.images(for: times) {
                if Task.isCancelled { break }
                switch result {
                case .success(requestedTime: let requested, let cgImage, actualTime: _):
                    guard let key = keyByRequestedValue[Int(requested.value)] else { continue }
                    let image = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    ShotFilmstripTileStore.shared.set(
                        image,
                        forKey: key,
                        cost: cgImage.bytesPerRow * cgImage.height
                    )
                    landedAny = true
                    await self?.noteTilesLanded()
                case .failure:
                    // One bad time stays a placeholder; the wave continues.
                    continue
                }
            }
            let failedOutright = !landedAny && !Task.isCancelled
            await self?.waveFinished(clipPath: clipPath, failedOutright: failedOutright)
        }
        waves[clipPath] = Wave(rung: rung, keys: keys, task: task)
    }

    /// Coalesces a burst of landings into one published change per runloop
    /// turn, so a 30-tile wave redraws a handful of times, not 30.
    private func noteTilesLanded() {
        guard !revisionBumpPending else { return }
        revisionBumpPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.revisionBumpPending = false
            self.revision += 1
        }
    }

    private func waveFinished(clipPath: String, failedOutright: Bool) {
        waves[clipPath] = nil
        if failedOutright {
            unavailableClipPaths.insert(clipPath)
        }
        while waves.count < Self.maxConcurrentWaves, !pending.isEmpty {
            let next = pending.removeFirst()
            guard waves[next.clipPath] == nil else { continue }
            launchWave(
                clipPath: next.clipPath,
                tiles: next.tiles,
                rung: next.rung,
                heightPixels: next.heightPixels
            )
        }
    }
}
