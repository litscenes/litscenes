import Foundation

struct CatalogManifestFile: Codable, Hashable, Sendable {
    var kind: String
    var path: String
    var url: String
    var sha256: String
    var byteSize: Int

    var resolvedURL: URL? { URL(string: url.trimmed) }
}

struct CatalogManifestCompatibility: Codable, Hashable, Sendable {
    var minimumDesktopVersion: String
    var clientFamilies: [String]
}

struct CatalogManifest: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.catalog_manifest.v1"
    static let liveURL = URL(string: "https://catalog.litscenes.ai/v1/manifest.json")!

    var schemaVersion: String
    var manifestVersion: String
    var publishedAt: String
    var termsSha256: String
    var terms: CatalogManifestFile
    var catalogs: [CatalogManifestFile]
    var compatibility: CatalogManifestCompatibility

    func catalog(kind: String) -> CatalogManifestFile? {
        catalogs.first { $0.kind == kind }
    }
}

enum CatalogSnapshotOrigin: String, Codable, Sendable {
    case live
    case cached
    case bundled
}

/// Whether the app may fetch the live style catalog on its own. Off by
/// default: an unconfigured install makes no network requests at all — the
/// bundled starter catalog serves until the user turns the live catalog on or
/// explicitly refreshes (an explicit refresh always goes live; the user asked).
enum CatalogFetchPolicy {
    static let preferenceKey = "LITSCENES_LIVE_CATALOG"

    static func liveCatalogEnabled() -> Bool {
        let raw = LitScenesCredentialStore()
            .resolvedCredentialValue(forKey: preferenceKey)
            .trimmed
            .lowercased()
        guard !raw.isEmpty else { return false }
        return !["0", "false", "no", "off"].contains(raw)
    }
}

struct CatalogRuntimeSnapshot: Sendable {
    var manifest: CatalogManifest
    var styleBrowse: StyleBrowseCatalog
    var styleReference: SREFReferenceCatalog
    var terms: String
    var origin: CatalogSnapshotOrigin
    var warning: String
}

private struct CatalogRawSnapshot: Sendable {
    var manifestData: Data
    var termsData: Data
    var styleBrowseData: Data
    var styleReferenceData: Data
}

private struct CatalogSnapshotPointer: Codable, Sendable {
    var activeVersion: String
    var previousVersion: String?
    var activatedAt: String
}

enum CatalogPayloadIntegrity {
    static func matches(_ data: Data, sha256 expectedSHA256: String, byteSize: Int) -> Bool {
        data.count == byteSize && sha256Hex(data) == expectedSHA256.trimmed.lowercased()
    }
}

