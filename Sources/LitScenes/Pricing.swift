import Foundation

struct PricingManifest: Codable {
    var schemaVersion: String
    var updatedAt: String
    var source: String
    var models: [ModelPricing]

    static func load() throws -> PricingManifest {
        let url = try packagedResourceURL(named: "openai_pricing", extension: "json")
        return try JSONCoding.decoder.decode(PricingManifest.self, from: Data(contentsOf: url))
    }

    func pricing(for model: String) -> ModelPricing {
        models.first { $0.model == model } ?? models.first { $0.model == "gpt-5.5" } ?? ModelPricing(
            model: model,
            inputPerMillion: 1.25,
            cachedInputPerMillion: 0.125,
            outputPerMillion: 10.0
        )
    }
}

struct ModelPricing: Codable, Hashable {
    var model: String
    var inputPerMillion: Double
    var cachedInputPerMillion: Double
    var outputPerMillion: Double
}

struct CostEstimator {
    var manifest: PricingManifest

    func estimateImageInputTokens(width: Int, height: Int, detail: ImageDetail) -> Int {
        let patches = Int(ceil(Double(max(width, 1)) / 32.0) * ceil(Double(max(height, 1)) / 32.0))
        let cap = detail == .original ? 10_000 : 2_500
        return min(patches, cap)
    }

    func estimateRequestCost(model: String, width: Int, height: Int, detail: ImageDetail, promptTokens: Int = 1_200, outputTokens: Int = 900) -> Double {
        let pricing = manifest.pricing(for: model)
        let inputTokens = estimateImageInputTokens(width: width, height: height, detail: detail) + promptTokens
        return (Double(inputTokens) / 1_000_000.0 * pricing.inputPerMillion)
            + (Double(outputTokens) / 1_000_000.0 * pricing.outputPerMillion)
    }

    func actualCost(model: String, usage: OpenAIUsage) -> Double {
        let pricing = manifest.pricing(for: model)
        let uncached = max(0, usage.inputTokens - usage.cachedInputTokens)
        return (Double(uncached) / 1_000_000.0 * pricing.inputPerMillion)
            + (Double(usage.cachedInputTokens) / 1_000_000.0 * pricing.cachedInputPerMillion)
            + (Double(usage.outputTokens) / 1_000_000.0 * pricing.outputPerMillion)
    }
}
