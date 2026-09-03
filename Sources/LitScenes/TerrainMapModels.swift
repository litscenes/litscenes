import CoreGraphics
import Foundation

/// A roster place pinned onto the project's terrain map. One pin per place —
/// the pin is keyed by ProjectPlace.placeId, so the scene tether rides the
/// existing frame → area → placeId spine with no new scene-side edges.
/// Coordinates are normalized (0–1, top-left origin) against the CURRENT map
/// canvas; every growth pass remaps them through the revision's prior-content
/// rect so a pin keeps naming the same spot of the world.
struct TerrainMapPin: Codable, Hashable, Identifiable, Sendable {
    var placeId: String
    var x: Double = 0.5
    var y: Double = 0.5
    /// Normalized extents of the region the pin claims — the crop that rides
    /// as a "world map region" reference when this place's frames render.
    var regionWidth: Double = TerrainMapPin.defaultRegionExtent
    var regionHeight: Double = TerrainMapPin.defaultRegionExtent
    /// Operator note carried into the region reference's descriptor
    /// ("coastal cliffs on the northwest shore").
    var descriptor: String = ""
    var updatedAt: String = DateFormats.now()

    static let defaultRegionExtent = 0.15
    static let minimumRegionExtent = 0.02

    var id: String { placeId }

    func normalized() -> TerrainMapPin {
        var value = self
        value.placeId = value.placeId.trimmed
        value.x = min(1, max(0, value.x))
        value.y = min(1, max(0, value.y))
        value.regionWidth = min(1, max(Self.minimumRegionExtent, value.regionWidth))
        value.regionHeight = min(1, max(Self.minimumRegionExtent, value.regionHeight))
        value.descriptor = value.descriptor.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case placeId
        case x
        case y
        case regionWidth
        case regionHeight
        case descriptor
        case updatedAt
    }

    init(
        placeId: String,
        x: Double = 0.5,
        y: Double = 0.5,
        regionWidth: Double = TerrainMapPin.defaultRegionExtent,
        regionHeight: Double = TerrainMapPin.defaultRegionExtent,
        descriptor: String = "",
        updatedAt: String = DateFormats.now()
    ) {
        self.placeId = placeId
        self.x = x
        self.y = y
        self.regionWidth = regionWidth
        self.regionHeight = regionHeight
        self.descriptor = descriptor
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placeId = try container.decodeIfPresent(String.self, forKey: .placeId) ?? ""
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        regionWidth = try container.decodeIfPresent(Double.self, forKey: .regionWidth) ?? Self.defaultRegionExtent
        regionHeight = try container.decodeIfPresent(Double.self, forKey: .regionHeight) ?? Self.defaultRegionExtent
        descriptor = try container.decodeIfPresent(String.self, forKey: .descriptor) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        self = normalized()
    }
}

/// One committed change to the map canvas. `priorContentRect*` records where
/// the PREVIOUS canvas's content sits inside this revision's canvas — the pin
/// remap record — and `pinsSnapshot` holds the pins as they stood when this
/// revision committed, so a one-step revert restores geometry losslessly.
struct TerrainMapRevision: Codable, Hashable, Identifiable, Sendable {
    static let seedOperation = "seed"
    static let growOperation = "grow"

    var revisionId: String
    var mediaId: String = ""
    var operation: String = TerrainMapRevision.growOperation
    /// TerrainGrowthDirection raw value; empty for seeds.
    var direction: String = ""
    var canvasWidth: Int = 0
    var canvasHeight: Int = 0
    var priorContentRectX: Double = 0
    var priorContentRectY: Double = 0
    var priorContentRectWidth: Double = 1
    var priorContentRectHeight: Double = 1
    var pinsSnapshot: [TerrainMapPin] = []
    var at: String = DateFormats.now()

    var id: String { revisionId }

    /// Top-left-origin normalized rect in this revision's canvas.
    var priorContentRect: CGRect {
        CGRect(
            x: priorContentRectX,
            y: priorContentRectY,
            width: priorContentRectWidth,
            height: priorContentRectHeight
        )
    }