actor CatalogManifestRuntime {
    static let shared = CatalogManifestRuntime()

    private static let manifestMaximumBytes = 256 * 1024
    private static let payloadMaximumBytes = 12 * 1024 * 1024

    private let session: URLSession
    private let rootURL: URL
    private var cachedSnapshot: CatalogRuntimeSnapshot?

    init(
        session: URLSession = .shared,
        rootURL: URL = litScenesApplicationSupportDirectory()
            .appendingPathComponent("catalog", isDirectory: true)
    ) {
        self.session = session
        self.rootURL = rootURL
    }

    func loadSnapshot(force: Bool = false) async throws -> CatalogRuntimeSnapshot {
        if !force, let cachedSnapshot {
            return cachedSnapshot
        }

        // Bundled-first when the live catalog is off: serve the last known
        // good snapshot or the bundled starter without touching the network. A
        // forced load is the explicit user refresh and always goes live.
        if !force, !CatalogFetchPolicy.liveCatalogEnabled() {
            if let stored = try? loadStoredSnapshot() {
                var snapshot = stored
                snapshot.warning = "Live style catalog is off; using the last saved catalog. Refresh to fetch the current set from catalog.litscenes.ai."
                cachedSnapshot = snapshot
                return snapshot
            }
            let raw = try loadBundledRawSnapshot()
            let snapshot = try decodeAndVerify(
                raw,
                origin: .bundled,
                warning: "Using the bundled starter catalog. Turn on the live catalog in Settings, or Refresh, to fetch the full style set from catalog.litscenes.ai."
            )
            try? persist(raw: raw, manifest: snapshot.manifest)
            cachedSnapshot = snapshot
            return snapshot
        }

        do {
            let raw = try await fetchLiveSnapshot()
            let snapshot = try decodeAndVerify(raw, origin: .live, warning: "")
            try persist(raw: raw, manifest: snapshot.manifest)
            cachedSnapshot = snapshot
            return snapshot
        } catch {
            let liveError = error.localizedDescription
            if let cached = try? loadStoredSnapshot() {
                var fallback = cached
                fallback.warning = "Catalog refresh failed; using the last-known-good catalog. \(liveError)"
                cachedSnapshot = fallback
                return fallback
            }
            if var memory = cachedSnapshot {
                memory.warning = "Catalog refresh failed; keeping the active catalog. \(liveError)"
                cachedSnapshot = memory
                return memory
            }
            do {
                let raw = try loadBundledRawSnapshot()
                let snapshot = try decodeAndVerify(
                    raw,
                    origin: .bundled,
                    warning: "The live catalog is unavailable; using bundled verified metadata. Uncached image previews still require catalog access. \(liveError)"
                )
                try? persist(raw: raw, manifest: snapshot.manifest)
                cachedSnapshot = snapshot
                return snapshot
            } catch {
                throw ScreenGraphError.capture(
                    "No verified style catalog is available. Live error: \(liveError) Bundled error: \(error.localizedDescription)"
                )
            }
        }
    }

    func currentWarning() -> String {
        cachedSnapshot?.warning ?? ""
    }

    func currentTermsURL() -> URL {
        cachedSnapshot?.manifest.terms.resolvedURL ?? LitScenesReleaseIdentity.catalogTermsURL
    }

    private func fetchLiveSnapshot() async throws -> CatalogRawSnapshot {
        print("[catalog_manifest] starting url=\(CatalogManifest.liveURL.absoluteString)")
        let startedAt = Date()
        do {
            let manifestData = try await fetch(
                CatalogManifest.liveURL,
                label: "Catalog manifest",
                maximumBytes: Self.manifestMaximumBytes
            )
            let manifest = try JSONCoding.decoder.decode(CatalogManifest.self, from: manifestData)
            try validateManifest(manifest)
            guard let styleBrowse = manifest.catalog(kind: "style_browse"),
                  let styleReference = manifest.catalog(kind: "style_reference") else {
                throw ScreenGraphError.capture("Catalog manifest is missing required catalogs.")
            }
            let termsData = try await fetchManifestFile(manifest.terms)
            let styleBrowseData = try await fetchManifestFile(styleBrowse)
            let styleReferenceData = try await fetchManifestFile(styleReference)
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[catalog_manifest] completed version=\(manifest.manifestVersion) duration_ms=\(durationMs) status_code=200")
            return CatalogRawSnapshot(
                manifestData: manifestData,
                termsData: termsData,
                styleBrowseData: styleBrowseData,
                styleReferenceData: styleReferenceData
            )
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[catalog_manifest] error duration_ms=\(durationMs) status_code=0 error=\(error.localizedDescription)")
            throw error
        }
    }

    private func fetchManifestFile(_ file: CatalogManifestFile) async throws -> Data {
        guard let url = file.resolvedURL else {
            throw ScreenGraphError.capture("Catalog manifest has an invalid \(file.kind) URL.")
        }
        return try await fetch(url, label: file.kind, maximumBytes: Self.payloadMaximumBytes)
    }

    private func fetch(_ url: URL, label: String, maximumBytes: Int) async throws -> Data {
        guard url.scheme == "https",
              url.host == "catalog.litscenes.ai",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil else {
            throw ScreenGraphError.capture("\(label) must use the catalog.litscenes.ai HTTPS boundary.")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("\(label) request failed.")
        }
        guard data.count <= maximumBytes else {
            throw ScreenGraphError.capture("\(label) exceeded its maximum safe size.")
        }
        return data
    }

    private func decodeAndVerify(
        _ raw: CatalogRawSnapshot,
        origin: CatalogSnapshotOrigin,
        warning: String
    ) throws -> CatalogRuntimeSnapshot {
        let manifest = try JSONCoding.decoder.decode(CatalogManifest.self, from: raw.manifestData)
        try validateManifest(manifest)
        guard let browseEntry = manifest.catalog(kind: "style_browse"),
              let referenceEntry = manifest.catalog(kind: "style_reference") else {
            throw ScreenGraphError.capture("Catalog manifest is missing required catalogs.")
        }
        try verify(raw.termsData, against: manifest.terms)
        try verify(raw.styleBrowseData, against: browseEntry)
        try verify(raw.styleReferenceData, against: referenceEntry)

        guard manifest.termsSha256.lowercased() == manifest.terms.sha256.lowercased() else {
            throw ScreenGraphError.capture("Catalog terms hash does not match the manifest terms entry.")
        }
        guard let terms = String(data: raw.termsData, encoding: .utf8) else {
            throw ScreenGraphError.capture("Catalog terms are not valid UTF-8.")
        }
        let styleBrowse = try JSONCoding.decoder.decode(StyleBrowseCatalog.self, from: raw.styleBrowseData)
        let styleReference = try JSONCoding.decoder.decode(SREFReferenceCatalog.self, from: raw.styleReferenceData)
        guard styleBrowse.isUsable, styleReference.isUsable else {
            throw ScreenGraphError.capture("Catalog payload decoded but is not usable.")
        }
        return CatalogRuntimeSnapshot(
            manifest: manifest,
            styleBrowse: styleBrowse,
            styleReference: styleReference,
            terms: terms,
            origin: origin,
            warning: warning
        )
    }

    func validateManifest(_ manifest: CatalogManifest) throws {
        guard manifest.schemaVersion == CatalogManifest.schemaVersion,
              !manifest.manifestVersion.trimmed.isEmpty,
              !manifest.publishedAt.trimmed.isEmpty,
              manifest.terms.kind == "terms",
              manifest.catalogs.count == 2,
              Set(manifest.catalogs.map(\.kind)) == Set(["style_browse", "style_reference"]) else {
            throw ScreenGraphError.capture("Catalog manifest contract is invalid.")
        }
        let entries = [manifest.terms] + manifest.catalogs
        guard Set(entries.map(\.kind)).count == entries.count,
              Set(entries.map(\.path)).count == entries.count else {
            throw ScreenGraphError.capture("Catalog manifest contains duplicate kinds or paths.")
        }
        for entry in entries {
            let pathParts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.kind.trimmed.isEmpty,
                  !entry.path.trimmed.isEmpty,
                  entry.path == entry.path.trimmed,
                  !entry.path.hasPrefix("/"),
                  !entry.path.hasSuffix("/"),
                  pathParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  entry.sha256.count == 64,
                  entry.sha256.allSatisfy({ $0.isHexDigit }),
                  entry.sha256 == entry.sha256.lowercased(),
                  entry.byteSize > 0,
                  entry.byteSize <= Self.payloadMaximumBytes,
                  let url = entry.resolvedURL,
                  url.scheme == "https",
                  url.host == "catalog.litscenes.ai",
                  url.user == nil,
                  url.password == nil,
                  url.port == nil,
                  url.query == nil,
                  url.fragment == nil,
                  url.path == "/\(entry.path)" else {
                throw ScreenGraphError.capture("Catalog manifest entry \(entry.kind) is invalid.")
            }
        }
    }

    private func verify(_ data: Data, against entry: CatalogManifestFile) throws {
        guard CatalogPayloadIntegrity.matches(data, sha256: entry.sha256, byteSize: entry.byteSize) else {
            throw ScreenGraphError.capture("Catalog \(entry.kind) integrity verification failed.")
        }
    }

    private func persist(raw: CatalogRawSnapshot, manifest: CatalogManifest) throws {
        let snapshotsURL = rootURL.appendingPathComponent("snapshots", isDirectory: true)
        let versionURL = snapshotsURL.appendingPathComponent(safeIdentifier(manifest.manifestVersion), isDirectory: true)
        try ensureDirectory(versionURL)
        try raw.manifestData.write(to: versionURL.appendingPathComponent("manifest.json"), options: [.atomic])
        try raw.termsData.write(to: versionURL.appendingPathComponent("terms.md"), options: [.atomic])
        try raw.styleBrowseData.write(to: versionURL.appendingPathComponent("style-browse.json"), options: [.atomic])
        try raw.styleReferenceData.write(to: versionURL.appendingPathComponent("style-reference.json"), options: [.atomic])

        let pointerURL = rootURL.appendingPathComponent("active.json")
        let existing = try? JSONCoding.decoder.decode(CatalogSnapshotPointer.self, from: Data(contentsOf: pointerURL))
        let pointer = CatalogSnapshotPointer(
            activeVersion: manifest.manifestVersion,
            previousVersion: existing?.activeVersion == manifest.manifestVersion
                ? existing?.previousVersion
                : existing?.activeVersion,
            activatedAt: DateFormats.now()
        )
        try ensureDirectory(rootURL)
        try JSONCoding.encoder.encode(pointer).write(to: pointerURL, options: [.atomic])
    }

    private func loadStoredSnapshot() throws -> CatalogRuntimeSnapshot {
        let pointerURL = rootURL.appendingPathComponent("active.json")
        let pointer = try JSONCoding.decoder.decode(CatalogSnapshotPointer.self, from: Data(contentsOf: pointerURL))
        let versions = uniqueNonEmpty([pointer.activeVersion, pointer.previousVersion ?? ""])
        var lastError: Error?
        for version in versions {
            do {
                let raw = try loadRawSnapshot(
                    from: rootURL
                        .appendingPathComponent("snapshots", isDirectory: true)
                        .appendingPathComponent(safeIdentifier(version), isDirectory: true)
                )
                return try decodeAndVerify(raw, origin: .cached, warning: "")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ScreenGraphError.capture("Catalog cache pointer has no usable snapshot.")
    }

    private func loadBundledRawSnapshot() throws -> CatalogRawSnapshot {
        guard let directory = Bundle.module.url(forResource: "CatalogFallback", withExtension: nil) else {
            throw ScreenGraphError.capture("Bundled catalog directory is missing.")
        }
        return try loadRawSnapshot(from: directory, bundled: true)
    }

    private func loadRawSnapshot(from directory: URL, bundled: Bool = false) throws -> CatalogRawSnapshot {
        CatalogRawSnapshot(
            manifestData: try Data(contentsOf: directory.appendingPathComponent("manifest.json")),
            termsData: try Data(contentsOf: directory.appendingPathComponent(bundled ? "CATALOG_TERMS.md" : "terms.md")),
            styleBrowseData: try Data(contentsOf: directory.appendingPathComponent("style-browse.json")),
            styleReferenceData: try Data(contentsOf: directory.appendingPathComponent("style-reference.json"))
        )
    }
}
