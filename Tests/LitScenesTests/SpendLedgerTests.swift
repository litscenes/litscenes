import Foundation
import Testing
@testable import LitScenes

// THE SPEND LEDGER's pure laws: tolerant persistence, the dedupe law, the
// fold law (caps, pruning, watermarks), label honesty, the attention law,
// and a real SQLite round-trip through the document store.

private func entry(
    id: String = "spend_a",
    at: String = "2026-08-02T10:00:00Z",
    kind: String = "shot_render_segment",
    usd: Double? = 0.4,
    credits: Double? = nil,
    status: String = "completed"
) -> SpendLedgerEntry {
    SpendLedgerEntry(
        entryId: id,
        at: at,
        kind: kind,
        provider: "fal_image_to_video",
        model: "fal-ai/wan/v2.7/image-to-video",
        requestId: "req_\(id)",
        contextLabel: "Shot 1",
        shotId: "shot_1",
        unit: "seconds",
        unitCount: 8,
        estimatedUSD: usd,
        estimatedCredits: credits,
        status: status
    )
}

// MARK: - Persistence tolerance

@Test func ledgerDocumentsDecodeTolerantly() throws {
    let bareEntry = try JSONDecoder().decode(SpendLedgerEntry.self, from: Data("{}".utf8))
    #expect(bareEntry.status == "completed")
    #expect(bareEntry.estimatedUSD == nil)

    let bareSummary = try JSONDecoder().decode(
        SpendLedgerSummaryDocument.self,
        from: Data(#"{"projectId":"p1","junkKey":true}"#.utf8)
    )
    #expect(bareSummary.projectId == "p1")
    #expect(bareSummary.totalsByDay.isEmpty)

    // Round-trip through the store's own coder.
    let full = entry()
    let data = try JSONCoding.encoder.encode(full)
    let back = try JSONCoding.decoder.decode(SpendLedgerEntry.self, from: data)
    #expect(back == full)
}

// MARK: - The dedupe law

@Test func entryIdDerivesFromProviderJobAndFallsBackUnique() {
    let a = spendLedgerEntryId(kind: "shot_look", requestId: "job_1")
    let b = spendLedgerEntryId(kind: "shot_look", requestId: "job_1")
    #expect(a == b)
    // Same job under a different kind is a different event.
    #expect(spendLedgerEntryId(kind: "clip_look", requestId: "job_1") != a)
    // No request id: each attempt is its own honest row.
    #expect(spendLedgerEntryId(kind: "image", requestId: "")
        != spendLedgerEntryId(kind: "image", requestId: ""))
}

// MARK: - The fold law

@Test func foldMovesTotalsOnlyForNewEntriesAndKeepsRecents() {
    var summary = SpendLedgerSummaryDocument.empty(projectId: "p1")
    let paid = entry()
    summary = spendLedgerSummaryFolding(paid, into: summary, entryAlreadyExists: false, now: paid.at)
    #expect(abs(summary.projectTotal.usd - 0.4) < 0.000_1)
    #expect(summary.projectTotal.pricedCount == 1)
    #expect(summary.recentEntries.map(\.entryId) == ["spend_a"])

    // Re-observing the same job (a resume) surfaces it but folds nothing.
    summary = spendLedgerSummaryFolding(paid, into: summary, entryAlreadyExists: true, now: paid.at)
    #expect(abs(summary.projectTotal.usd - 0.4) < 0.000_1)
    #expect(summary.recentEntries.count == 1)

    // An unpriced entry counts as unpriced — its dollars are UNKNOWN, not 0.
    let unpriced = entry(id: "spend_b", usd: nil)
    summary = spendLedgerSummaryFolding(unpriced, into: summary, entryAlreadyExists: false, now: unpriced.at)
    #expect(summary.projectTotal.unpricedCount == 1)
    #expect(abs(summary.projectTotal.usd - 0.4) < 0.000_1)

    // A credits-only entry is priced in its own unit.
    let credits = entry(id: "spend_c", usd: nil, credits: 312)
    summary = spendLedgerSummaryFolding(credits, into: summary, entryAlreadyExists: false, now: credits.at)
    #expect(abs(summary.projectTotal.credits - 312) < 0.000_1)
    #expect(summary.projectTotal.pricedCount == 2)

    // Failures advance the attention watermark and count as failures.
    let failed = entry(id: "spend_d", at: "2026-08-02T11:00:00Z", usd: nil, status: "failed_unknown_charge")
    summary = spendLedgerSummaryFolding(failed, into: summary, entryAlreadyExists: false, now: failed.at)
    #expect(summary.lastFailureAt == "2026-08-02T11:00:00Z")
    #expect(summary.projectTotal.failedCount == 1)

    // Day totals land under the local-calendar day of the entry.
    let day = spendLedgerDayKey(paid.at)
    #expect(abs((summary.totalsByDay[day]?.usd ?? 0) - 0.4) < 0.000_1)
}

