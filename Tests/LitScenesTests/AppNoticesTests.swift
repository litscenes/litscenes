import Foundation
import Testing
@testable import LitScenes

@Test
func diskUsageStateDocumentToleratesEmptyAndLegacyPayloads() throws {
    let empty = try JSONCoding.decoder.decode(AppNoticesStateDocument.self, from: Data("{}".utf8))
    #expect(empty.schemaVersion == "litscenes.app_notices.v1")
    #expect(empty.diskUsage == .empty)

    let legacy = try JSONCoding.decoder.decode(
        AppNoticesStateDocument.self,
        from: Data(#"{"schema_version":"litscenes.app_notices.v0","disk_usage":{"measured_at":"2026-07-25T00:00:00.000Z","locations":[{"key":"app-projects","byte_count":42,"unknown_field":true},{"key":"","byte_count":9},{"key":"app-projects"}],"unknown":1},"stray":"x"}"#.utf8)
    )
    #expect(legacy.schemaVersion == "litscenes.app_notices.v0")
    #expect(legacy.diskUsage.measuredAt == "2026-07-25T00:00:00.000Z")
    // normalized() on decode: empty keys dropped, duplicate keys deduped.
    #expect(legacy.diskUsage.locations.map(\.key) == ["app-projects"])
    #expect(legacy.diskUsage.locations.first?.byteCount == 42)
    #expect(legacy.diskUsage.locations.first?.group == "app")
    #expect(legacy.diskUsage.acknowledgment == nil)

    let encoded = try JSONCoding.encoder.encode(legacy)
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(text.contains(#""schema_version""#))
    #expect(text.contains(#""byte_count""#))
    let roundTripped = try JSONCoding.decoder.decode(AppNoticesStateDocument.self, from: encoded)
    #expect(roundTripped == legacy)
}

@Test
func diskUsageStoreRoundTripsAndDefaultsToEmpty() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_notices_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AppNoticesStore(root: root)

    #expect(store.load() == .empty)

    var document = AppNoticesStateDocument()
    document.diskUsage.measuredAt = "2026-07-26T00:00:00.000Z"
    document.diskUsage.locations = [
        DiskUsageLocationReading(
            key: "app-projects",
            label: "Projects",
            path: "/tmp/projects",
            group: "app",
            byteCount: 1_234,
            fileCount: 3,
            exists: true
        )
    ]
    document.diskUsage.acknowledgment = DiskUsageAcknowledgment(
        acknowledgedAt: "2026-07-26T00:00:01.000Z",
        acknowledgedTotalBytes: 1_234,
        acknowledgedOverThresholdKeys: ["app-projects"]
    )
    try store.save(document)
    #expect(store.load() == document)

    try Data("not json".utf8).write(to: store.fileURL)
    #expect(store.load() == .empty)
}

@Test
func diskUsageScannerMeasuresKnownTreeIncludingHiddenFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_notices_scan_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let present = root.appendingPathComponent("present", isDirectory: true)
    let nested = present.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let plannedFiles: [(url: URL, bytes: Int)] = [
        (present.appendingPathComponent("plain.bin"), 1_024),
        (present.appendingPathComponent(".hidden_blob"), 2_048),
        (nested.appendingPathComponent("deep.bin"), 4_096)
    ]
    for planned in plannedFiles {
        try Data(repeating: 0x5A, count: planned.bytes).write(to: planned.url)
    }

    let readings = DiskUsageScanner.measure([
        DiskUsageScanner.WatchedLocation(key: "ws-present", label: "Present", url: present, group: "workspace"),
        DiskUsageScanner.WatchedLocation(
            key: "ws-absent",
            label: "Absent",
            url: root.appendingPathComponent("absent", isDirectory: true),
            group: "workspace"
        )
    ])

    let presentReading = try #require(readings.first { $0.key == "ws-present" })
    #expect(presentReading.exists)
    #expect(presentReading.fileCount == 3)
    // Allocated size is block-rounded, so it is at least the logical bytes written.
    #expect(presentReading.byteCount >= 7_168)

    let absentReading = try #require(readings.first { $0.key == "ws-absent" })
    #expect(!absentReading.exists)
    #expect(absentReading.byteCount == 0)
    #expect(absentReading.fileCount == 0)
}

@Test
func diskUsageAttentionLightsOnPerLocationAndTotalThresholds() {
    func record(_ byteCounts: [Int64]) -> DiskUsageNoticeRecord {
        DiskUsageNoticeRecord(
            measuredAt: "2026-07-26T00:00:00.000Z",
            locations: byteCounts.enumerated().map { index, bytes in
                DiskUsageLocationReading(
                    key: "loc-\(index)",
                    label: "Location \(index)",
                    path: "/tmp/loc-\(index)",
                    group: "app",
                    byteCount: bytes,
                    fileCount: 1,
                    exists: true
                )
            }
        )
    }

    #expect(!evaluateDiskUsageAttention(record([1_000, 2_000]), perLocationBytes: 5_000, totalAttentionBytes: 15_000, rearmDeltaBytes: 2_000))
    #expect(evaluateDiskUsageAttention(record([6_000, 100]), perLocationBytes: 5_000, totalAttentionBytes: 15_000, rearmDeltaBytes: 2_000))
    #expect(evaluateDiskUsageAttention(record([4_000, 4_000, 4_000, 4_000]), perLocationBytes: 5_000, totalAttentionBytes: 15_000, rearmDeltaBytes: 2_000))
    #expect(!evaluateDiskUsageAttention(record([]), perLocationBytes: 5_000, totalAttentionBytes: 15_000, rearmDeltaBytes: 2_000))
}

@Test
func diskUsageAttentionRespectsAcknowledgmentAndRearm() {
    func evaluate(_ record: DiskUsageNoticeRecord) -> Bool {
        evaluateDiskUsageAttention(record, perLocationBytes: 5_000, totalAttentionBytes: 15_000, rearmDeltaBytes: 2_000)
    }

    var record = DiskUsageNoticeRecord(
        measuredAt: "2026-07-26T00:00:00.000Z",
        locations: [
            DiskUsageLocationReading(key: "big", label: "Big", path: "/tmp/big", group: "app", byteCount: 6_000, fileCount: 1, exists: true),
            DiskUsageLocationReading(key: "small", label: "Small", path: "/tmp/small", group: "app", byteCount: 100, fileCount: 1, exists: true)
        ]
    )

    // Over threshold with no acknowledgment: lit.
    #expect(evaluate(record))

    // Acknowledged at the current readings: quiet.
    record.acknowledgment = DiskUsageAcknowledgment(
        acknowledgedAt: "2026-07-26T00:00:01.000Z",
        acknowledgedTotalBytes: record.totalBytes,
        acknowledgedOverThresholdKeys: ["big"]
    )
    #expect(!evaluate(record))

    // Growth below the re-arm delta stays quiet (total 7_500, +1_400).
    record.locations[1].byteCount = 1_500
    #expect(!evaluate(record))

    // Growth at/above the delta re-lights (total 8_200, +2_100).
    record.locations[1].byteCount = 2_200
    #expect(evaluate(record))

    // A new location crossing the per-location threshold re-lights even when
    // the acknowledged total covers it.
    record.locations[1].byteCount = 5_500
    record.acknowledgment = DiskUsageAcknowledgment(
        acknowledgedAt: "2026-07-26T00:00:02.000Z",
        acknowledgedTotalBytes: record.totalBytes,
        acknowledgedOverThresholdKeys: ["big"]
    )
    #expect(evaluate(record))
    record.acknowledgment = DiskUsageAcknowledgment(
        acknowledgedAt: "2026-07-26T00:00:03.000Z",
        acknowledgedTotalBytes: record.totalBytes,
        acknowledgedOverThresholdKeys: ["big", "small"]
    )
    #expect(!evaluate(record))

    // Pruned back under every threshold: quiet regardless of stale acknowledgment.
    record.locations[0].byteCount = 1_000
    record.locations[1].byteCount = 100
    #expect(!evaluate(record))
}

@Test
func diskUsageWatchedLocationsResolveAppSupportAndWorkspaceBuckets() throws {
    let appSupportRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_notices_app_\(UUID().uuidString)", isDirectory: true)
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_notices_ws_\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: appSupportRoot)
        try? FileManager.default.removeItem(at: workspaceRoot)
    }
    try FileManager.default.createDirectory(
        at: appSupportRoot.appendingPathComponent("projects", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: workspaceRoot.appendingPathComponent("litscenes-output", isDirectory: true),
        withIntermediateDirectories: true
    )

    let both = DiskUsageScanner.watchedLocations(appSupportRoot: appSupportRoot, workspaceRoot: workspaceRoot)
    #expect(both.filter { $0.group == "app" }.map(\.key) == ["app-projects", "app-dev", "app-sref-style-references", "app-screen-graph-output"])
    #expect(both.filter { $0.group == "workspace" }.map(\.key) == ["ws-litscenes-output", "ws-media_sample", "ws-code-references", "ws-sounds", "ws-experiments"])

    let appOnly = DiskUsageScanner.watchedLocations(appSupportRoot: appSupportRoot, workspaceRoot: nil)
    #expect(appOnly.count == 4)
    #expect(appOnly.allSatisfy { $0.group == "app" })

    // The walk-up resolves the ancestor holding a bucket dir from a nested cwd.
    let nestedCwd = workspaceRoot.appendingPathComponent("apps/desktop/LitScenes", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedCwd, withIntermediateDirectories: true)
    #expect(DiskUsageScanner.defaultWorkspaceRoot(cwd: nestedCwd)?.path == workspaceRoot.standardizedFileURL.path)
}
