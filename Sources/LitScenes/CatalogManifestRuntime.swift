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

enum CatalogPayloadIntegrity {
    static func matches(_ data: Data, sha256 expectedSHA256: String, byteSize: Int) -> Bool {
        data.count == byteSize && sha256Hex(data) == expectedSHA256.trimmed.lowercased()
    }
}

actor CatalogManifestRuntime {
    static let shared = CatalogManifestRuntime()

    private static let payloadMaximumBytes = 12 * 1024 * 1024

    private var cachedSnapshot: CatalogRuntimeSnapshot?

    // Parameters remain source-compatible for offline verification clients.
    init(session: URLSession = .shared, rootURL: URL = litScenesApplicationSupportDirectory()) {}

    func loadSnapshot(force: Bool = false) async throws -> CatalogRuntimeSnapshot {
        if !force, let cachedSnapshot { return cachedSnapshot }
        let snapshot = try decodeAndVerify(loadBundledRawSnapshot(), origin: .bundled, warning: "")
        cachedSnapshot = snapshot
        return snapshot
    }

    func currentWarning() -> String {
        cachedSnapshot?.warning ?? ""
    }

    func currentTermsURL() -> URL { LitScenesReleaseIdentity.catalogTermsURL }

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
                  url.scheme == "litscenes-bundle",
                  url.host == "catalog",
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

    private func loadBundledRawSnapshot() throws -> CatalogRawSnapshot {
        let directory = try packagedResourceURL(named: "CatalogFallback")
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
