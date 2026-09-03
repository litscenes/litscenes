import Foundation

// MARK: - Tunables

/// Thresholds confirmed in tuning: the badge dot lights at
/// ≥5 GB for any single watched location or ≥15 GB across all of them, and —
/// once acknowledged — re-lights only after +2 GB of growth beyond the
/// acknowledged total or a new location crossing the per-location line.
/// Cadence is launch + manual refresh; there is deliberately no timer.
enum DiskUsageNoticeTunables {
    static let perLocationAttentionBytes: Int64 = 5_000_000_000
    static let totalAttentionBytes: Int64 = 15_000_000_000
    static let rearmDeltaBytes: Int64 = 2_000_000_000
}

// MARK: - Documents

/// One watched directory with its most recent measurement. Identity and
/// reading travel together so persisted state stays one flat tolerant list.
struct DiskUsageLocationReading: Codable, Hashable, Sendable, Identifiable {
    var key: String
    var label: String
    var path: String
    /// "app" = Application Support bucket, "workspace" = repo-root dev dir.
    var group: String
    var byteCount: Int64
    var fileCount: Int
    var exists: Bool

    var id: String { key }

    init(
        key: String = "",
        label: String = "",
        path: String = "",
        group: String = "app",
        byteCount: Int64 = 0,
        fileCount: Int = 0,
        exists: Bool = false
    ) {
        self.key = key
        self.label = label
        self.path = path
        self.group = group
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.exists = exists
    }

    enum CodingKeys: CodingKey {
        case key, label, path, group, byteCount, fileCount, exists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? "app"
        byteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount) ?? 0
        fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount) ?? 0
        exists = try container.decodeIfPresent(Bool.self, forKey: .exists) ?? false
    }
}

struct DiskUsageAcknowledgment: Codable, Hashable, Sendable {
    var acknowledgedAt: String
    var acknowledgedTotalBytes: Int64
    /// Keys that were over the per-location threshold when acknowledged; a new
    /// key crossing later re-lights the badge even without total growth.
    var acknowledgedOverThresholdKeys: [String]

    init(
        acknowledgedAt: String = "",
        acknowledgedTotalBytes: Int64 = 0,
        acknowledgedOverThresholdKeys: [String] = []
    ) {
        self.acknowledgedAt = acknowledgedAt
        self.acknowledgedTotalBytes = acknowledgedTotalBytes
        self.acknowledgedOverThresholdKeys = acknowledgedOverThresholdKeys
    }

    enum CodingKeys: CodingKey {
        case acknowledgedAt, acknowledgedTotalBytes, acknowledgedOverThresholdKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        acknowledgedAt = try container.decodeIfPresent(String.self, forKey: .acknowledgedAt) ?? ""
        acknowledgedTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .acknowledgedTotalBytes) ?? 0
        acknowledgedOverThresholdKeys = try container.decodeIfPresent([String].self, forKey: .acknowledgedOverThresholdKeys) ?? []
    }
}

struct DiskUsageNoticeRecord: Codable, Hashable, Sendable {
    var measuredAt: String
    var locations: [DiskUsageLocationReading]
    var acknowledgment: DiskUsageAcknowledgment?

    static let empty = DiskUsageNoticeRecord()

    var totalBytes: Int64 {
        locations.reduce(0) { $0 + $1.byteCount }
    }

    init(
        measuredAt: String = "",
        locations: [DiskUsageLocationReading] = [],
        acknowledgment: DiskUsageAcknowledgment? = nil
    ) {
        self.measuredAt = measuredAt
        self.locations = locations
        self.acknowledgment = acknowledgment
    }

    enum CodingKeys: CodingKey {
        case measuredAt, locations, acknowledgment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        measuredAt = try container.decodeIfPresent(String.self, forKey: .measuredAt) ?? ""
        locations = try container.decodeIfPresent([DiskUsageLocationReading].self, forKey: .locations) ?? []
        acknowledgment = try container.decodeIfPresent(DiskUsageAcknowledgment.self, forKey: .acknowledgment)
        self = normalized()
    }

    func normalized() -> DiskUsageNoticeRecord {
        var copy = self
        var seenKeys = Set<String>()
        copy.locations = locations.filter { !$0.key.isEmpty && seenKeys.insert($0.key).inserted }
        return copy
    }
}

/// The app-level notices document — persisted as `notices.json` beside
/// `credentials.env`, not in any project database.
struct AppNoticesStateDocument: Codable, Hashable, Sendable {
    var schemaVersion: String
    var diskUsage: DiskUsageNoticeRecord

    static let empty = AppNoticesStateDocument()

    init(
        schemaVersion: String = "litscenes.app_notices.v1",
        diskUsage: DiskUsageNoticeRecord = .empty
    ) {
        self.schemaVersion = schemaVersion
        self.diskUsage = diskUsage
    }

    enum CodingKeys: CodingKey {
        case schemaVersion, diskUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.app_notices.v1"
        diskUsage = try container.decodeIfPresent(DiskUsageNoticeRecord.self, forKey: .diskUsage) ?? .empty
    }
}

// MARK: - Attention

/// Keys of locations at/above the per-location threshold.
func diskUsageOverThresholdKeys(
    _ record: DiskUsageNoticeRecord,
    perLocationBytes: Int64 = DiskUsageNoticeTunables.perLocationAttentionBytes
) -> [String] {
    record.locations.filter { $0.byteCount >= perLocationBytes }.map(\.key)
}

