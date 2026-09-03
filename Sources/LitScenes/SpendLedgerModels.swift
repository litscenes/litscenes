import Foundation

// THE SPEND LEDGER — what the app actually spent, recorded at the moment it
// spent it, honestly labeled.
//
// HONESTY LAWS:
// - UNPRICED, NEVER $0: a nil estimate renders "unpriced"; every surfaced
//   total wears "Estimates at submission-time rates — not a bill".
// - FAILURES LEDGER: each paid attempt happened; failed rows carry
//   `failed_unknown_charge` because FAL's failure-billing policy is
//   unknowable from here, and the ledger says so instead of guessing.
// - DEDUPE BY PROVIDER JOB: the entry id derives from (kind, requestId)
//   when a request id exists, so a retry or resume re-observing the SAME
//   provider job folds once. Request-id-less failures stay distinct rows by
//   design — every attempt is history.
// - Footage extraction, reused clips, and every local free operation NEVER
//   ledger: the ledger is about money, and $0 rows would drown the truth.

/// One paid event. Persisted as its own document row
/// (`spend_ledger_entry` / documentId = entryId) — the
/// `story_generation_run` per-record shape, so appends never rewrite
/// history.
struct SpendLedgerEntry: Codable, Hashable, Identifiable, Sendable {
    var entryId = ""
    var at = ""
    /// shot_render_segment | shot_render_narration_driven | join_bridge |
    /// shot_look | clip_look | image | narration_tts | story_audio_tts |
    /// sound_effect
    var kind = ""
    var provider = ""
    var model = ""
    var requestId = ""
    var traceId = ""
    /// Shot/frame/cut name resolved AT WRITE TIME — labels are history too.
    var contextLabel = ""
    var shotId = ""
    var imageId = ""
    /// seconds | images | characters
    var unit = ""
    var unitCount: Double = 0
    /// nil = honestly unpriced. NEVER encode an unknown as zero.
    var estimatedUSD: Double?
    /// Non-USD units: ElevenLabs character cost, Decart credits.
    var estimatedCredits: Double?
    var pricingNote = ""
    /// completed | failed_unknown_charge
    var status = "completed"

    var id: String { entryId }
    var isFailure: Bool { status == "failed_unknown_charge" }

    private enum CodingKeys: String, CodingKey {
        case entryId, at, kind, provider, model, requestId, traceId
        case contextLabel, shotId, imageId, unit, unitCount
        // "estimatedUSD" snake-cases to "estimated_usd" which decodes back
        // as "estimatedUsd" — the acronym round-trip trap. The stringValue
        // must be the camel form the decoder reconstructs.
        case estimatedUSD = "estimatedUsd"
        case estimatedCredits, pricingNote, status
    }

    init(
        entryId: String = "",
        at: String = "",
        kind: String = "",
        provider: String = "",
        model: String = "",
        requestId: String = "",
        traceId: String = "",
        contextLabel: String = "",
        shotId: String = "",
        imageId: String = "",
        unit: String = "",
        unitCount: Double = 0,
        estimatedUSD: Double? = nil,
        estimatedCredits: Double? = nil,
        pricingNote: String = "",
        status: String = "completed"
    ) {
        self.entryId = entryId
        self.at = at
        self.kind = kind
        self.provider = provider
        self.model = model
        self.requestId = requestId
        self.traceId = traceId
        self.contextLabel = contextLabel
        self.shotId = shotId
        self.imageId = imageId
        self.unit = unit
        self.unitCount = unitCount
        self.estimatedUSD = estimatedUSD
        self.estimatedCredits = estimatedCredits
        self.pricingNote = pricingNote
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decodeIfPresent(String.self, forKey: .entryId) ?? ""
        at = try container.decodeIfPresent(String.self, forKey: .at) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        contextLabel = try container.decodeIfPresent(String.self, forKey: .contextLabel) ?? ""
        shotId = try container.decodeIfPresent(String.self, forKey: .shotId) ?? ""
        imageId = try container.decodeIfPresent(String.self, forKey: .imageId) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        unitCount = try container.decodeIfPresent(Double.self, forKey: .unitCount) ?? 0
        estimatedUSD = try container.decodeIfPresent(Double.self, forKey: .estimatedUSD)
        estimatedCredits = try container.decodeIfPresent(Double.self, forKey: .estimatedCredits)
        pricingNote = try container.decodeIfPresent(String.self, forKey: .pricingNote) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "completed"
    }
}

