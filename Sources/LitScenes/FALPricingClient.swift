import Foundation

// MARK: - Live FAL model pricing (the render-plan strip's cost source)
//
// Rates come from FAL's platform pricing API and are cached for ~a day —
// never hardcoded, never blocking: a fetch failure leaves the last snapshot
// (the UI shows its age) or an honest "rates unavailable".

struct FALModelPrice: Codable, Hashable, Sendable {
    var endpointId: String
    var unitPrice: Double
    var unit: String
    var currency: String

    private enum CodingKeys: String, CodingKey {
        case endpointId = "endpoint_id"
        case unitPrice = "unit_price"
        case unit
        case currency
    }
}

/// One snapshot for every FAL endpoint the app can bill against — video
/// segments and image stacks alike. The cache file keeps its historical name.
struct FALPricingSnapshot: Codable, Hashable, Sendable {
    var fetchedAt: Date
    /// Keyed by endpoint id (e.g. "fal-ai/kling-video/v3/pro/image-to-video").
    var prices: [String: FALModelPrice]

    var ageSeconds: TimeInterval {
        max(0, Date().timeIntervalSince(fetchedAt))
    }

    /// "just now" / "3h ago" / "2d ago" — the header's honesty caption.
    var ageLabel: String {
        let age = ageSeconds
        if age < 90 { return "just now" }
        if age < 3_600 { return "\(Int(age / 60))m ago" }
        if age < 86_400 { return "\(Int(age / 3_600))h ago" }
        return "\(Int(age / 86_400))d ago"
    }
}

enum FALPricingClientError: Error, LocalizedError {
    case missingAPIKey
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "FAL API key is not configured"
        case .badResponse(let code):
            return "FAL pricing API returned HTTP \(code)"
        }
    }
}

/// One tiny GET against FAL's platform pricing API.
struct FALPricingClient {
    var session: URLSession = .shared

    private struct PricingResponse: Decodable {
        var prices: [FALModelPrice]
    }

    func fetchPrices(endpointIds: [String], apiKey: String) async throws -> [FALModelPrice] {
        let key = apiKey.trimmed
        guard !key.isEmpty else { throw FALPricingClientError.missingAPIKey }
        var components = URLComponents(string: "https://api.fal.ai/v1/models/pricing")!
        components.queryItems = [URLQueryItem(name: "endpoint_id", value: endpointIds.joined(separator: ","))]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw FALPricingClientError.badResponse(status)
        }
        return try JSONDecoder().decode(PricingResponse.self, from: data).prices
    }
}

typealias FALVideoPricingSnapshot = FALPricingSnapshot

// MARK: - Cost estimation over a segment plan

/// What the render-plan strip can honestly claim about cost. `totalUSD` sums
/// only PRICED segments; when `unpricedModelLabels` is non-empty the UI shows
/// "≥" and names what's missing.
struct ShotRenderCostEstimate: Equatable {
    var totalUSD: Double = 0
    var pricedSegmentCount: Int = 0
    var totalGeneratedCount: Int = 0
    var unpricedModelLabels: [String] = []
    var isFetchingRates: Bool = false
    var includesPublishedRateEstimate: Bool = false

    var isComplete: Bool { unpricedModelLabels.isEmpty && totalGeneratedCount > 0 }

    var headlineLabel: String? {
        guard pricedSegmentCount > 0 else { return nil }
        let amount = totalUSD < 0.01 && totalUSD > 0
            ? String(format: "$%.3f", totalUSD)
            : String(format: "$%.2f", totalUSD)
        if includesPublishedRateEstimate {
            return isComplete ? "EST. ≈ \(amount)" : "EST. ≥ \(amount) (≈)"
        }
        return isComplete ? "EST. \(amount)" : "EST. ≥ \(amount)"
    }

    /// The FAL endpoint id a stack bills against, nil for models that do not
    /// bill through FAL (native Kling v2.6 bills on its own account).
    static func falEndpointId(for stack: ShotRenderStack) -> String? {
        switch stack.model {
        case .falKlingV3Pro, .falSeedance20, .falSeedance25, .wan27, .falHailuo3, .falHailuo3Max, .falLTX23Narration:
            return stack.pairedModelSelection.providerModelId
        default:
            return nil
        }
    }

    /// Units FAL bills once per render, whatever the clip's length.
    private static let flatUnits: Set<String> = [
        "video", "videos", "request", "requests", "generation", "generations"
    ]

