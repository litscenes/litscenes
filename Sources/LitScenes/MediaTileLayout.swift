import CoreGraphics

/// Geometry of a media grid tile's picture area. A thumb never crops: the tile
/// follows the image's own shape inside a band, and beyond the band the image
/// letterboxes on the tile matte instead of losing its edges.
struct MediaTileAspect: Equatable {
    /// Width divided by height of the tile's picture area.
    var tileAspect: CGFloat
    /// True when the image sits on the matte because its shape falls outside the band.
    var letterboxes: Bool
}

enum MediaTileLayout {
    /// Narrowest tile the grid grows to (2:3 portrait).
    static let minimumTileAspect: CGFloat = 2.0 / 3.0
    /// Widest tile the grid grows to (16:9 landscape).
    static let maximumTileAspect: CGFloat = 16.0 / 9.0
    /// Tile shape when the image's own dimensions are unknown.
    static let fallbackTileAspect: CGFloat = 4.0 / 3.0

    /// Within the band the tile takes the image's own aspect and the picture fills it
    /// edge to edge; outside the band the tile clamps to the nearer band edge and the
    /// picture letterboxes inside it. Unknown dimensions fall back to 4:3 on the matte.
    static func aspect(width: Int, height: Int) -> MediaTileAspect {
        guard width > 0, height > 0 else {
            return MediaTileAspect(tileAspect: fallbackTileAspect, letterboxes: true)
        }
        let imageAspect = CGFloat(width) / CGFloat(height)
        if imageAspect < minimumTileAspect {
            return MediaTileAspect(tileAspect: minimumTileAspect, letterboxes: true)
        }
        if imageAspect > maximumTileAspect {
            return MediaTileAspect(tileAspect: maximumTileAspect, letterboxes: true)
        }
        return MediaTileAspect(tileAspect: imageAspect, letterboxes: false)
    }
}

/// The tile badge speaks only when a file needs attention. Managed is the
/// default state of every project file and Linked is discoverable from the Use
/// menu and the detail card, so neither earns a badge; Missing is actionable.
func mediaTileStorageBadgeText(_ status: MediaStorageStatus) -> String? {
    switch status {
    case .managed, .linked:
        return nil
    case .missing:
        return status.label
    }
}