struct SpendLedgerDayTotal: Codable, Hashable, Sendable {
    var usd: Double = 0
    var credits: Double = 0
    var pricedCount = 0
    var unpricedCount = 0
    var failedCount = 0
    var countsByKind: [String: Int] = [:]

    private enum CodingKeys: String, CodingKey {
        case usd, credits, pricedCount, unpricedCount, failedCount, countsByKind
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usd = try container.decodeIfPresent(Double.self, forKey: .usd) ?? 0
        credits = try container.decodeIfPresent(Double.self, forKey: .credits) ?? 0
        pricedCount = try container.decodeIfPresent(Int.self, forKey: .pricedCount) ?? 0
        unpricedCount = try container.decodeIfPresent(Int.self, forKey: .unpricedCount) ?? 0
        failedCount = try container.decodeIfPresent(Int.self, forKey: .failedCount) ?? 0
        countsByKind = try container.decodeIfPresent([String: Int].self, forKey: .countsByKind) ?? [:]
    }

    mutating func fold(_ entry: SpendLedgerEntry) {
        if let usdValue = entry.estimatedUSD {
            usd += usdValue
            pricedCount += 1
        } else if entry.estimatedCredits != nil {
            pricedCount += 1
        } else {
            unpricedCount += 1
        }
        if let creditsValue = entry.estimatedCredits {
            credits += creditsValue
        }
        if entry.isFailure { failedCount += 1 }
        countsByKind[entry.kind, default: 0] += 1
    }
}

