import Foundation

struct SREFReferenceCatalogPointer: Codable, Hashable, Sendable {
    var schemaVersion: String
    var catalogKind: String
    var catalogPath: String
    var catalogUrl: String
    var version: String

    var resolvedCatalogURL: URL? {
        URL(string: catalogUrl.trimmed)
    }
}

struct SREFReferenceCatalog: Codable, Hashable, Sendable {
    static let empty = SREFReferenceCatalog(
        schemaVersion: "",
        catalogKind: "",
        version: "",
        defaultGridVariant: "generated_1024",
        defaultDetailVariant: "generated_1024",
        defaultGenerationVariant: "generated_1024",
        styleCount: 0,
        generatedImageCount: 0,
        items: []
    )

    var schemaVersion: String
    var catalogKind: String
    var version: String
    var defaultGridVariant: String
    var defaultDetailVariant: String
    var defaultGenerationVariant: String
    var styleCount: Int
    var generatedImageCount: Int
    var items: [SREFReferenceCatalogItem]

    var isUsable: Bool {
        schemaVersion == "litscenes.sref_reference_catalog.v0.1" && !items.isEmpty
    }

    var displayItems: [SREFReferenceCatalogItem] {
        items.sorted { lhs, rhs in
            if lhs.pageValue != rhs.pageValue {
                return lhs.pageValue < rhs.pageValue
            }
            if lhs.cardIndexValue != rhs.cardIndexValue {
                return lhs.cardIndexValue < rhs.cardIndexValue
            }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }
}

struct SREFReferenceCatalogItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var srefCode: String
    var sourceKey: String
    var sourceId: String?
    var sourceSystem: String?
    var sourceUrl: String?
    var page: Int?
    var cardIndex: Int?
    var selectionRank: Int?
    var variants: [String: SREFReferenceImageVariant]

    var displayTitle: String {
        title.trimmed.isEmpty ? "SREF \(srefCode.trimmed)" : title.trimmed
    }

    var pageValue: Int {
        page ?? Int.max
    }

    var cardIndexValue: Int {
        cardIndex ?? Int.max
    }

    func preferredVariant(in catalog: SREFReferenceCatalog) -> (name: String, variant: SREFReferenceImageVariant)? {
        let candidateNames = uniqueNonEmpty([
            catalog.defaultGridVariant,
            catalog.defaultGenerationVariant,
            catalog.defaultDetailVariant,
            "generated_1024"
        ])
        for name in candidateNames {
            if let variant = variants[name] {
                return (name, variant)
            }
        }
        guard let first = variants.sorted(by: { $0.key < $1.key }).first else { return nil }
        return (first.key, first.value)
    }

    func styleImageReference(in catalog: SREFReferenceCatalog) -> SREFStyleImageReference? {
        guard let preferred = preferredVariant(in: catalog) else { return nil }
        return SREFStyleImageReference(
            catalogKind: catalog.catalogKind,
            catalogVersion: catalog.version,
            itemId: id,
            title: displayTitle,
            srefCode: srefCode.trimmed,
            sourceKey: sourceKey.trimmed,
            variantName: preferred.name,
            url: preferred.variant.url.trimmed,
            sha256: preferred.variant.sha256.trimmed.lowercased(),
            width: preferred.variant.width,
            height: preferred.variant.height,
            byteSize: preferred.variant.byteSize,
            mimeType: preferred.variant.mimeType.trimmed.isEmpty ? "image/png" : preferred.variant.mimeType.trimmed
        )
    }
}

struct SREFReferenceImageVariant: Codable, Hashable, Sendable {
    var url: String
    var path: String
    var sha256: String
    var width: Int
    var height: Int
    var byteSize: Int
    var mimeType: String
}

struct SREFStyleImageReference: Codable, Hashable, Identifiable, Sendable {
    static let sourceReferencePrefix = "sref-image-json:"

    var id: String { "\(catalogVersion)|\(itemId)|\(sha256)" }
    var catalogKind: String
    var catalogVersion: String
    var itemId: String
    var title: String
    var srefCode: String
    var sourceKey: String
    var variantName: String
    var url: String
    var sha256: String
    var width: Int
    var height: Int
    var byteSize: Int
    var mimeType: String

    var sourceReferenceId: String {
        guard let data = try? JSONCoding.encoder.encode(self) else {
            return "\(Self.sourceReferencePrefix)\(id)"
        }
        return Self.sourceReferencePrefix + data.base64EncodedString()
    }