@Test func foldEnforcesCapsAndPrunesDaysLosslessly() {
    var summary = SpendLedgerSummaryDocument.empty(projectId: "p1")
    // Overflow the recents caps.
    for index in 0..<(SpendLedgerSummaryDocument.recentEntryIdsCap + 10) {
        let row = entry(id: "spend_\(index)", usd: 0.01)
        summary = spendLedgerSummaryFolding(row, into: summary, entryAlreadyExists: false, now: row.at)
    }
    #expect(summary.recentEntries.count == SpendLedgerSummaryDocument.recentEntriesCap)
    #expect(summary.recentEntryIds.count == SpendLedgerSummaryDocument.recentEntryIdsCap)
    let expectedTotal = Double(SpendLedgerSummaryDocument.recentEntryIdsCap + 10) * 0.01
    #expect(abs(summary.projectTotal.usd - expectedTotal) < 0.001)

    // Overflow the day cap: old keys prune, projectTotal keeps their spend.
    var pruned = SpendLedgerSummaryDocument.empty(projectId: "p1")
    for index in 0..<(SpendLedgerSummaryDocument.dayKeyCap + 5) {
        let day = index + 1
        let stamp = String(format: "%04d-01-01T10:00:00Z", 2000 + day)
        let row = entry(id: "spend_day_\(index)", at: stamp, usd: 1)
        pruned = spendLedgerSummaryFolding(row, into: pruned, entryAlreadyExists: false, now: stamp)
    }
    #expect(pruned.totalsByDay.count == SpendLedgerSummaryDocument.dayKeyCap)
    #expect(abs(pruned.projectTotal.usd - Double(SpendLedgerSummaryDocument.dayKeyCap + 5)) < 0.001)
}

@Test func dayKeyParsesBothFractionalAndPlainStamps() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    // `DateFormats.now()` writes fractional seconds — the day key must not
    // fall back to "today" for real entries.
    #expect(spendLedgerDayKey("2026-03-05T10:00:00.123Z", calendar: calendar) == "2026-03-05")
    #expect(spendLedgerDayKey("2026-03-05T10:00:00Z", calendar: calendar) == "2026-03-05")
}

// MARK: - Label honesty

@Test func amountLabelNeverRendersUnknownAsZero() {
    #expect(spendAmountLabel(usd: nil, credits: nil) == "unpriced")
    #expect(spendAmountLabel(usd: 0.4, credits: nil) == "$0.40")
    // Sub-cent keeps three decimals rather than lying "$0.00".
    #expect(spendAmountLabel(usd: 0.004, credits: nil) == "$0.004")
    #expect(spendAmountLabel(usd: nil, credits: 312) == "312 credits")
    #expect(spendAmountLabel(usd: 0.5, credits: 100) == "$0.50 + 100 credits")
}

// MARK: - The attention law

@Test func failureAttentionArmsAcksAndReArms() {
    var summary = SpendLedgerSummaryDocument.empty(projectId: "p1")
    #expect(!evaluateSpendFailureAttention(summary))

    summary.lastFailureAt = "2026-08-02T11:00:00Z"
    #expect(evaluateSpendFailureAttention(summary))

    // Open == ack.
    summary.failuresAcknowledgedAt = "2026-08-02T11:05:00Z"
    #expect(!evaluateSpendFailureAttention(summary))

    // A NEWER failure re-arms.
    summary.lastFailureAt = "2026-08-02T12:00:00Z"
    #expect(evaluateSpendFailureAttention(summary))
}

// MARK: - Store round-trip

@Test func ledgerRoundTripsThroughTheDocumentStore() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_spend_ledger_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProjectLibrary(root: root)
    let project = try library.createProject(named: "Spend Ledger")
    let store = ProjectContextStore(projectLibrary: library)

    // Fresh project: an empty summary, no entries, no false attention.
    var summary = store.loadSpendLedgerSummary(for: project)
    #expect(summary.totalsByDay.isEmpty)
    #expect(store.loadSpendLedgerEntries(for: project).isEmpty)

    let row = entry()
    #expect(!store.spendLedgerEntryExists(row.entryId, for: project))
    summary = spendLedgerSummaryFolding(row, into: summary, entryAlreadyExists: false, now: row.at)
    try store.saveSpendLedgerEntry(row, summary: summary, for: project)

    // Both halves landed atomically and read back.
    #expect(store.spendLedgerEntryExists(row.entryId, for: project))
    let loaded = store.loadSpendLedgerSummary(for: project)
    #expect(abs(loaded.projectTotal.usd - 0.4) < 0.000_1)
    #expect(store.loadSpendLedgerEntries(for: project).map(\.entryId) == [row.entryId])
}
