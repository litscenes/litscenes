import Foundation
import SQLite3

/// Per-project growth instrument.
///
/// A long-lived project gets slow for structural reasons, not mysterious ones:
/// every render adds a take row that is never pruned, and every lens version
/// stores a whole serialized body. Measured on a reference machine — 1.0 GB on
/// disk, a 27 MB database, 980 hero-image rows across 42 frames (23.3 takes per
/// frame), and 35 lens-version rows averaging 320 KB each.
///
/// This exists so the next optimization is aimed rather than guessed. It
/// reports what actually grows; it never deletes or archives anything.

/// One measured table. `byteCount` comes from SQLite's `dbstat` virtual table
/// when the build provides it, and is -1 when unavailable — reported honestly
/// as unknown rather than silently as zero.
struct ProjectVitalsTableReading: Hashable, Sendable, Identifiable {
    var table: String
    var rowCount: Int
    var byteCount: Int64

    var id: String { table }
    var hasByteCount: Bool { byteCount >= 0 }
}

struct ProjectVitals: Hashable, Sendable {
    var projectId: String = ""
    var projectName: String = ""
    var storyBytes: Int64 = 0
    var libraryBytes: Int64 = 0
    var databaseBytes: Int64 = 0
    /// Tables that grow with use, biggest first.
    var tables: [ProjectVitalsTableReading] = []
    var heroImageCount: Int = 0
    var heroImageFrameCount: Int = 0
    var registryRowCount: Int = 0
    /// Registry rows whose project directory no longer exists — broken picker
    /// entries. Non-zero means the registry is carrying dead weight.
    var registryDeadRowCount: Int = 0
    var measuredAt: String = ""

    var totalBytes: Int64 { storyBytes + libraryBytes + databaseBytes }

    /// Average take-stack depth. The number that says how much a project has
    /// accumulated per frame — the working set no cold tier bounds yet.
    var takesPerFrame: Double {
        guard heroImageFrameCount > 0 else { return 0 }
        return Double(heroImageCount) / Double(heroImageFrameCount)
    }

    /// Human-readable lines, biggest signal first. Kept here (not in a view) so
    /// the wording is testable and reusable from a log dump.
    var summaryLines: [String] {
        var lines = [
            "\(projectName): \(ProjectVitals.formatted(totalBytes)) on disk",
            "  story \(ProjectVitals.formatted(storyBytes)) · library \(ProjectVitals.formatted(libraryBytes)) · database \(ProjectVitals.formatted(databaseBytes))"
        ]
        if heroImageFrameCount > 0 {
            lines.append("  \(heroImageCount) takes across \(heroImageFrameCount) frames (\(String(format: "%.1f", takesPerFrame)) per frame)")
        }
        for table in tables.prefix(4) {
            let size = table.hasByteCount ? " · \(ProjectVitals.formatted(table.byteCount))" : ""
            lines.append("  \(table.table): \(table.rowCount) rows\(size)")
        }
        if registryRowCount > 0 {
            let dead = registryDeadRowCount > 0 ? " (\(registryDeadRowCount) dead)" : ""
            lines.append("  registry: \(registryRowCount) projects\(dead)")
        }
        return lines
    }

    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}

enum ProjectVitalsProbe {
    /// Tables worth watching: the ones that grow with normal use. Anything not
    /// listed either has a bounded size or is derived.
    static let watchedTables = [
        "project_lens_hero_images",
        "project_lens_version_lenses",
        "project_documents",
        "media_items",
        "project_lens_terms",
        "media_observation_terms"
    ]

    /// Walks the project directory and reads row counts from its database.
    /// Never mutates: the database is opened read-only and a failure to read
    /// any single table leaves that reading out rather than failing the probe.
    static func measure(
        project: ProjectRecord,
        projectLibrary: ProjectLibrary,
        registryRowCount: Int = 0,
        registryDeadRowCount: Int = 0
    ) -> ProjectVitals {
        var vitals = ProjectVitals(
            projectId: project.projectId,
            projectName: project.name,
            registryRowCount: registryRowCount,
            registryDeadRowCount: registryDeadRowCount,
            measuredAt: DateFormats.now()
        )
        let directory = projectLibrary.projectDirectory(for: project)
        let readings = DiskUsageScanner.measure([
            DiskUsageScanner.WatchedLocation(
                key: "story",
                label: "Story",
                url: directory.appendingPathComponent("story", isDirectory: true),
                group: "project"
            ),
            DiskUsageScanner.WatchedLocation(
                key: "library",
                label: "Library",
                url: directory.appendingPathComponent("library", isDirectory: true),
                group: "project"
            )
        ])
        vitals.storyBytes = readings.first { $0.key == "story" }?.byteCount ?? 0
        vitals.libraryBytes = readings.first { $0.key == "library" }?.byteCount ?? 0

        let databaseURL = directory.appendingPathComponent("LitScenes.db")
        vitals.databaseBytes = fileByteCount(databaseURL)
        if let database = ProjectVitalsReadOnlyDatabase(url: databaseURL) {
            vitals.tables = watchedTables.compactMap { table in
                guard let rows = database.rowCount(table: table) else { return nil }
                return ProjectVitalsTableReading(
                    table: table,
                    rowCount: rows,
                    byteCount: database.byteCount(table: table) ?? -1
                )
            }
            .sorted {
                // Byte size when known, row count otherwise — biggest first.
                ($0.hasByteCount ? $0.byteCount : Int64($0.rowCount)) >
                ($1.hasByteCount ? $1.byteCount : Int64($1.rowCount))
            }
            vitals.heroImageCount = database.rowCount(table: "project_lens_hero_images") ?? 0
            vitals.heroImageFrameCount = database.distinctCount(
                table: "project_lens_hero_images",
                column: "render_target_id"
            ) ?? 0
        }
        return vitals
    }

    static func fileByteCount(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        let bytes = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0
        return Int64(bytes)
    }
}

/// Minimal read-only reader for the vitals probe. Deliberately separate from
/// `LitScenesDesktopDatabase`: measuring must never migrate a schema, register
/// a project, or create a file, and opening READONLY (without CREATE) is what
/// guarantees that even if the path is wrong.
final class ProjectVitalsReadOnlyDatabase {
    private let connection: OpaquePointer

    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        connection = handle
    }

    deinit { sqlite3_close(connection) }

    func rowCount(table: String) -> Int? {
        guard isSafeIdentifier(table), tableExists(table) else { return nil }
        return scalar("SELECT COUNT(*) FROM \"\(table)\";")
    }

    func distinctCount(table: String, column: String) -> Int? {
        guard isSafeIdentifier(table), isSafeIdentifier(column), tableExists(table) else { return nil }
        return scalar("SELECT COUNT(DISTINCT \"\(column)\") FROM \"\(table)\";")
    }

    /// Page bytes from `dbstat`, which is a compile-time-optional virtual
    /// table; nil when this SQLite build lacks it.
    func byteCount(table: String) -> Int64? {
        guard isSafeIdentifier(table) else { return nil }
        guard let kb = scalar("SELECT SUM(pgsize) FROM dbstat WHERE name='\(table)';") else { return nil }
        return Int64(kb)
    }

    private func tableExists(_ table: String) -> Bool {
        (scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='\(table)';") ?? 0) > 0
    }

    private func scalar(_ sql: String) -> Int? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Table and column names are interpolated (SQLite cannot bind
    /// identifiers), so they must come from a known-safe alphabet. The current
    /// callers pass compile-time constants; this keeps that true if a future
    /// caller passes something dynamic.
    private func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
