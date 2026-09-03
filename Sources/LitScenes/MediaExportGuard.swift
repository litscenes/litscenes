import AVFoundation
import Foundation

/// A finished export that names its own failure.
///
/// The message is operator-facing, while the originating system error (when
/// one exists — a pure watchdog stall has none) stays reachable through
/// `NSUnderlyingErrorKey` so `shotRenderFailureSummary` still records the
/// `AVFoundationErrorDomain:-11883` / `NSOSStatusErrorDomain:-12912`
/// provenance that made this diagnosable.
struct MediaExportFailure: LocalizedError, CustomNSError {
    let message: String
    let underlying: Error?

    var errorDescription: String? { message }

    static var errorDomain: String { "LitScenes.MediaExport" }
    var errorCode: Int { 1 }
    var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let underlying {
            info[NSUnderlyingErrorKey] = underlying as NSError
        }
        return info
    }
}

/// `AVAssetExportSession` is not `Sendable`, but the two entry points the
/// guard needs are documented as safe to use from any thread: the async
/// `export(to:as:)`, and `cancelExport()`, whose entire purpose is
/// interrupting an in-flight export from somewhere else. This box carries
/// exactly those two uses across the task boundary and exposes nothing else.
private struct CarriedExportSession: @unchecked Sendable {
    let session: AVAssetExportSession
}

/// The single law for running an `AVAssetExportSession` to completion.
///
/// macOS shares one hardware video encoder (the AVE block) across every
/// process. When another process holds it — an in-progress screen recording
/// is the everyday case — an export neither fails fast nor makes progress: it
/// stalls, and VideoToolbox eventually surfaces `AVErrorEncodeFailed` over
/// `kVTVideoEncoderMalfunctionErr` as the bare, unactionable string "Cannot
/// Encode". A traced Clip Look sat in that stall for 361 seconds before it
/// finally errored.
///
/// Three consequences followed from exporting without a guard, and this type
/// exists to remove all three:
///   * callers awaited with no deadline, so an in-flight flag read as a hung
///     app for minutes;
///   * the abandoned export left a truncated, `moov`-less file on disk, which
///     outlives the failure and later reads as corrupt media;
///   * the operator was shown "Cannot Encode", naming neither cause nor cure.
enum MediaExportGuard {
    /// Shortest deadline granted to any export. Setup and teardown dominate
    /// brief clips, so the floor has to clear that fixed cost comfortably.
    static let floorSeconds: Double = 60

    /// A healthy export runs faster than realtime even with a CoreImage
    /// blur-fill composition in the graph. Ten times the content's own
    /// duration leaves generous headroom on a loaded machine while still
    /// catching a wedged encoder in a fraction of the 361-second stall.
    static let realtimeMultiple: Double = 10

    /// The longest legitimate export this app produces is a ten-minute Lucy
    /// source under a CoreImage blur-fill composition; the ceiling grants it
    /// 6× realtime (not the full 10×) while still guaranteeing a wedged
    /// encoder dies within the hour instead of hanging a flag forever.
    static let ceilingSeconds: Double = 3600

    /// `kVTVideoEncoderMalfunctionErr`, `kVTVideoEncoderNotAvailableNowErr`,
    /// and `kVTCouldNotCreateInstanceErr`: the three ways VideoToolbox says
    /// "the hardware encoder is not yours right now".
    static let encoderContentionStatusCodes: Set<Int> = [-12912, -12915, -12907]

    /// The recorder clause both encoder messages share — ONE copy, so the
    /// stall popup and the classified-contention popup can never drift apart
    /// on what to stop.
    static let recordingRemedy = "an in-progress screen recording, "
        + "including LitScenes' own File > Record Session"

    /// Names the remedy. The operator can act on this sentence; they cannot
    /// act on "Cannot Encode".
    static let encoderContentionMessage = "macOS would not hand this app the hardware video encoder. "
        + "Another process is holding it — the usual cause is \(recordingRemedy). "
        + "Stop the recording and try again."

