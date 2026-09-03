import Foundation
import Testing
@testable import LitScenes

// File > Record Session pure logic: the pause-aware clock, the Downloads
// filename convention, and the single-vs-multi segment finalize decision.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func sessionClockAccumulatesAcrossPauseResume() {
    var clock = SessionRecordingClock()
    clock.segmentDidStart(at: t0)
    clock.segmentDidEnd(at: t0.addingTimeInterval(10))
    clock.segmentDidStart(at: t0.addingTimeInterval(30))
    #expect(clock.elapsedSeconds(now: t0.addingTimeInterval(35)) == 15)
}

@Test func sessionClockFreezesWhilePaused() {
    var clock = SessionRecordingClock()
    clock.segmentDidStart(at: t0)
    clock.segmentDidEnd(at: t0.addingTimeInterval(8))
    // Paused: elapsed reads the accumulated total no matter how late "now" is.
    #expect(clock.elapsedSeconds(now: t0.addingTimeInterval(500)) == 8)
    #expect(!clock.isRunning)
}

@Test func sessionClockIgnoresDoubleTransitions() {
    var clock = SessionRecordingClock()
    // Ending a clock that never started is a no-op.
    clock.segmentDidEnd(at: t0)
    #expect(clock.elapsedSeconds(now: t0.addingTimeInterval(5)) == 0)

    clock.segmentDidStart(at: t0)
    // A second start must not move the segment origin.
    clock.segmentDidStart(at: t0.addingTimeInterval(4))
    clock.segmentDidEnd(at: t0.addingTimeInterval(10))
    #expect(clock.elapsedSeconds(now: t0.addingTimeInterval(10)) == 10)
    // A second end must not double-count the segment.
    clock.segmentDidEnd(at: t0.addingTimeInterval(20))
    #expect(clock.elapsedSeconds(now: t0.addingTimeInterval(20)) == 10)
}

@Test func sessionClockElapsedLabel() {
    #expect(SessionRecordingClock.elapsedLabel(0) == "00:00")
    #expect(SessionRecordingClock.elapsedLabel(65) == "01:05")
    #expect(SessionRecordingClock.elapsedLabel(3_753) == "1:02:33")
}

@Test func sessionFilenameMatchesConvention() {
    var components = DateComponents()
    components.year = 2026
    components.month = 7
    components.day = 29
    components.hour = 10
    components.minute = 32
    components.second = 15
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(identifier: "Pacific/Honolulu")!
    calendar.timeZone = zone
    let date = calendar.date(from: components)!
    #expect(
        SessionRecordingNaming.filename(for: date, timeZone: zone)
            == "LitScenes Session 2026-07-29 at 10.32.15.mov"
    )
}

@Test func sessionFilenameAvoidsCollisions() {
    let directory = URL(fileURLWithPath: "/tmp/downloads", isDirectory: true)
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    let fresh = SessionRecordingNaming.collisionSafeURL(in: directory, date: date) { _ in false }
    #expect(fresh.lastPathComponent == SessionRecordingNaming.filename(for: date))

    // Base and " 2" both taken: the next free ordinal wins.
    let stem = (SessionRecordingNaming.filename(for: date) as NSString).deletingPathExtension
    let taken: Set<String> = [
        "\(stem).mov",
        "\(stem) 2.mov"
    ]
    let third = SessionRecordingNaming.collisionSafeURL(in: directory, date: date) { url in
        taken.contains(url.lastPathComponent)
    }
    #expect(third.lastPathComponent == "\(stem) 3.mov")
}

@Test func sessionFinalizePlanDecision() {
    let a = URL(fileURLWithPath: "/tmp/segment-001.mov")
    let b = URL(fileURLWithPath: "/tmp/segment-002.mov")
    #expect(SessionFinalizePlan.plan(forCompletedSegments: []) == .none)
    #expect(SessionFinalizePlan.plan(forCompletedSegments: [a]) == .moveSingle(a))
    #expect(SessionFinalizePlan.plan(forCompletedSegments: [a, b]) == .stitch([a, b]))
}