/// Whether the badge dot shows. Named `evaluate…` so the engine's computed
/// `diskUsageNeedsAttention` can call it without shadowing itself.
func evaluateDiskUsageAttention(
    _ record: DiskUsageNoticeRecord,
    perLocationBytes: Int64 = DiskUsageNoticeTunables.perLocationAttentionBytes,
    totalAttentionBytes: Int64 = DiskUsageNoticeTunables.totalAttentionBytes,
    rearmDeltaBytes: Int64 = DiskUsageNoticeTunables.rearmDeltaBytes
) -> Bool {
    let overKeys = diskUsageOverThresholdKeys(record, perLocationBytes: perLocationBytes)
    let total = record.totalBytes
    guard !overKeys.isEmpty || total >= totalAttentionBytes else { return false }
    guard let acknowledgment = record.acknowledgment else { return true }
    if total >= acknowledgment.acknowledgedTotalBytes + rearmDeltaBytes { return true }
    let acknowledgedKeys = Set(acknowledgment.acknowledgedOverThresholdKeys)
    return overKeys.contains { !acknowledgedKeys.contains($0) }
}

// MARK: - Store

/// Flat tolerant JSON under the active release identity's Application Support
/// root — loads
/// never throw (missing/corrupt reads as `.empty`), saves do.
struct AppNoticesStore {
    var root: URL = litScenesApplicationSupportDirectory()

    var fileURL: URL {
        root.appendingPathComponent("notices.json")
    }

    func load() -> AppNoticesStateDocument {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONCoding.decoder.decode(AppNoticesStateDocument.self, from: data) else {
            return .empty
        }
        return document
    }

    func save(_ document: AppNoticesStateDocument) throws {
        try ensureDirectory(root)
        let data = try JSONCoding.prettyEncoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - Scanner

/// Resolves and measures the watched generated-output locations. Pure
/// filesystem reads; the engine runs these inside a detached utility task.
enum DiskUsageScanner {
    struct WatchedLocation: Hashable, Sendable {
        var key: String
        var label: String
        var url: URL
        var group: String
    }

    /// Buckets under the active release identity's Application Support root.
    static let appSupportBucketNames: [(dir: String, label: String)] = [
        ("projects", "Projects"),
        ("dev", "Dev traces"),
        ("sref-style-references", "Style references"),
        ("screen-graph-output", "Screen graph output")
    ]

    /// Dev-workspace dirs at a development checkout root — written by
    /// external tooling rather than the app itself, which is exactly why
    /// their disk usage goes unnoticed without this scan.
    static let workspaceBucketNames: [(dir: String, label: String)] = [
        ("litscenes-output", "Python output"),
        ("media_sample", "Media samples"),
        ("code-references", "Code references"),
        ("sounds", "Sounds"),
        ("experiments", "Experiments")
    ]

    /// LITSCENES_WORKSPACE_DIR (process env or the .env chain, incl.
    /// ~/.litscenes.env for packaged builds) wins; otherwise walk ≤8 parents
    /// from cwd accepting the first ancestor holding at least one workspace
    /// bucket. nil (e.g. packaged app with cwd "/") hides the workspace group.
    static func defaultWorkspaceRoot(
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> URL? {
        if let configured = environmentValue("LITSCENES_WORKSPACE_DIR")?.trimmed, !configured.isEmpty {
            let url = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
            if directoryExists(url) {
                return url
            }
        }
        // The parent-walk sniff only makes sense inside a development
        // checkout; packaged public builds have no workspace to find.
        guard LitScenesReleaseIdentity.current.channel == .development else { return nil }
        var cursor = cwd.standardizedFileURL
        for _ in 0..<8 {
            let holdsBucket = workspaceBucketNames.contains { bucket in
                directoryExists(cursor.appendingPathComponent(bucket.dir, isDirectory: true))
            }
            if holdsBucket {
                return cursor
            }
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { break }
            cursor = parent
        }
        return nil
    }

    static func watchedLocations(
        appSupportRoot: URL = litScenesApplicationSupportDirectory(),
        workspaceRoot: URL?
    ) -> [WatchedLocation] {
        var locations = appSupportBucketNames.map { bucket in
            WatchedLocation(
                key: "app-\(bucket.dir)",
                label: bucket.label,
                url: appSupportRoot.appendingPathComponent(bucket.dir, isDirectory: true),
                group: "app"
            )
        }
        if let workspaceRoot {
            locations += workspaceBucketNames.map { bucket in
                WatchedLocation(
                    key: "ws-\(bucket.dir)",
                    label: bucket.label,
                    url: workspaceRoot.appendingPathComponent(bucket.dir, isDirectory: true),
                    group: "workspace"
                )
            }
        }
        return locations
    }

    static func measure(_ locations: [WatchedLocation]) -> [DiskUsageLocationReading] {
        locations.map(measureLocation)
    }

    private static func measureLocation(_ location: WatchedLocation) -> DiskUsageLocationReading {
        var reading = DiskUsageLocationReading(
            key: location.key,
            label: location.label,
            path: location.url.standardizedFileURL.path,
            group: location.group
        )
        guard directoryExists(location.url) else { return reading }
        reading.exists = true

        // Hidden files stay in (code-references is mostly .git objects) and
        // the sum is allocated size, so readings track what du/Finder report.
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: location.url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return reading
        }

        let keySet = Set(keys)
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keySet),
                  values.isRegularFile == true else { continue }
            let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            reading.byteCount += Int64(bytes)
            reading.fileCount += 1
        }
        return reading
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