    /// How long `contentSeconds` of media may encode before the export is
    /// considered wedged rather than slow.
    static func deadlineSeconds(forContentSeconds contentSeconds: Double) -> Double {
        guard contentSeconds.isFinite, contentSeconds > 0 else { return floorSeconds }
        return min(max(floorSeconds, contentSeconds * realtimeMultiple), ceilingSeconds)
    }

    /// `operation` names what was encoding ("render stitch", "cut export") and
    /// `contentSeconds` how much — so a stall names WHICH export wedged and
    /// over what length, instead of leaving the operator to guess which of the
    /// app's many guarded encodes the popup is about. A pure stall carries no
    /// classified error, so the encoder-contention remedy is phrased as the
    /// usual cause, not a certainty.
    static func stallMessage(
        deadlineSeconds: Double,
        fileType: AVFileType = .mp4,
        operation: String = "",
        contentSeconds: Double = 0
    ) -> String {
        let subject = operation.trimmed.nilIfEmpty
            ?? (fileType == .m4a ? "audio export" : "video export")
        let content = contentSeconds > 0
            ? " (\(String(format: "%.1f", contentSeconds))s of content)"
            : ""
        // Audio-only exports never touch the hardware video encoder — the
        // screen-recording remedy would be plausible-sounding false advice.
        guard fileType != .m4a else {
            return "The \(subject)\(content) made no progress for \(Int(deadlineSeconds.rounded())) seconds "
                + "and was stopped. Try again; if it keeps stalling, relaunch the app."
        }
        return "The \(subject)\(content) made no progress for \(Int(deadlineSeconds.rounded())) seconds "
            + "and was stopped. The usual cause is another process holding the shared hardware "
            + "video encoder — \(recordingRemedy). Stop the recording and try again; "
            + "if nothing is recording, retrying usually succeeds."
    }