    /// How many billable units one segment consumes, or nil when FAL's unit
    /// string carries no meaning we can convert honestly.
    ///
    /// The unit is INTERPRETED, never assumed flat on fallthrough: FAL reports
    /// Seedance's token-bucket pricing as the opaque `"units"`, and reading
    /// that as a per-render fee under-billed a 4s 1080p segment by 194×
    /// (see `FALTokenBilling`). An unrecognized unit is unpriced — the strip
    /// says "≥" rather than printing a confident wrong number next to a
    /// button that spends money.
    static func billedUnits(stack: ShotRenderStack, unit: String) -> Double? {
        let normalized = unit.lowercased().trimmed
        if normalized.contains("second") {
            return Double(stack.segmentSeconds)
        }
        if normalized == "units" || normalized.contains("token") {
            return stack.pairedModelSelection.falTokenBilling?
                .billedUnits(durationSeconds: stack.segmentSeconds)
        }
        if flatUnits.contains(normalized) {
            return 1
        }
        return nil
    }

    /// Per-segment estimate. A zero rate is unpriced, never a $0.00 line item
    /// — the render bills regardless of what the pricing API claims — and so
    /// is a unit whose dimension we cannot convert.
    static func segmentUSD(stack: ShotRenderStack, pricing: FALPricingSnapshot?) -> Double? {
        guard !stack.isNativeFootageExtend else { return nil }
        guard let endpointId = falEndpointId(for: stack),
              let price = pricing?.prices[endpointId],
              price.currency.uppercased() == "USD",
              price.unitPrice > 0,
              let units = billedUnits(stack: stack, unit: price.unit) else {
            return nil
        }
        return price.unitPrice * units
    }

    /// Published LTX Extend rate for 1920×1080: $0.10 per generated plus
    /// context second. Kept explicit (rather than mixed into FAL pricing) so
    /// the UI labels it as an approximate published-rate estimate.
    static func nativeExtendUSD(durationSeconds: Int, contextSeconds: Double) -> Double? {
        guard (2...20).contains(durationSeconds), contextSeconds >= 1 else { return nil }
        return 0.10 * (Double(durationSeconds) + contextSeconds)
    }

    static func segmentUSD(
        item: ShotSegmentPromptPlanItem,
        pricing: FALPricingSnapshot?
    ) -> Double? {
        if item.renderStack.isNativeFootageExtend {
            guard let context = item.nativeExtendContextSeconds else { return nil }
            return nativeExtendUSD(
                durationSeconds: item.renderStack.segmentSeconds,
                contextSeconds: context
            )
        }
        return segmentUSD(stack: item.renderStack, pricing: pricing)
    }

    /// LTX narration clips bill by the exact authored audio-driver duration,
    /// not the stack's capability-probe duration.
    static func narrationDrivenUSD(
        stack: ShotRenderStack,
        durationSeconds: Double,
        pricing: FALPricingSnapshot?
    ) -> Double? {
        guard stack.isNarrationDriven,
              durationSeconds >= 2,
              durationSeconds <= 20,
              let endpointId = falEndpointId(for: stack),
              let price = pricing?.prices[endpointId],
              price.currency.uppercased() == "USD",
              price.unitPrice > 0 else {
            return nil
        }
        let unit = price.unit.lowercased().trimmed
        if unit.contains("second") {
            return price.unitPrice * durationSeconds
        }
        if flatUnits.contains(unit) {
            return price.unitPrice
        }
        return nil
    }

    static func estimate(
        items: [ShotSegmentPromptPlanItem],
        pricing: FALPricingSnapshot?,
        isFetchingRates: Bool = false
    ) -> ShotRenderCostEstimate {
        var value = ShotRenderCostEstimate(isFetchingRates: isFetchingRates)
        value.totalGeneratedCount = items.count
        var unpriced: [String] = []
        for item in items {
            if let usd = segmentUSD(item: item, pricing: pricing) {
                value.totalUSD += usd
                value.pricedSegmentCount += 1
                value.includesPublishedRateEstimate = value.includesPublishedRateEstimate
                    || item.renderStack.isNativeFootageExtend
            } else if !unpriced.contains(item.renderStack.model.label) {
                unpriced.append(item.renderStack.model.label)
            }
        }
        value.unpricedModelLabels = unpriced
        return value
    }
}