    func normalized() -> TerrainMapRevision {
        var value = self
        value.revisionId = value.revisionId.trimmed
        if value.revisionId.isEmpty {
            value.revisionId = "terrainrev_\(shortHash("\(value.mediaId):\(value.at)", length: 12))"
        }
        value.mediaId = value.mediaId.trimmed
        value.operation = value.operation.trimmed
        value.direction = value.direction.trimmed
        value.canvasWidth = max(0, value.canvasWidth)
        value.canvasHeight = max(0, value.canvasHeight)
        value.pinsSnapshot = value.pinsSnapshot.map { $0.normalized() }
        value.at = value.at.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case revisionId
        case mediaId
        case operation
        case direction
        case canvasWidth
        case canvasHeight
        case priorContentRectX
        case priorContentRectY
        case priorContentRectWidth
        case priorContentRectHeight
        case pinsSnapshot
        case at
    }

    init(
        revisionId: String,
        mediaId: String = "",
        operation: String = TerrainMapRevision.growOperation,
        direction: String = "",
        canvasWidth: Int = 0,
        canvasHeight: Int = 0,
        priorContentRectX: Double = 0,
        priorContentRectY: Double = 0,
        priorContentRectWidth: Double = 1,
        priorContentRectHeight: Double = 1,
        pinsSnapshot: [TerrainMapPin] = [],
        at: String = DateFormats.now()
    ) {
        self.revisionId = revisionId
        self.mediaId = mediaId
        self.operation = operation
        self.direction = direction
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.priorContentRectX = priorContentRectX
        self.priorContentRectY = priorContentRectY
        self.priorContentRectWidth = priorContentRectWidth
        self.priorContentRectHeight = priorContentRectHeight
        self.pinsSnapshot = pinsSnapshot
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revisionId = try container.decodeIfPresent(String.self, forKey: .revisionId) ?? ""
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId) ?? ""
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? Self.growOperation
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        canvasWidth = try container.decodeIfPresent(Int.self, forKey: .canvasWidth) ?? 0
        canvasHeight = try container.decodeIfPresent(Int.self, forKey: .canvasHeight) ?? 0
        priorContentRectX = try container.decodeIfPresent(Double.self, forKey: .priorContentRectX) ?? 0
        priorContentRectY = try container.decodeIfPresent(Double.self, forKey: .priorContentRectY) ?? 0
        priorContentRectWidth = try container.decodeIfPresent(Double.self, forKey: .priorContentRectWidth) ?? 1
        priorContentRectHeight = try container.decodeIfPresent(Double.self, forKey: .priorContentRectHeight) ?? 1
        pinsSnapshot = try container.decodeIfPresent([TerrainMapPin].self, forKey: .pinsSnapshot) ?? []
        at = try container.decodeIfPresent(String.self, forKey: .at) ?? DateFormats.now()
        self = normalized()
    }
}

