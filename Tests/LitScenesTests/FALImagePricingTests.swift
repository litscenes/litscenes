import Foundation
import Testing
@testable import LitScenes

private func price(_ endpoint: String, _ unitPrice: Double, _ unit: String, currency: String = "USD") -> FALModelPrice {
    FALModelPrice(endpointId: endpoint, unitPrice: unitPrice, unit: unit, currency: currency)
}

private func snapshot(_ prices: [FALModelPrice], age: TimeInterval = 0) -> FALPricingSnapshot {
    FALPricingSnapshot(
        fetchedAt: Date().addingTimeInterval(-age),
        prices: Dictionary(prices.map { ($0.endpointId, $0) }, uniquingKeysWith: { first, _ in first })
    )
}

@Suite("THE IMAGE PRICE LAW")
struct FALImagePricingTests {
    @Test("A FAL stack bills the edit endpoint when references attach, else the base model; non-FAL stacks are not FAL-priced")
    func endpointChoice() throws {
        let nano = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.falNanoBanana2))
        #expect(FALImagePricing.endpointId(stack: nano, attachesReferences: true) == "fal-ai/nano-banana-2/edit")
        #expect(FALImagePricing.endpointId(stack: nano, attachesReferences: false) == "fal-ai/nano-banana-2")
        let reve = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.falReve21))
        #expect(FALImagePricing.endpointId(stack: reve, attachesReferences: true) == "reve/2.1/text-to-image")
        let openAI = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase))
        #expect(FALImagePricing.endpointId(stack: openAI, attachesReferences: true) == nil)
        let ids = FALImagePricing.endpointIds(stacks: RenderStackRegistry.shared.stacks())
        #expect(ids.contains("fal-ai/nano-banana-2"))
        #expect(ids.contains("fal-ai/nano-banana-2/edit"))
        #expect(ids.contains("fal-ai/flux-2-pro/edit"))
        #expect(!ids.contains("gpt-image-2"))
        #expect(Set(ids).count == ids.count)
    }

    @Test("Only per-image and per-megapixel units convert; everything else is unpriced")
    func unitLaw() {
        #expect(FALImagePricing.billedUnits(unit: "image", outputPixels: nil) == 1)
        #expect(FALImagePricing.billedUnits(unit: "images", outputPixels: 5) == 1)
        #expect(FALImagePricing.billedUnits(unit: "megapixel", outputPixels: 1_572_864) == 1.572864)
        #expect(FALImagePricing.billedUnits(unit: "megapixels", outputPixels: nil) == nil)
        #expect(FALImagePricing.billedUnits(unit: "seconds", outputPixels: 1_000_000) == nil)
        #expect(FALImagePricing.billedUnits(unit: "units", outputPixels: 1_000_000) == nil)
        #expect(FALImagePricing.billedUnits(unit: "1000 tokens", outputPixels: 1_000_000) == nil)
        #expect(FALImagePricing.billedUnits(unit: "compute seconds", outputPixels: 1_000_000) == nil)
        #expect(FALImagePricing.billedUnits(unit: "", outputPixels: 1_000_000) == nil)
    }

    @Test("Estimates and notes: flat per image, per megapixel scaled by pixels, zero and non-USD unpriced")
    func estimatesAndNotes() {
        let perImage = price("fal-ai/nano-banana-2/edit", 0.10, "image")
        #expect(FALImagePricing.estimateUSD(price: perImage, outputPixels: nil) == 0.10)
        #expect(FALImagePricing.rateNote(price: perImage) == "$0.10 per image")
        let perMP = price("fal-ai/image-apps-v2/outpaint", 0.035, "megapixel")
        #expect(FALImagePricing.estimateUSD(price: perMP, outputPixels: 2_000_000) == 0.07)
        #expect(FALImagePricing.estimateUSD(price: perMP, outputPixels: nil) == nil)
        #expect(FALImagePricing.rateNote(price: perMP) == "$0.04 per megapixel")
        #expect(FALImagePricing.rateNote(price: price("x", 0.005, "image")) == "$0.005 per image")
        #expect(FALImagePricing.estimateUSD(price: price("x", 0, "image"), outputPixels: nil) == nil)
        #expect(FALImagePricing.rateNote(price: price("x", 0, "image")) == nil)
        #expect(FALImagePricing.estimateUSD(price: price("x", 0.1, "image", currency: "EUR"), outputPixels: nil) == nil)
        #expect(FALImagePricing.rateNote(price: price("x", 0.1, "seconds")) == nil)
    }

    @Test("The display note prefers the live rate, marks a stale snapshot, and falls back to the stack's own note")
    func displayNote() throws {
        let nano = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.falNanoBanana2))
        let live = snapshot([price("fal-ai/nano-banana-2/edit", 0.10, "image"), price("fal-ai/nano-banana-2", 0.08, "image")])
        #expect(FALImagePricing.displayNote(stack: nano, attachesReferences: true, snapshot: live) == "$0.10 per image")
        #expect(FALImagePricing.displayNote(stack: nano, attachesReferences: false, snapshot: live) == "$0.08 per image")
        let stale = snapshot([price("fal-ai/nano-banana-2", 0.08, "image")], age: 3 * 86_400)
        #expect(FALImagePricing.displayNote(stack: nano, attachesReferences: false, snapshot: stale) == "$0.08 per image · rates 3d ago")
        // Unreadable unit → the yaml note (Nano Banana has none → "").
        let unreadable = snapshot([price("fal-ai/nano-banana-2", 0.08, "units")])
        #expect(FALImagePricing.displayNote(stack: nano, attachesReferences: false, snapshot: unreadable) == "")
        #expect(FALImagePricing.displayNote(stack: nano, attachesReferences: false, snapshot: nil) == "")
        let reve = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.falReve21))
        #expect(FALImagePricing.displayNote(stack: reve, attachesReferences: false, snapshot: nil) == "$0.25 per image")
        #expect(FALImagePricing.renderedEstimateUSD(endpointId: "fal-ai/nano-banana-2/edit", snapshot: live, outputPixels: nil) == 0.10)
        #expect(FALImagePricing.renderedEstimateUSD(endpointId: "missing", snapshot: live, outputPixels: nil) == nil)
    }

    @Test("The on-disk snapshot shape (reference-date fetched_at, endpoint-keyed prices) decodes")
    func snapshotDecodes() throws {
        let json = #"{"fetchedAt":809803373.962147,"prices":{"fal-ai/wan/v2.7/image-to-video":{"endpoint_id":"fal-ai/wan/v2.7/image-to-video","unit_price":0.1,"unit":"seconds","currency":"USD"}}}"#
        let decoded = try JSONDecoder().decode(FALPricingSnapshot.self, from: Data(json.utf8))
        #expect(decoded.prices["fal-ai/wan/v2.7/image-to-video"]?.unit == "seconds")
        #expect(decoded.ageSeconds > 0)
    }
}
