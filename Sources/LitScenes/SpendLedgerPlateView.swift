import SwiftUI

/// THE SPEND LEDGER PLATE — every recorded paid event, newest day first,
/// with per-day subtotals folded from the rows on display. Labels wear the
/// honesty laws: "unpriced" for a nil estimate (never $0), "charge unknown"
/// on failures, and the submission-time caption on the footer.
struct SpendLedgerPlateView: View {
    @ObservedObject var library: LibraryEngine
    var onClose: () -> Void

    @State private var entries: [SpendLedgerEntry] = []
    @State private var hasLoaded = false

    /// (dayKey, rows) newest day first; rows newest first inside a day.
    private var dayGroups: [(day: String, rows: [SpendLedgerEntry])] {
        let grouped = Dictionary(grouping: entries) { spendLedgerDayKey($0.at) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day, default: []].sorted { $0.at > $1.at })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                PlateLabel(text: "SPEND LEDGER", size: 11, weight: .bold, color: PlateColor.ink)
                PlateLabel(
                    text: library.currentProject?.name.trimmed.nilIfEmpty ?? "This project",
                    size: 9,
                    color: PlateColor.inkFaint
                )
                Spacer(minLength: 0)
                PlateLabel(
                    text: projectTotalLabel,
                    size: 9,
                    weight: .semibold,
                    color: PlateColor.ink
                )
                .help("Everything this project has recorded, including days pruned from the ledger view")
                Button("Close") { onClose() }
                    .buttonStyle(PlateButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if entries.isEmpty {
                        PlateLabel(
                            text: hasLoaded
                                ? "No paid operations recorded yet — the ledger starts with the next render."
                                : "Loading…",
                            size: 9,
                            color: PlateColor.inkFaint
                        )
                    }
                    ForEach(dayGroups, id: \.day) { group in
                        daySection(group.day, rows: group.rows)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            HStack {
                PlateLabel(text: spendHonestyCaption, size: 8.5, color: PlateColor.inkFaint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: 940, height: 610)
        .background(PlateColor.cream)
        .environment(\.colorScheme, .light)
        .onAppear {
            entries = library.loadSpendLedgerEntries()
            hasLoaded = true
        }
    }

    private var projectTotalLabel: String {
        let total = library.spendLedgerSummary.projectTotal
        guard total.pricedCount + total.unpricedCount + total.failedCount > 0 else {
            return "PROJECT · nothing recorded"
        }
        return "PROJECT · \(dayTotalLabel(total))"
    }

    /// "$4.20 + 312 credits · 3 unpriced · 1 failed" — folded amounts plus
    /// the honest unknowns.
    private func dayTotalLabel(_ total: SpendLedgerDayTotal) -> String {
        var parts: [String] = []
        if total.usd > 0 || total.credits > 0 {
            parts.append(spendAmountLabel(
                usd: total.usd > 0 ? total.usd : nil,
                credits: total.credits > 0 ? total.credits : nil
            ))
        }
        if total.unpricedCount > 0 {
            parts.append(total.unpricedCount == 1 ? "1 unpriced" : "\(total.unpricedCount) unpriced")
        }
        if total.failedCount > 0 {
            parts.append(total.failedCount == 1 ? "1 failed" : "\(total.failedCount) failed")
        }
        return parts.isEmpty ? "unpriced" : parts.joined(separator: " · ")
    }

    private func daySection(_ day: String, rows: [SpendLedgerEntry]) -> some View {
        var subtotal = SpendLedgerDayTotal()
        for row in rows { subtotal.fold(row) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PlateLabel(text: day, size: 9.5, weight: .bold, color: PlateColor.ink)
                PlateLabel(text: dayTotalLabel(subtotal), size: 8.5, color: PlateColor.inkFaint)
                Spacer(minLength: 0)
                PlateLabel(
                    text: rows.count == 1 ? "1 operation" : "\(rows.count) operations",
                    size: 8.5,
                    color: PlateColor.inkFaint
                )
            }
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            ForEach(rows) { row in
                entryRow(row)
            }
        }
    }

    private func entryRow(_ entry: SpendLedgerEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            PlateLabel(text: spendClockLabel(entry.at), size: 8.5, color: PlateColor.inkFaint)
                .frame(width: 36, alignment: .leading)
            PlateLabel(
                text: spendKindDisplayLabel(entry.kind),
                size: 9,
                weight: .semibold,
                color: entry.isFailure ? CanonColor.rust : PlateColor.ink
            )
            .frame(width: 110, alignment: .leading)
            PlateLabel(
                text: entry.contextLabel.trimmed.nilIfEmpty ?? "—",
                size: 9,
                color: PlateColor.ink
            )
            .frame(width: 170, alignment: .leading)
            PlateLabel(
                text: providerModelLabel(entry),
                size: 8.5,
                color: PlateColor.inkFaint
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            PlateLabel(
                text: spendUnitsLabel(unit: entry.unit, unitCount: entry.unitCount),
                size: 8.5,
                color: PlateColor.inkFaint
            )
            .frame(width: 70, alignment: .trailing)
            PlateLabel(
                text: entry.isFailure
                    ? "charge unknown"
                    : spendAmountLabel(usd: entry.estimatedUSD, credits: entry.estimatedCredits),
                size: 9,
                weight: .semibold,
                color: entry.isFailure ? CanonColor.rust : PlateColor.ink
            )
            .frame(width: 120, alignment: .trailing)
            .help(entry.pricingNote.trimmed.isEmpty ? "" : entry.pricingNote)
        }
        .padding(.vertical, 1)
    }

    private func providerModelLabel(_ entry: SpendLedgerEntry) -> String {
        let model = entry.model.trimmed
        let provider = entry.provider.trimmed
        if model.isEmpty { return provider }
        if provider.isEmpty { return model }
        return "\(provider) · \(model)"
    }
}