/// The project's terrain map, persisted as one project document (no table
/// change). The canvas itself is archived media (`terrain_map` derivative
/// kind); this document holds the pointer, the pins, and the growth history.
/// NEVER bump the schema version — the loader gates on exact equality, so
/// evolution is additive fields riding the tolerant decoder at v0.1.
struct TerrainMapDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.terrain_map.v0.1"
    static let documentType = "terrain_map"
    static let maxRevisions = 20

    var schemaVersion: String = TerrainMapDocument.schemaVersion
    var projectId: String = ""
    /// MediaItemRecord.mediaId of the current map canvas; empty when unseeded.
    var currentMediaId: String = ""
    var canvasWidth: Int = 0
    var canvasHeight: Int = 0
    /// Persistent operator continuation body appended to the fixed growth
    /// preamble on every grow pass.
    var growthPrompt: String = ""
    var pins: [TerrainMapPin] = []
    /// Newest-last; capped in normalized(). Older canvases stay archived in
    /// the Library regardless.
    var revisions: [TerrainMapRevision] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> TerrainMapDocument {
        TerrainMapDocument(projectId: projectId)
    }

    var isSeeded: Bool {
        !currentMediaId.trimmed.isEmpty && canvasWidth > 0 && canvasHeight > 0
    }

    func pin(forPlaceId placeId: String) -> TerrainMapPin? {
        pins.first { $0.placeId == placeId }
    }

    var latestRevision: TerrainMapRevision? { revisions.last }

    func normalized() -> TerrainMapDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        value.currentMediaId = value.currentMediaId.trimmed
        value.canvasWidth = max(0, value.canvasWidth)
        value.canvasHeight = max(0, value.canvasHeight)
        value.growthPrompt = value.growthPrompt.trimmed
        var seenPlaceIds: Set<String> = []
        value.pins = value.pins
            .map { $0.normalized() }
            .filter { pin in
                guard !pin.placeId.isEmpty, !seenPlaceIds.contains(pin.placeId) else { return false }
                seenPlaceIds.insert(pin.placeId)
                return true
            }
        value.revisions = Array(value.revisions.map { $0.normalized() }.suffix(Self.maxRevisions))
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case currentMediaId
        case canvasWidth
        case canvasHeight
        case growthPrompt
        case pins
        case revisions
        case updatedAt
    }

    init(
        schemaVersion: String = TerrainMapDocument.schemaVersion,
        projectId: String = "",
        currentMediaId: String = "",
        canvasWidth: Int = 0,
        canvasHeight: Int = 0,
        growthPrompt: String = "",
        pins: [TerrainMapPin] = [],
        revisions: [TerrainMapRevision] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.currentMediaId = currentMediaId
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.growthPrompt = growthPrompt
        self.pins = pins
        self.revisions = revisions
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        currentMediaId = try container.decodeIfPresent(String.self, forKey: .currentMediaId) ?? ""
        canvasWidth = try container.decodeIfPresent(Int.self, forKey: .canvasWidth) ?? 0
        canvasHeight = try container.decodeIfPresent(Int.self, forKey: .canvasHeight) ?? 0
        growthPrompt = try container.decodeIfPresent(String.self, forKey: .growthPrompt) ?? ""
        pins = try container.decodeIfPresent([TerrainMapPin].self, forKey: .pins) ?? []
        revisions = try container.decodeIfPresent([TerrainMapRevision].self, forKey: .revisions) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self = normalized()
    }
}

/// Fixed provider-boundary prompt fragments for the terrain map. Like
/// LensZoomOutPrompt, these live at the client boundary — outside the operator-
/// editable growth prompt — so the top-down framing survives edits. gpt-image
/// reads negations as content vocabulary, so everything is stated affirmatively.
enum TerrainMapPrompt {
    static let openAIGrowthPreamble = """
    Top-down orthographic terrain map: keep the supplied map exactly as it is and fill the transparent area with more of the same world seen straight down — continue coastlines, rivers, roads, and biomes across the boundary at the same scale, palette, and rendering style. The view stays flat and map-like everywhere.
    """

    static let seedPreamble = """
    Top-down orthographic terrain map of a world, seen straight down like a hand-drawn atlas plate: coastlines, rivers, roads, forests, mountains, and settlements laid out flat and map-like, with one consistent palette and rendering style across the whole sheet.
    """

    static func openAIWirePrompt(operatorPrompt: String) -> String {
        let trimmed = operatorPrompt.trimmed
        return trimmed.isEmpty ? openAIGrowthPreamble : openAIGrowthPreamble + "\n\n" + trimmed
    }

    static func seedWirePrompt(operatorPrompt: String) -> String {
        let trimmed = operatorPrompt.trimmed
        return trimmed.isEmpty ? seedPreamble : seedPreamble + "\n\n" + trimmed
    }

    /// The plain-English descriptor riding a place's map-region crop, telling
    /// the model the attachment is geography, not scene content — the camera-
    /// map descriptor precedent.
    static func regionReferenceDescriptor(placeName: String, descriptor: String) -> String {
        let name = placeName.trimmed
        let note = descriptor.trimmed
        var text = "TOP-DOWN WORLD MAP region — the area of the world around"
            + (name.isEmpty ? " this place" : " \(name)")
            + ", seen from directly above."
        if !note.isEmpty {
            text += " \(note)."
        }
        text += " Use it for geography, adjacency, and terrain context; take visual style and scene content from the other references."
        return text
    }
}
