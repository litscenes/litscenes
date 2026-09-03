import Foundation

/// THE IMAGE PRICE LAW: what a FAL image render can honestly claim about its
/// price from the live pricing snapshot. The unit is INTERPRETED, never assumed:
/// a flat per-image rate prices one output; a per-megapixel rate needs the
/// output's pixels; every other unit, a zero rate, or a non-USD rate is
/// unpriced — never a confident wrong number beside a spending button.
enum FALImagePricing {
    /// The endpoint a Frame or sheet render bills against: the edit endpoint
    /// when references attach and the stack has one, else the base model. nil
    /// for stacks that do not bill through FAL.
    static func endpointId(stack: RenderStack, attachesReferences: Bool) -> String? {
        guard stack.isFAL else { return nil }
        let base = stack.model.trimmed
        let edit = stack.styleModel.trimmed
        if attachesReferences, !edit.isEmpty { return edit }
        return base.isEmpty ? nil : base
    }

    /// Every endpoint a FAL image stack can bill against, for the pricing fetch.
    static func endpointIds(stacks: [RenderStack]) -> [String] {
        var ids: [String] = []
        for stack in stacks where stack.isFAL {
            for id in [stack.model.trimmed, stack.styleModel.trimmed] where !id.isEmpty && !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    enum UnitKind: Equatable {
        case perImage
        case perMegapixel
    }

    /// The only two dimensions an image render can convert honestly.
    static func unitKind(_ unit: String) -> UnitKind? {
        let normalized = unit.lowercased().trimmed
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("megapixel") || normalized == "mp" || normalized.hasSuffix(" mp") {
            return .perMegapixel
        }
        if normalized.contains("image") {
            return .perImage
        }
        return nil
    }

    static func billedUnits(unit: String, outputPixels: Int?) -> Double? {
        switch unitKind(unit) {
        case .perImage:
            return 1
        case .perMegapixel:
            guard let outputPixels, outputPixels > 0 else { return nil }
            return Double(outputPixels) / 1_000_000
        case nil:
            return nil
        }
    }

    private static func usableRate(_ price: FALModelPrice) -> Bool {
        price.currency.uppercased() == "USD" && price.unitPrice > 0
    }

    /// The estimate for one output, or nil when the rate cannot be read.
    static func estimateUSD(price: FALModelPrice, outputPixels: Int?) -> Double? {
        guard usableRate(price), let units = billedUnits(unit: price.unit, outputPixels: outputPixels) else { return nil }
        return price.unitPrice * units
    }

    /// "$0.10 per image" / "$0.035 per megapixel"; nil when the unit is not one
    /// we can read.
    static func rateNote(price: FALModelPrice) -> String? {
        guard usableRate(price), let kind = unitKind(price.unit) else { return nil }
        let amount = price.unitPrice < 0.01
            ? String(format: "$%.3f", price.unitPrice)
            : String(format: "$%.2f", price.unitPrice)
        switch kind {
        case .perImage: return "\(amount) per image"
        case .perMegapixel: return "\(amount) per megapixel"
        }
    }

    /// What the UI states before a click: the live rate when the snapshot can
    /// read it (with its age once it is older than a day), else the stack's own
    /// note, else "" — the consumers print "unpriced" for "".
    static func displayNote(
        stack: RenderStack,
        attachesReferences: Bool,
        snapshot: FALPricingSnapshot?,
        staleAfter: TimeInterval = 86_400
    ) -> String {
        if let snapshot,
           let endpointId = endpointId(stack: stack, attachesReferences: attachesReferences),
           let price = snapshot.prices[endpointId],
           let note = rateNote(price: price) {
            return snapshot.ageSeconds > staleAfter ? "\(note) · rates \(snapshot.ageLabel)" : note
        }
        return stack.priceNote.trimmed
    }

    /// The finished render's estimate: the recipe's endpoint (what was actually
    /// called) against the live snapshot and the file's pixels.
    static func renderedEstimateUSD(endpointId: String, snapshot: FALPricingSnapshot?, outputPixels: Int?) -> Double? {
        guard let price = snapshot?.prices[endpointId.trimmed] else { return nil }
        return estimateUSD(price: price, outputPixels: outputPixels)
    }
}