    var filename: String {
        let ext = mimeType.lowercased().contains("jpeg") || mimeType.lowercased().contains("jpg") ? "jpg" : "png"
        return "\(safeIdentifier(catalogVersion))_\(safeIdentifier(itemId))_\(sha256.prefix(12)).\(ext)"
    }

    static func decodeSourceReferenceId(_ value: String) -> SREFStyleImageReference? {
        guard value.hasPrefix(sourceReferencePrefix) else { return nil }
        let encoded = String(value.dropFirst(sourceReferencePrefix.count))
        guard let data = Data(base64Encoded: encoded),
              let reference = try? JSONCoding.decoder.decode(SREFStyleImageReference.self, from: data) else {
            return nil
        }
        return reference.normalized()
    }

    func normalized() -> SREFStyleImageReference {
        var value = self
        value.catalogKind = value.catalogKind.trimmed
        value.catalogVersion = value.catalogVersion.trimmed
        value.itemId = value.itemId.trimmed
        value.title = value.title.trimmed
        value.srefCode = value.srefCode.trimmed
        value.sourceKey = value.sourceKey.trimmed
        value.variantName = value.variantName.trimmed.isEmpty ? "generated_1024" : value.variantName.trimmed
        value.url = value.url.trimmed
        value.sha256 = value.sha256.trimmed.lowercased()
        value.width = max(0, value.width)
        value.height = max(0, value.height)
        value.byteSize = max(0, value.byteSize)
        value.mimeType = value.mimeType.trimmed.isEmpty ? "image/png" : value.mimeType.trimmed
        return value
    }
}

actor SREFReferenceCatalogRuntime {
    static let shared = SREFReferenceCatalogRuntime()

    func loadCatalog(force: Bool = false) async throws -> SREFReferenceCatalog {
        try await CatalogManifestRuntime.shared.loadSnapshot(force: force).styleReference
    }
}

actor SREFReferenceImageCache {
    static let shared = SREFReferenceImageCache()

    private let rootURL = litScenesApplicationSupportDirectory()
        .appendingPathComponent("sref-style-references", isDirectory: true)

    func cachedFileURL(for reference: SREFStyleImageReference) async throws -> URL {
        let normalized = reference.normalized()
        guard let remoteURL = URL(string: normalized.url), !normalized.sha256.isEmpty else {
            throw ScreenGraphError.capture("SREF style reference is missing a valid URL or SHA-256.")
        }

        let outputURL = cacheURL(for: normalized)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let existingData = try Data(contentsOf: outputURL)
            if sha256Hex(existingData) == normalized.sha256 {
                return outputURL
            }
            try? FileManager.default.removeItem(at: outputURL)
        }

        try ensureDirectory(outputURL.deletingLastPathComponent())
        let startedAt = Date()
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("SREF style image download failed.")
        }
        guard sha256Hex(data) == normalized.sha256 else {
            throw ScreenGraphError.capture("SREF style image SHA-256 verification failed.")
        }
        try data.write(to: outputURL, options: [.atomic])
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        print("[sref_reference_cache] completed item_id=\(normalized.itemId) bytes=\(data.count) duration_ms=\(durationMs)")
        return outputURL
    }

    private func cacheURL(for reference: SREFStyleImageReference) -> URL {
        rootURL
            .appendingPathComponent(safeIdentifier(reference.catalogVersion), isDirectory: true)
            .appendingPathComponent(reference.filename)
    }
}

extension LensStyleIngredient {
    static func srefStyleReference(
        _ reference: SREFStyleImageReference,
        order: Int,
        now: String = DateFormats.now()
    ) -> LensStyleIngredient {
        let normalized = reference.normalized()
        return LensStyleIngredient(
            ingredientId: "ingredient_\(shortHash("\(normalized.id):\(order):\(now)", length: 12))",
            order: order,
            enabled: true,
            title: normalized.title.isEmpty ? "SREF style reference" : normalized.title,
            role: "style_reference",
            narrativeUse: "Use this generated SREF composite as a visual style anchor for Lens image generation.",
            presentationUse: uniqueNonEmpty(["SREF \(normalized.srefCode)", normalized.variantName]).joined(separator: " · "),
            notes: normalized.url,
            paletteTerms: [],
            motifTerms: [],
            avoidTerms: [],
            referenceAestheticIds: [],
            sourceRecipeId: nil,
            sourceRecipeVersion: normalized.catalogVersion,
            sourceReferenceIds: [normalized.sourceReferenceId],
            updatedAt: now
        )
    }
}
