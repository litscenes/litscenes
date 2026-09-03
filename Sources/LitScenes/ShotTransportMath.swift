import Foundation

// THE TRANSPORT LAWS (pure — the modal wires them to AVPlayer).
//
// Shuttle is a ladder, not a slider: L walks 1→2→4 (capped by what the item
// can honestly do), J walks −1→−2→−4 only when the item can actually play in
// reverse — a composition preview usually cannot, and the fallback NEVER
// fakes a negative rate. A press against the current direction resets to the
// first rung of the new direction.

enum ShotTransportMath {
    static let shuttleLadder: [Float] = [1, 2, 4]

    /// The next forward shuttle rate after pressing L at `current`.
    /// Paused (0) or moving backward → first rung; else escalate, capped.
    static func nextForwardRate(current: Float, cap: Float = 4) -> Float {
        guard current > 0 else { return min(shuttleLadder[0], cap) }
        for rung in shuttleLadder where rung > current {
            return min(rung, cap)
        }
        return min(shuttleLadder.last ?? 1, cap)
    }

    /// The next reverse shuttle rate after pressing J at `current`.
    /// Returned NEGATIVE; same ladder mirrored.
    static func nextReverseRate(current: Float, cap: Float = 4) -> Float {
        -nextForwardRate(current: -current, cap: cap)
    }

    /// Frame-quantized step from the resolved playhead: quantize to the
    /// 24fps grid, move by `frames`, clamp into [0, duration]. A playhead
    /// resting exactly at the end is a valid position (judging an out-point).
    static func frameStepped(
        _ seconds: Double,
        frames: Int,
        durationSeconds: Double
    ) -> Double {
        let quantized = ShotAudioTiming.frameQuantizedStart(seconds)
        let stepped = quantized + Double(frames) * ShotAudioTiming.frameSeconds
        let floored = max(stepped, 0)
        guard durationSeconds > 0 else { return floored }
        return min(floored, durationSeconds)
    }
}

/// Loop is a persisted preference read at end-of-item time — the loop
/// observer closure is created once per player build, so it must read the
/// LIVE value here, never a captured copy.
enum ShotPlayerTransportPreference {
    static let loopKey = "shot_player_loop_enabled"

    static var loopEnabled: Bool {
        get { (LitScenesPreferences.store.object(forKey: loopKey) as? Bool) ?? true }
        set { LitScenesPreferences.store.set(newValue, forKey: loopKey) }
    }
}

/// One row of the keymap — the cheat sheet renders from this table and a test
/// pins uniqueness, so the sheet can never drift from the shipped keys.
struct ShotShortcutRow: Identifiable, Hashable, Sendable {
    var keys: String
    var action: String
    var scope: String

    var id: String { "\(scope)|\(keys)" }
}

enum ShotTransportKeymap {
    static let transportScope = "Transport"
    static let pictureScope = "Picture"
    static let audioScope = "Audio lanes"
    static let zoomScope = "Zoom"
    static let generalScope = "General"

    /// Every keyboard affordance in the shot player, one table. Audio-lane
    /// keys apply to the selected region on the focused lane; transport keys
    /// bubble to the modal from anywhere that doesn't consume them.
    static let all: [ShotShortcutRow] = [
        ShotShortcutRow(keys: "Space", action: "Play / pause", scope: transportScope),
        ShotShortcutRow(keys: "K", action: "Pause", scope: transportScope),
        ShotShortcutRow(keys: "L", action: "Shuttle forward 1× → 2× → 4×", scope: transportScope),
        ShotShortcutRow(keys: "J", action: "Shuttle reverse (steps back 1s when the preview can't play backward)", scope: transportScope),
        ShotShortcutRow(keys: ", / .", action: "Step one frame back / forward (⇧ = 10)", scope: transportScope),
        ShotShortcutRow(keys: "Home / End", action: "Jump to start / end", scope: transportScope),
        ShotShortcutRow(keys: "⌥L", action: "Toggle loop playback", scope: transportScope),
        ShotShortcutRow(keys: "B", action: "Blade: mark razor start, then commit at the playhead", scope: pictureScope),
        ShotShortcutRow(keys: "I / O", action: "Set shot IN / OUT at the playhead", scope: pictureScope),
        ShotShortcutRow(keys: "⌥I / ⌥O", action: "Clear shot IN / OUT", scope: pictureScope),
        ShotShortcutRow(keys: "← / →", action: "Nudge selected region ±1 frame (⇧ = 10)", scope: audioScope),
        ShotShortcutRow(keys: "[ / ]", action: "Trim selected region's edge to the playhead", scope: audioScope),
        ShotShortcutRow(keys: "S", action: "Split selected region at the playhead", scope: audioScope),
        ShotShortcutRow(keys: "M", action: "Mute / unmute selected region", scope: audioScope),
        ShotShortcutRow(keys: "L", action: "Loop / unloop selected region", scope: audioScope),
        ShotShortcutRow(keys: "⌫", action: "Delete selected region", scope: audioScope),
        ShotShortcutRow(keys: "⌘+ / ⌘−", action: "Zoom in / out around the playhead", scope: zoomScope),
        ShotShortcutRow(keys: "⌘0", action: "Zoom to fit", scope: zoomScope),
        ShotShortcutRow(keys: "Pinch / ⇄ scroll", action: "Zoom at the cursor / pan the window (sound editor)", scope: zoomScope),
        ShotShortcutRow(keys: "E", action: "Open the sound editor — all lanes, large", scope: generalScope),
        ShotShortcutRow(keys: "⎋", action: "Blade mark → razor → cut selection → region selection → close", scope: generalScope),
        ShotShortcutRow(keys: "?", action: "This keyboard reference", scope: generalScope)
    ]
}
