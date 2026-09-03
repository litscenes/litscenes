import Foundation
import Testing
@testable import LitScenes

@Suite("Media tile laws")
struct MediaTileLawsTests {
    @Test("Only a missing file earns a storage badge")
    func storageBadgeSpeaksOnlyForMissing() {
        #expect(mediaTileStorageBadgeText(.managed) == nil)
        #expect(mediaTileStorageBadgeText(.linked) == nil)
        #expect(mediaTileStorageBadgeText(.missing) == "Missing")
    }

    @Test("Images inside the band keep their own aspect without a matte")
    func inBandImagesKeepNativeAspect() {
        let portrait = MediaTileLayout.aspect(width: 2000, height: 3000)
        #expect(abs(portrait.tileAspect - 2.0 / 3.0) < 0.0001)
        #expect(portrait.letterboxes == false)

        let landscape = MediaTileLayout.aspect(width: 1600, height: 1200)
        #expect(abs(landscape.tileAspect - 4.0 / 3.0) < 0.0001)
        #expect(landscape.letterboxes == false)

        let wide = MediaTileLayout.aspect(width: 1920, height: 1080)
        #expect(abs(wide.tileAspect - 16.0 / 9.0) < 0.0001)
        #expect(wide.letterboxes == false)
    }

    @Test("Images beyond the band letterbox at the nearer band edge")
    func outOfBandImagesLetterboxAtBandEdge() {
        let tall = MediaTileLayout.aspect(width: 1080, height: 1920)
        #expect(abs(tall.tileAspect - MediaTileLayout.minimumTileAspect) < 0.0001)
        #expect(tall.letterboxes)

        let panorama = MediaTileLayout.aspect(width: 3000, height: 1000)
        #expect(abs(panorama.tileAspect - MediaTileLayout.maximumTileAspect) < 0.0001)
        #expect(panorama.letterboxes)
    }

    @Test("Unknown dimensions fall back to 4:3 on the matte")
    func unknownDimensionsFallBack() {
        let unknown = MediaTileLayout.aspect(width: 0, height: 0)
        #expect(abs(unknown.tileAspect - MediaTileLayout.fallbackTileAspect) < 0.0001)
        #expect(unknown.letterboxes)
        #expect(MediaTileLayout.aspect(width: -4, height: 3).letterboxes)
    }
}
