import Foundation

struct ReadyLensSetDigest: Codable, Hashable {
    var schemaVersion: String = ProjectLensSetDocument.schemaVersion
    var lenses: [ReadyLensDigest]
}

struct ReadyLensDigest: Codable, Hashable {
    var lensId: String
    var updatedAt: String
    var title: String
    var claim: String
    var visualSummary: String
    var colorPalette: [LensColorSwatch]
    var styleIngredients: [ReadyLensIngredientDigest]
    var paletteTerms: [String]
    var motifTerms: [String]
    var textureMaterialTerms: [String]
    var compositionTerms: [String]
    var pacingEnergyTerms: [String]
    var mustPreserve: [String]
    var mustAvoid: [String]
    var referenceMediaIds: [String]
    var derivedVirtues: [String]
}

struct ReadyLensIngredientDigest: Codable, Hashable {
    var ingredientId: String
    var title: String
    var role: String
    var narrativeUse: String
    var presentationUse: String
    var paletteTerms: [String]
    var motifTerms: [String]
    var avoidTerms: [String]
    var referenceAestheticIds: [String]
    var sourceRecipeId: String
    var sourceRecipeVersion: String
}

struct CurrentLensSetPromptJSON: Codable, Hashable {
    var schemaVersion: String = "litscenes.current_lens_set_prompt.v0.1"
    var readyLensSetHash: String
    var digest: ReadyLensSetDigest
    var rowSnapshots: [LensRowSnapshot]
}

struct PromptSafeLensSetPacket: Codable, Hashable {
    var schemaVersion: String = "litscenes.prompt_safe_lens_set.v0.1"
    var readyLensSetHash: String
    var promptSafeLensSetHash: String
    var lenses: [PromptSafeLensSnapshot]
}

struct PromptSafeLensSnapshot: Codable, Hashable {
    var lensId: String
    var snapshotHash: String
    var claim: String
    var visualSummary: String
    var resolvedVisualLanguage: LensResolvedVisualLanguage
    var mustPreserve: [String]
    var mustAvoid: [String]
    var referenceMediaIds: [String]
    var readinessIssues: [LensReadinessIssue]

    static func from(lens: ProjectLens) -> PromptSafeLensSnapshot {
        let normalized = lens.normalized()
        let body = normalized.body.normalized()
        let sourceLabels = uniqueNonEmpty([body.title] + body.styleIngredients.map(\.title))
        let resolved = sanitizedGeneratedLensResolvedLanguage(
            body.resolvedVisualLanguageForSceneStory,
            sourceLabels: sourceLabels
        )
        let report = body.readinessReport
        return PromptSafeLensSnapshot(
            lensId: normalized.lensId,
            snapshotHash: stableHash(normalized, length: 20),
            claim: sanitizedLensProductionValue(body.claim, sourceLabels: sourceLabels),
            visualSummary: sanitizedLensProductionValue(body.visualSummary, sourceLabels: sourceLabels),
            resolvedVisualLanguage: resolved,
            mustPreserve: sanitizedLensProductionValues(body.mustPreserve, sourceLabels: sourceLabels),
            mustAvoid: lensLiteralVisualAvoidTerms(body.mustAvoid + resolved.avoid),
            referenceMediaIds: body.referenceMediaIds,
            readinessIssues: uniqueReadinessIssues(normalized.readyReadinessIssues + report.blockingIssues + report.warnings)
        )
    }
}

func promptSafeLensSetPacket(_ lensSet: ProjectLensSetDocument, readyLensSetHash: String) -> PromptSafeLensSetPacket {
    let lenses = lensSet.readyLenses
        .sorted { $0.lensId < $1.lensId }
        .map(PromptSafeLensSnapshot.from)
    return PromptSafeLensSetPacket(
        readyLensSetHash: readyLensSetHash,
        promptSafeLensSetHash: stableHash(lenses),
        lenses: lenses
    )
}

func readyLensSetDigest(_ lensSet: ProjectLensSetDocument) -> ReadyLensSetDigest {
    let lenses = lensSet.readyLenses
        .sorted { $0.lensId < $1.lensId }
        .map { lens in
            let body = lens.body.normalized()
            return ReadyLensDigest(
                lensId: lens.lensId,
                updatedAt: lens.updatedAt,
                title: body.title,
                claim: body.claim,
                visualSummary: body.visualSummary,
                colorPalette: body.colorPalette,
                styleIngredients: body.styleIngredients
                    .filter(\.enabled)
                    .sorted { $0.order < $1.order }
                    .map { ingredient in
                        ReadyLensIngredientDigest(
                            ingredientId: ingredient.ingredientId,
                            title: ingredient.title,
                            role: ingredient.role,
                            narrativeUse: ingredient.narrativeUse,
                            presentationUse: ingredient.presentationUse,
                            paletteTerms: ingredient.paletteTerms,
                            motifTerms: ingredient.motifTerms,
                            avoidTerms: ingredient.avoidTerms,
                            referenceAestheticIds: ingredient.referenceAestheticIds,
                            sourceRecipeId: ingredient.sourceRecipeId ?? "",
                            sourceRecipeVersion: ingredient.sourceRecipeVersion ?? ""
                        )
                    },
                paletteTerms: body.paletteTerms,
                motifTerms: body.motifTerms,
                textureMaterialTerms: body.textureMaterialTerms,
                compositionTerms: body.compositionTerms,
                pacingEnergyTerms: body.pacingEnergyTerms,
                mustPreserve: body.mustPreserve,
                mustAvoid: body.mustAvoid,
                referenceMediaIds: body.referenceMediaIds,
                derivedVirtues: body.derivedVirtues
            )
        }
    return ReadyLensSetDigest(lenses: lenses)
}

func computeReadyLensSetHash(_ lensSet: ProjectLensSetDocument) -> String {
    stableHash(readyLensSetDigest(lensSet))
}

func lensRowSnapshots(from lensSet: ProjectLensSetDocument) -> [LensRowSnapshot] {
    lensSet.readyLenses.flatMap { lens in
        lens.body.normalized().styleIngredients
            .filter(\.enabled)
            .map { LensRowSnapshot.make(lens: lens, ingredient: $0) }
    }
    .sorted { lhs, rhs in
        if lhs.lensId == rhs.lensId {
            return lhs.ingredientId < rhs.ingredientId
        }
        return lhs.lensId < rhs.lensId
    }
}

func computeLensRowSnapshotHash(_ snapshots: [LensRowSnapshot]) -> String {
    stableHash(snapshots.sorted { $0.snapshotHash < $1.snapshotHash })
}
