import Foundation

struct StyleBrowseCollection: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var name: String
    var description: String
    var dotColorHex: String
    var sortOrder: Int

    var id: String { key }
}

struct StyleBrowseStyle: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var label: String
    var caption: String
    /// Render-oriented one-line summary from the style reference analysis
    /// (one_line_style_summary); optional so catalogs published before the field
    /// existed still decode.
    var oneLineStyleSummary: String?
    var url: String
    var sha256: String?
    var width: Int?
    var height: Int?
    var collection: String
    var secondaryCollection: String?
    var moods: [String]
    var hueName: String
    var hueHex: String
    var medium: String
    var sat: Int
    var con: Int
    var ser: Int
    var lin: Int
    var sty: Int
    var srefCode: String
    var page: Int
    var cardIndex: Int

    var displayLabel: String {
        label.trimmed.isEmpty ? title.trimmed : label.trimmed
    }

    /// The one-line style description carried into generation prompts alongside the
    /// attached style image; falls back to the browse caption for older catalogs.
    var styleSummaryLine: String {
        let summary = (oneLineStyleSummary ?? "").trimmed
        return summary.isEmpty ? caption.trimmed : summary
    }

    func treatmentSlot(weight: Int) -> LensStyleTreatmentSlot {
        LensStyleTreatmentSlot(
            styleId: id,
            label: displayLabel,
            collection: collection,
            hueHex: hueHex,
            url: url,
            weight: weight
        )
    }
}

struct StyleBrowseCatalog: Codable, Hashable, Sendable {
    static let empty = StyleBrowseCatalog(
        schemaVersion: "",
        catalogKind: "",
        version: "",
        taxonomyVersion: "",
        categorizationModel: "",
        styleCount: 0,
        collections: [],
        styles: []
    )

    var schemaVersion: String
    var catalogKind: String
    var version: String
    var taxonomyVersion: String
    var categorizationModel: String
    var styleCount: Int
    var collections: [StyleBrowseCollection]
    var styles: [StyleBrowseStyle]

    var isUsable: Bool {
        schemaVersion == "litscenes.style_browse_catalog.v0.1" && !styles.isEmpty && !collections.isEmpty
    }

    var displayCollections: [StyleBrowseCollection] {
        collections.sorted { $0.sortOrder < $1.sortOrder }
    }

    func styles(in collectionKey: String) -> [StyleBrowseStyle] {
        styles.filter { $0.collection == collectionKey }
    }

    func style(withId id: String) -> StyleBrowseStyle? {
        styles.first { $0.id == id }
    }
}

extension StyleBrowseStyle {
    /// Verifiable image reference for provider image inputs; nil when the catalog entry
    /// predates sha256 publication.
    func styleImageReference(catalogVersion: String) -> SREFStyleImageReference? {
        guard let sha256, !sha256.trimmed.isEmpty, !url.trimmed.isEmpty else { return nil }
        return SREFStyleImageReference(
            catalogKind: "style_browse_catalog",
            catalogVersion: catalogVersion,
            itemId: id,
            title: displayLabel,
            srefCode: srefCode,
            sourceKey: srefCode,
            variantName: "generated_1024",
            url: url,
            sha256: sha256,
            width: width ?? 1024,
            height: height ?? 1024,
            byteSize: 0,
            mimeType: "image/png"
        ).normalized()
    }
}

extension LensStyleIngredient {
    static func styleCatalogReference(
        style: StyleBrowseStyle,
        reference: SREFStyleImageReference,
        roleLabel: String,
        collectionName: String,
        order: Int,
        now: String = DateFormats.now()
    ) -> LensStyleIngredient {
        LensStyleIngredient(
            ingredientId: "ingredient_\(shortHash("\(reference.id):\(order):\(now)", length: 12))",
            order: order,
            enabled: true,
            title: style.displayLabel,
            role: "style_reference",
            narrativeUse: "\(roleLabel) from the style catalog; its image anchors Lens image generation.",
            presentationUse: uniqueNonEmpty([roleLabel, collectionName]).joined(separator: " · "),
            notes: style.caption,
            paletteTerms: [],
            motifTerms: [],
            avoidTerms: [],
            referenceAestheticIds: [],
            sourceRecipeId: nil,
            sourceRecipeVersion: reference.catalogVersion,
            sourceReferenceIds: [reference.sourceReferenceId],
            updatedAt: now
        )
    }
}

actor StyleBrowseCatalogRuntime {
    static let shared = StyleBrowseCatalogRuntime()

    func loadCatalog(force: Bool = false) async throws -> StyleBrowseCatalog {
        try await CatalogManifestRuntime.shared.loadSnapshot(force: force).styleBrowse
    }
}
