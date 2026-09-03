import CoreGraphics
import Foundation
import Testing
@testable import LitScenes

private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    draw(context)
    return context.makeImage()
}

private func solidImage(width: Int, height: Int, gray: CGFloat) -> CGImage? {
    makeImage(width: width, height: height) { context in
        context.setFillColor(CGColor(srgbRed: gray / 255, green: gray / 255, blue: gray / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

private func twoToneImage(width: Int, height: Int, left: CGFloat, right: CGFloat) -> CGImage? {
    makeImage(width: width, height: height) { context in
        context.setFillColor(CGColor(srgbRed: left / 255, green: left / 255, blue: left / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: right / 255, green: right / 255, blue: right / 255, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    }
}

@Test func colorMatchBiasMapsSolidRegionsWithClampedBias() throws {
    // Solid colors have zero deviation → gain stays 1 and the mean offset
    // rides in the bias, clamped to the correction band.
    let generated = try #require(solidImage(width: 64, height: 64, gray: 100))
    let original = try #require(solidImage(width: 64, height: 64, gray: 150))
    let match = LensZoomOutColorMatch.harmonizedPerimeter(
        generated: generated,
        providerSourceRegion: CGRect(x: 8, y: 8, width: 48, height: 48),
        original: original
    )
    let corrected = try #require(match.image)
    #expect(match.detail.hasPrefix("gain 1.00/1.00/1.00"))
    #expect(match.detail.contains("bias 48/48/48"))
    let stats = try #require(LensZoomOutColorMatch.channelStats(of: corrected))
    #expect(abs(stats.mean[0] - 148) <= 1)
    #expect(abs(stats.mean[1] - 148) <= 1)
    #expect(abs(stats.mean[2] - 148) <= 1)
}

@Test func colorMatchIdentityIsSkipped() throws {
    let generated = try #require(twoToneImage(width: 64, height: 64, left: 90, right: 190))
    let match = LensZoomOutColorMatch.harmonizedPerimeter(
        generated: generated,
        providerSourceRegion: CGRect(x: 0, y: 0, width: 64, height: 64),
        original: generated
    )
    #expect(match.image == nil)
    #expect(match.detail == "identity")
}

@Test func colorMatchAffineMatchesMeansAndClampsGain() throws {
    // Same spread, shifted mean → gain 1, bias = the shift.
    let provider = (mean: [150.0, 150.0, 150.0], deviation: [50.0, 50.0, 50.0])
    let reference = (mean: [170.0, 170.0, 170.0], deviation: [50.0, 50.0, 50.0])
    let shifted = LensZoomOutColorMatch.affine(matching: provider, to: reference)
    #expect(shifted.gains.allSatisfy { abs($0 - 1) < 0.0001 })
    #expect(shifted.biases.allSatisfy { abs($0 - 20) < 0.0001 })

    // A wildly larger reference spread clamps at the gain band's top; the
    // resulting bias clamps too.
    let flat = (mean: [150.0, 150.0, 150.0], deviation: [10.0, 10.0, 10.0])
    let wide = (mean: [150.0, 150.0, 150.0], deviation: [100.0, 100.0, 100.0])
    let clamped = LensZoomOutColorMatch.affine(matching: flat, to: wide)
    #expect(clamped.gains.allSatisfy { $0 == LensZoomOutColorMatch.gainRange.upperBound })
    #expect(clamped.biases.allSatisfy { $0 == LensZoomOutColorMatch.biasRange.lowerBound })

    // Near-zero provider deviation never divides: gain stays 1.
    let degenerate = LensZoomOutColorMatch.affine(
        matching: (mean: [100.0, 100.0, 100.0], deviation: [0.0, 0.0, 0.0]),
        to: wide
    )
    #expect(degenerate.gains.allSatisfy { $0 == 1 })
}

@Test func colorMatchApplyUsesPerChannelTables() throws {
    let generated = try #require(twoToneImage(width: 64, height: 64, left: 100, right: 200))
    let affine = LensZoomOutColorMatch.ChannelAffine(
        gains: [1, 1, 1],
        biases: [20, 20, 20]
    )
    let corrected = try #require(LensZoomOutColorMatch.apply(affine, to: generated))
    let leftStats = try #require(LensZoomOutColorMatch.channelStats(
        of: corrected,
        in: CGRect(x: 0, y: 0, width: 24, height: 64)
    ))
    let rightStats = try #require(LensZoomOutColorMatch.channelStats(
        of: corrected,
        in: CGRect(x: 40, y: 0, width: 24, height: 64)
    ))
    #expect(abs(leftStats.mean[0] - 120) <= 1.5)
    #expect(abs(rightStats.mean[0] - 220) <= 1.5)
}