    /// True when a failure is the shared encoder refusing to serve this
    /// process, rather than anything wrong with the asset being exported.
    static func isEncoderContentionFailure(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var depth = 0
        while let node = current, depth < 4 {
            if node.domain == AVFoundationErrorDomain,
               node.code == AVError.Code.encodeFailed.rawValue {
                return true
            }
            if node.domain == NSOSStatusErrorDomain,
               encoderContentionStatusCodes.contains(node.code) {
                return true
            }
            current = node.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    /// Cancellation is an outcome, not a fault: it must reach callers in its
    /// original shape so `isCancellationLikeError` keeps recognizing it.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == AVFoundationErrorDomain
            && nsError.code == AVError.Code.operationCancelled.rawValue
    }

    /// Runs `session` to completion under a stall deadline, leaving no
    /// partial file behind on any failure path.
    ///
    /// The deadline is derived from the session's own `timeRange`, so callers
    /// keep their existing one-line export and cannot forget to size it.
    static func export(
        _ session: AVAssetExportSession,
        to outputURL: URL,
        as fileType: AVFileType,
        operation: String = ""
    ) async throws {
        let content = await contentSeconds(for: session)
        let deadline = deadlineSeconds(forContentSeconds: content)
        let carried = CarriedExportSession(session: session)
        let timedOut = TimeoutFlag()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await carried.session.export(to: outputURL, as: fileType)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(deadline))
                    // Mark BEFORE cancelling: if the export child's
                    // cancellation error races us to the group, the catch
                    // must still classify this as a stall, never as an
                    // operator cancel.
                    timedOut.set()
                    // Release the encoder rather than leaving the stalled
                    // session holding it behind us.
                    carried.session.cancelExport()
                    throw MediaExportFailure(
                        message: stallMessage(
                            deadlineSeconds: deadline,
                            fileType: fileType,
                            operation: operation,
                            contentSeconds: content
                        ),
                        underlying: nil
                    )
                }
                // First finisher wins; the loser is cancelled on scope exit
                // and its error discarded by the group.
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            // A truncated export is worse than no export: it reads as corrupt
            // media long after the encoder recovers.
            try? FileManager.default.removeItem(at: outputURL)
            if timedOut.isSet, isCancellation(error) {
                throw MediaExportFailure(
                    message: stallMessage(
                        deadlineSeconds: deadline,
                        fileType: fileType,
                        operation: operation,
                        contentSeconds: content
                    ),
                    underlying: error
                )
            }
            if isCancellation(error) {
                // Caller gave up (task cancellation): the sleep dies before
                // the watchdog body runs, so nothing else tells the session
                // to stop — a wedged encoder must be released here too.
                carried.session.cancelExport()
                throw error
            }
            if isEncoderContentionFailure(error) {
                guard fileType != .m4a else { throw error }
                throw MediaExportFailure(message: encoderContentionMessage, underlying: error)
            }
            throw error
        }
    }

    /// The same stall deadline, for encoding work that is NOT an
    /// `AVAssetExportSession`.
    ///
    /// `AVAssetWriter` reaches the same shared AVE block by the same route and
    /// wedges the same way, so it needs the same deadline — but it is driven by
    /// the caller rather than run to completion by one call, so the two cannot
    /// share `export`. Everything that made the stall diagnosable lives here
    /// too: the deadline, the contention classifier, and the message that names
    /// the remedy.
    ///
    /// `onStall` releases whatever holds the encoder (for a writer, that is
    /// `cancelWriting()`). Unlike `export`, this does NOT delete any output —
    /// callers bake into a scratch directory and clean it up on their own
    /// failure path, so there is no single file here to name.
    static func watchdog<T: Sendable>(
        contentSeconds: Double,
        fileType: AVFileType = .mp4,
        operationName: String = "",
        onStall: @escaping @Sendable () -> Void,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let deadline = deadlineSeconds(forContentSeconds: contentSeconds)
        let timedOut = TimeoutFlag()
        func stall(underlying: Error? = nil) -> MediaExportFailure {
            MediaExportFailure(
                message: stallMessage(
                    deadlineSeconds: deadline,
                    fileType: fileType,
                    operation: operationName,
                    contentSeconds: contentSeconds
                ),
                underlying: underlying
            )
        }
        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(for: .seconds(deadline))
                    // Mark BEFORE releasing, for the same reason `export` does:
                    // the operation's own cancellation error may win the race
                    // to the group, and this must still read as a stall.
                    timedOut.set()
                    onStall()
                    throw stall()
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw stall()
                }
                return first
            }
        } catch {
            if timedOut.isSet, isCancellation(error) {
                throw stall(underlying: error)
            }
            if isCancellation(error) {
                // The caller gave up, so the watchdog body never runs and
                // nothing else would tell a wedged encoder to let go.
                onStall()
                throw error
            }
            if isEncoderContentionFailure(error) {
                guard fileType != .m4a else { throw error }
                throw MediaExportFailure(message: encoderContentionMessage, underlying: error)
            }
            throw error
        }
    }

    /// Set by the watchdog before it cancels the session, read by the catch:
    /// makes stall-vs-operator-cancel classification deterministic even when
    /// the cancelled export child's error wins the race to the group.
    private final class TimeoutFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// The session's export length: its explicit `timeRange` when set,
    /// otherwise the whole asset. An unreadable duration yields 0, which the
    /// deadline treats as "floor only".
    private static func contentSeconds(for session: AVAssetExportSession) async -> Double {
        let range = session.timeRange
        if range.duration.isValid,
           !range.duration.isIndefinite,
           range.duration != .positiveInfinity,
           range.duration.seconds > 0 {
            return range.duration.seconds
        }
        if let duration = try? await session.asset.load(.duration),
           duration.isValid,
           !duration.isIndefinite,
           duration.seconds > 0 {
            return duration.seconds
        }
        return 0
    }
}
