import Foundation

// MARK: - Records

/// One baked ambient bed. Identity is the deterministic hash of the normalized
/// spec (`ambientBedId`), so re-baking the identical spec replaces the same bed
/// and file instead of stacking duplicates.
struct AmbientBedRecord: Codable, Hashable, Identifiable, Sendable {
    var bedId: String = ""
    /// Auto-named at bake ("432.00 Hz · warm drift"); a user rename survives
    /// re-bakes of the same spec.
    var displayName: String = ""
    /// The full spec, kept for re-open-in-tuner and re-bake.
    var spec: AmbientBedSpec = AmbientBedSpec()
    /// File name inside the project's ambient directory; extension records the
    /// baked format (.m4a, or .caf on seam-verification fallback).
    var fileName: String = ""
    /// PCM truth from the bake result — composition loop math uses this, never
    /// container metadata.
    var durationSeconds: Double = 0
    var createdAt: String = ""
    var updatedAt: String = ""

    var id: String { bedId }

    init(
        bedId: String = "",
        displayName: String = "",
        spec: AmbientBedSpec = AmbientBedSpec(),
        fileName: String = "",
        durationSeconds: Double = 0,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.bedId = bedId
        self.displayName = displayName
        self.spec = spec
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case bedId
        case displayName
        case spec
        case fileName
        case durationSeconds
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bedId = try container.decodeIfPresent(String.self, forKey: .bedId) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        spec = ((try? container.decodeIfPresent(AmbientBedSpec.self, forKey: .spec)) ?? nil) ?? AmbientBedSpec()
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> AmbientBedRecord {
        var value = self
        value.bedId = value.bedId.trimmed
        value.displayName = value.displayName.trimmed
        value.spec = value.spec.normalized()
        value.fileName = value.fileName.trimmed
        if value.fileName.isEmpty, !value.bedId.isEmpty {
            value.fileName = ambientBedFileName(bedId: value.bedId, format: .m4a)
        }
        value.durationSeconds = value.durationSeconds.isFinite ? max(value.durationSeconds, 0) : 0
        value.createdAt = value.createdAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// The project's bed library — one SQLite document.
struct ProjectAmbientBedLibraryDocument: Codable, Hashable, Sendable {
    static let documentType = "ambient_beds"
    static let currentSchemaVersion = "litscenes.ambient_beds.v1"

    var schemaVersion: String = currentSchemaVersion
    var projectId: String = ""
    var beds: [AmbientBedRecord] = []

    static func empty(projectId: String) -> ProjectAmbientBedLibraryDocument {
        ProjectAmbientBedLibraryDocument(projectId: projectId)
    }

    init(
        schemaVersion: String = ProjectAmbientBedLibraryDocument.currentSchemaVersion,
        projectId: String = "",
        beds: [AmbientBedRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.beds = beds
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case beds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        beds = ((try? container.decodeIfPresent([AmbientBedRecord].self, forKey: .beds)) ?? nil) ?? []
    }

    func bed(_ bedId: String) -> AmbientBedRecord? {
        beds.first { $0.bedId == bedId }
    }

    /// Replace-by-id upsert. The replaced record's `createdAt` survives, as
    /// does its `displayName` when the incoming one is empty — a user rename
    /// outlives re-baking the same spec.
    func upserting(_ record: AmbientBedRecord) -> ProjectAmbientBedLibraryDocument {
        var incoming = record.normalized()
        guard !incoming.bedId.isEmpty else { return self }
        if let existing = bed(incoming.bedId) {
            if incoming.displayName.isEmpty { incoming.displayName = existing.displayName }
            if !existing.createdAt.isEmpty { incoming.createdAt = existing.createdAt }
        }
        var value = self
        value.beds.removeAll { $0.bedId == incoming.bedId }
        value.beds.append(incoming)
        return value.normalized()
    }

    func removing(bedId: String) -> ProjectAmbientBedLibraryDocument {
        var value = self
        value.beds.removeAll { $0.bedId == bedId }
        return value.normalized()
    }

    func renaming(bedId: String, displayName: String, now: String) -> ProjectAmbientBedLibraryDocument {
        var value = self
        value.beds = value.beds.map { record in
            guard record.bedId == bedId else { return record }
            var renamed = record
            renamed.displayName = displayName.trimmed
            renamed.updatedAt = now
            return renamed
        }
        return value.normalized()
    }

    func normalized() -> ProjectAmbientBedLibraryDocument {
        var value = self
        value.schemaVersion = Self.currentSchemaVersion
        value.projectId = value.projectId.trimmed
        var seen: Set<String> = []
        value.beds = value.beds
            .map { $0.normalized() }
            .filter { !$0.bedId.isEmpty && seen.insert($0.bedId).inserted }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.bedId < rhs.bedId }
                return lhs.createdAt < rhs.createdAt
            }
        return value
    }
}

/// "432.00 Hz · warm drift" — the tuned frequency plus up to two filter
/// descriptors at amount ≥ 0.4, strongest first; a bare band reads "pure band".
func ambientBedAutoName(spec: AmbientBedSpec) -> String {
    let normalized = spec.normalized()
    let descriptors: [(String, Double)] = [
        ("warm", normalized.warmth),
        ("drift", normalized.drift),
        ("crackle", normalized.crackle),
        ("wash", normalized.wash)
    ]
    let active = descriptors
        .filter { $0.1 >= 0.4 }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
            return lhs.1 > rhs.1
        }
        .prefix(2)
        .map(\.0)
    let character = active.isEmpty ? "pure band" : active.joined(separator: " ")
    return String(format: "%.2f Hz · %@", normalized.tunerHz, character)
}

// MARK: - Loop math

/// Chunk plan for tiling a bed under a timeline: full repeats then one clamped
/// partial. Sums exactly to `targetSeconds`; empty when either duration is not
/// positive. Shared by the composition insert and the lane-row waveform tiling
/// so what renders is what plays.
func ambientBedLoopChunkSeconds(bedSeconds: Double, targetSeconds: Double) -> [Double] {
    guard bedSeconds.isFinite, targetSeconds.isFinite, bedSeconds > 0, targetSeconds > 0 else { return [] }
    var chunks: [Double] = []
    var remaining = targetSeconds
    while remaining > bedSeconds {
        chunks.append(bedSeconds)
        remaining -= bedSeconds
    }
    if remaining > 1e-9 {
        chunks.append(min(remaining, bedSeconds))
    }
    return chunks
}

// MARK: - Tuner metrics + snapping

/// Tunables for the tuner instrument (the `lensReframeSnappedRotation` shape:
/// pure functions over named constants, unit-tested without UI).
enum AmbientTunerMetrics {
    static let minHz: Double = AmbientBedSpec.tunerHzRange.lowerBound
    static let maxHz: Double = AmbientBedSpec.tunerHzRange.upperBound
    static let displayQuantumHz: Double = AmbientBedSpec.tunerQuantumHz
    static let fallbackHz: Double = 432
    /// Engraved detent stations: round ruler numbers plus musical anchors
    /// (A₄ 432/440, "healing" 528, octaves of A and C).
    static let detentsHz: [Double] = [
        40, 50, 55, 60, 80, 100, 110, 125, 160, 200, 220, 250, 320, 400, 432, 440,
        500, 528, 640, 800, 880, 1_000, 1_200, 1_600, 2_000, 2_500, 3_200, 4_000,
        5_000, 6_400, 8_000
    ]
    /// Magnetic capture half-band, in log space (~0.4% of frequency).
    static let magneticSnapLogRatio: Double = 0.004
    static let stepPlainHz: Double = 1.0
    static let stepFineHz: Double = 0.1
    static let stepHairHz: Double = 0.01
    static let durationChoicesSeconds: [Double] = [30, 60, 120]
    static let defaultAttachVolume: Double = 0.35
}

/// Log mapping from Hz to a 0…1 ruler fraction; both directions clamp.
func ambientTunerRulerFraction(forHz hz: Double) -> Double {
    let clamped = min(max(hz.isFinite ? hz : AmbientTunerMetrics.fallbackHz, AmbientTunerMetrics.minHz), AmbientTunerMetrics.maxHz)
    return log(clamped / AmbientTunerMetrics.minHz) / log(AmbientTunerMetrics.maxHz / AmbientTunerMetrics.minHz)
}

func ambientTunerHz(atRulerFraction fraction: Double) -> Double {
    let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
    return AmbientTunerMetrics.minHz * pow(AmbientTunerMetrics.maxHz / AmbientTunerMetrics.minHz, clamped)
}

/// Interactive snap: Shift quantizes to the nearest detent; otherwise a value
/// inside a detent's magnetic log band lands on it; otherwise it quantizes to
/// the display quantum. Always clamped; non-finite input falls back to 432.
func ambientTunerSnappedHz(rawHz: Double, shiftDown: Bool) -> Double {
    guard rawHz.isFinite else { return AmbientTunerMetrics.fallbackHz }
    let clamped = min(max(rawHz, AmbientTunerMetrics.minHz), AmbientTunerMetrics.maxHz)
    let nearestDetent = AmbientTunerMetrics.detentsHz.min {
        abs(log($0 / clamped)) < abs(log($1 / clamped))
    }
    if shiftDown, let nearestDetent {
        return nearestDetent
    }
    if let nearestDetent, abs(log(nearestDetent / clamped)) <= AmbientTunerMetrics.magneticSnapLogRatio {
        return nearestDetent
    }
    return (clamped * 100).rounded() / 100
}

/// Arrow-key stepping, quantized to the display quantum and clamped.
func ambientTunerSteppedHz(fromHz hz: Double, direction: Int, stepHz: Double) -> Double {
    let base = hz.isFinite ? hz : AmbientTunerMetrics.fallbackHz
    let step = stepHz.isFinite && stepHz > 0 ? stepHz : AmbientTunerMetrics.stepPlainHz
    let moved = base + Double(direction.signum()) * step
    let clamped = min(max(moved, AmbientTunerMetrics.minHz), AmbientTunerMetrics.maxHz)
    return (clamped * 100).rounded() / 100
}

/// ⇧←/→: the previous/next detent strictly beyond the current value.
func ambientTunerNextDetentHz(fromHz hz: Double, direction: Int) -> Double {
    let base = hz.isFinite ? hz : AmbientTunerMetrics.fallbackHz
    if direction >= 0 {
        return AmbientTunerMetrics.detentsHz.first { $0 > base + 1e-9 } ?? AmbientTunerMetrics.maxHz
    }
    return AmbientTunerMetrics.detentsHz.last { $0 < base - 1e-9 } ?? AmbientTunerMetrics.minHz
}

/// WIDTH slider mapping: 0…1 fraction ↔ physical band width in octaves,
/// exponential so the narrow end gets the fine travel.
func ambientTunerBandwidthOctaves(atWidthFraction fraction: Double) -> Double {
    let clamped = min(max(fraction.isFinite ? fraction : 0.5, 0), 1)
    let range = AmbientBedSpec.bandwidthOctavesRange
    return range.lowerBound * pow(range.upperBound / range.lowerBound, clamped)
}

func ambientTunerWidthFraction(forBandwidthOctaves octaves: Double) -> Double {
    let range = AmbientBedSpec.bandwidthOctavesRange
    let clamped = min(max(octaves.isFinite ? octaves : range.lowerBound, range.lowerBound), range.upperBound)
    return log(clamped / range.lowerBound) / log(range.upperBound / range.lowerBound)
}
