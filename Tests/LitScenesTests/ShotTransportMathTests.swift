import Foundation
import Testing
@testable import LitScenes

// Pure coverage for the transport laws: the shuttle ladder, frame stepping,
// and the keymap table the cheat sheet renders from.

private let frame = ShotAudioTiming.frameSeconds

@Test func forwardShuttleWalksTheLadderAndHonorsTheCap() {
    #expect(ShotTransportMath.nextForwardRate(current: 0) == 1)
    #expect(ShotTransportMath.nextForwardRate(current: 1) == 2)
    #expect(ShotTransportMath.nextForwardRate(current: 2) == 4)
    #expect(ShotTransportMath.nextForwardRate(current: 4) == 4)
    // A press against the current direction resets to the first rung.
    #expect(ShotTransportMath.nextForwardRate(current: -2) == 1)
    // An item that can't fast-forward caps at 2 and stays there.
    #expect(ShotTransportMath.nextForwardRate(current: 1, cap: 2) == 2)
    #expect(ShotTransportMath.nextForwardRate(current: 2, cap: 2) == 2)
    // An off-ladder rate (AVPlayer can report odd values) still escalates.
    #expect(ShotTransportMath.nextForwardRate(current: 1.5) == 2)
}

@Test func reverseShuttleMirrorsTheLadderNegative() {
    #expect(ShotTransportMath.nextReverseRate(current: 0) == -1)
    #expect(ShotTransportMath.nextReverseRate(current: -1) == -2)
    #expect(ShotTransportMath.nextReverseRate(current: -2) == -4)
    #expect(ShotTransportMath.nextReverseRate(current: -4) == -4)
    // Moving forward, J resets to the first reverse rung.
    #expect(ShotTransportMath.nextReverseRate(current: 2) == -1)
}

@Test func frameSteppedQuantizesStepsAndClamps() {
    // A mid-frame playhead quantizes to the grid before stepping.
    let stepped = ShotTransportMath.frameStepped(1.02, frames: 1, durationSeconds: 10)
    #expect(abs(stepped - (1.0 + frame)) < 0.000_001)

    // Ten-frame shift lands exactly ten frames away.
    let ten = ShotTransportMath.frameStepped(2, frames: 10, durationSeconds: 10)
    #expect(abs(ten - (2 + 10 * frame)) < 0.000_001)

    // Clamps at zero and at the duration (the end is a valid position —
    // judging an out-point happens there).
    #expect(ShotTransportMath.frameStepped(0, frames: -5, durationSeconds: 10) == 0)
    #expect(ShotTransportMath.frameStepped(9.99, frames: 5, durationSeconds: 10) == 10)

    // Unknown duration floors at zero and steps freely.
    let free = ShotTransportMath.frameStepped(5, frames: 3, durationSeconds: 0)
    #expect(abs(free - (5 + 3 * frame)) < 0.000_001)
}

@Test func keymapRowsAreUniquePerScope() {
    // The cheat sheet renders from this table; a duplicated key within one
    // scope would ship a lying reference.
    let ids = ShotTransportKeymap.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(!ShotTransportKeymap.all.isEmpty)
}