/// The rolled-up summary — one document, rewritten per event (bounded: caps
/// below keep it at tens of KB, well inside the store's demonstrated
/// envelope). `projectTotal` accumulates forever, so pruning old day keys
/// loses nothing.
struct SpendLedgerSummaryDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.spend_ledger.v1"
    static let recentEntriesCap = 20
    static let recentEntryIdsCap = 200
    static let dayKeyCap = 366

    var schemaVersion: String = SpendLedgerSummaryDocument.schemaVersion
    var projectId = ""
    var totalsByDay: [String: SpendLedgerDayTotal] = [:]
    var projectTotal = SpendLedgerDayTotal()
    /// Newest-first, capped — the popover renders without a DB read.
    var recentEntries: [SpendLedgerEntry] = []
    /// Newest-first, capped — `recordSpend`'s fast dedupe window.
    var recentEntryIds: [String] = []
    var lastFailureAt = ""
    var failuresAcknowledgedAt = ""
    var updatedAt = ""

    static func empty(projectId: String) -> SpendLedgerSummaryDocument {
        SpendLedgerSummaryDocument(projectId: projectId)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, projectId, totalsByDay, projectTotal
        case recentEntries, recentEntryIds
        case lastFailureAt, failuresAcknowledgedAt, updatedAt
    }

    init(projectId: String = "") {
        self.projectId = projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        totalsByDay = try container.decodeIfPresent([String: SpendLedgerDayTotal].self, forKey: .totalsByDay) ?? [:]
        projectTotal = try container.decodeIfPresent(SpendLedgerDayTotal.self, forKey: .projectTotal) ?? SpendLedgerDayTotal()
        recentEntries = try container.decodeIfPresent([SpendLedgerEntry].self, forKey: .recentEntries) ?? []
        recentEntryIds = try container.decodeIfPresent([String].self, forKey: .recentEntryIds) ?? []
        lastFailureAt = try container.decodeIfPresent(String.self, forKey: .lastFailureAt) ?? ""
        failuresAcknowledgedAt = try container.decodeIfPresent(String.self, forKey: .failuresAcknowledgedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

// MARK: - Pure laws

/// Local-calendar day key ("YYYY-MM-DD") for an ISO timestamp; spend truth
/// is what the OPERATOR's day looked like, not UTC's.
func spendLedgerDayKey(
    _ isoAt: String,
    calendar: Calendar = .current
) -> String {
    // `DateFormats.now()` writes fractional seconds; hand-written stamps may
    // not. A parse that accepted only one silently day-keyed everything to
    // "today" via the fallback.
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    let date = fractional.date(from: isoAt) ?? plain.date(from: isoAt) ?? Date()
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 0,
        components.day ?? 0
    )
}

/// THE DEDUPE LAW: a provider job's identity IS the entry's identity, so a
/// retry or resume re-observing the same job produces the same entry id and
/// folds once. Without a request id (mostly failures), each attempt gets a
/// unique id — it honestly happened.
func spendLedgerEntryId(kind: String, requestId: String) -> String {
    let cleaned = requestId.trimmed
    guard !cleaned.isEmpty else {
        return "spend_\(UUID().uuidString.lowercased())"
    }
    return "spend_\(shortHash("\(kind):\(cleaned)", length: 16))"
}

/// THE FOLD LAW: totals move only for a NEW entry (dedupe); recents always
/// surface the entry; a failure advances the attention watermark; caps and
/// day-pruning are enforced here so no caller can forget them.
func spendLedgerSummaryFolding(
    _ entry: SpendLedgerEntry,
    into summary: SpendLedgerSummaryDocument,
    entryAlreadyExists: Bool,
    now: String
) -> SpendLedgerSummaryDocument {
    var value = summary
    if !entryAlreadyExists {
        let dayKey = spendLedgerDayKey(entry.at.isEmpty ? now : entry.at)
        var day = value.totalsByDay[dayKey] ?? SpendLedgerDayTotal()
        day.fold(entry)
        value.totalsByDay[dayKey] = day
        value.projectTotal.fold(entry)
    }
    value.recentEntries.removeAll { $0.entryId == entry.entryId }
    value.recentEntries.insert(entry, at: 0)
    value.recentEntries = Array(value.recentEntries.prefix(SpendLedgerSummaryDocument.recentEntriesCap))
    value.recentEntryIds.removeAll { $0 == entry.entryId }
    value.recentEntryIds.insert(entry.entryId, at: 0)
    value.recentEntryIds = Array(value.recentEntryIds.prefix(SpendLedgerSummaryDocument.recentEntryIdsCap))
    if entry.isFailure {
        value.lastFailureAt = entry.at.isEmpty ? now : entry.at
    }
    if value.totalsByDay.count > SpendLedgerSummaryDocument.dayKeyCap {
        // Keys are sortable dates; drop the oldest. `projectTotal` already
        // holds their spend, so pruning is lossless.
        let keep = Set(value.totalsByDay.keys.sorted(by: >).prefix(SpendLedgerSummaryDocument.dayKeyCap))
        value.totalsByDay = value.totalsByDay.filter { keep.contains($0.key) }
    }
    value.updatedAt = now
    return value
}

/// UNPRICED, NEVER $0: nil USD and nil credits render as the word, not as
/// a lying zero. Sub-cent amounts keep three decimals (the pricing
/// headline precedent).
func spendAmountLabel(usd: Double?, credits: Double?) -> String {
    if let usd {
        let dollars = usd >= 0.01 || usd == 0
            ? String(format: "$%.2f", usd)
            : String(format: "$%.3f", usd)
        if let credits, credits > 0 {
            return "\(dollars) + \(creditsLabel(credits))"
        }
        return dollars
    }
    if let credits {
        return creditsLabel(credits)
    }
    return "unpriced"
}

private func creditsLabel(_ credits: Double) -> String {
    credits == credits.rounded()
        ? "\(Int(credits)) credits"
        : String(format: "%.1f credits", credits)
}

/// The badge law: a failure newer than the acknowledgment watermark lights
/// rust; opening the popover acknowledges (open == ack, the notices law);
/// a newer failure re-arms. ISO timestamps compare lexically.
func evaluateSpendFailureAttention(_ summary: SpendLedgerSummaryDocument) -> Bool {
    guard !summary.lastFailureAt.isEmpty else { return false }
    return summary.lastFailureAt > summary.failuresAcknowledgedAt
}
