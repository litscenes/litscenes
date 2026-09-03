import CoreGraphics
import Foundation

/// Per-channel affine exposure match that pulls a provider's generated Zoom Out
/// perimeter toward the exact source. The provider's own rendition of the
/// source region is the overlap sample: whatever exposure drift it shows there
/// is the drift its perimeter carries too. The correction applies to the
/// generated layer only — the byte-exact source re-stamp then covers the
/// overlap, so no source pixel is ever modified.
enum LensZoomOutColorMatch {
    struct ChannelAffine: Equatable {
        var gains: [Double]
        var biases: [Double]
    }

    struct PerimeterMatch {
        /// Corrected generated layer; nil when no correction should be drawn.
        var image: CGImage?
        /// Trace detail: "identity", a gain/bias summary, or a skip reason.
        var detail: String
    }

    static let gainRange = 0.6...1.6
    static let biasRange = -48.0...48.0

    static func harmonizedPerimeter(
        generated: CGImage,
        providerSourceRegion: CGRect,
        original: CGImage
    ) -> PerimeterMatch {
        guard let providerStats = channelStats(of: generated, in: providerSourceRegion) else {
            return PerimeterMatch(image: nil, detail: "stats_unavailable")
        }
        guard let referenceStats = channelStats(of: original) else {
            return PerimeterMatch(image: nil, detail: "stats_unavailable")
        }
        let correction = affine(matching: providerStats, to: referenceStats)
        if isIdentity(correction) {
            return PerimeterMatch(image: nil, detail: "identity")
        }
        guard let corrected = apply(correction, to: generated) else {
            return PerimeterMatch(image: nil, detail: "apply_failed")
        }
        let gains = correction.gains.map { String(format: "%.2f", $0) }.joined(separator: "/")
        let biases = correction.biases.map { String(format: "%.0f", $0) }.joined(separator: "/")
        return PerimeterMatch(image: corrected, detail: "gain \(gains) bias \(biases)")
    }

    /// Mean and standard deviation per RGB channel, sampled from a downscaled
    /// copy (longest side ≤ 64) of the image or of `region` (top-left pixel
    /// coordinates) within it.
    static func channelStats(of image: CGImage, in region: CGRect? = nil) -> (mean: [Double], deviation: [Double])? {
        var sample = image
        if let region {
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let bounded = region.integral.intersection(bounds)
            guard bounded.width >= 4, bounded.height >= 4,
                  let cropped = image.cropping(to: bounded) else {
                return nil
            }
            sample = cropped
        }
        let longestSide = max(sample.width, sample.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, 64.0 / Double(longestSide))
        let width = max(1, Int((Double(sample.width) * scale).rounded()))
        let height = max(1, Int((Double(sample.height) * scale).rounded()))
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
        context.interpolationQuality = .medium
        context.draw(sample, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let rowBytes = context.bytesPerRow
        let pointer = data.assumingMemoryBound(to: UInt8.self)
        var sums = [Double](repeating: 0, count: 3)
        var squareSums = [Double](repeating: 0, count: 3)
        for y in 0..<height {
            var offset = y * rowBytes
            for _ in 0..<width {
                for channel in 0..<3 {
                    let value = Double(pointer[offset + channel])
                    sums[channel] += value
                    squareSums[channel] += value * value
                }
                offset += 4
            }
        }
        let count = Double(width * height)
        guard count > 0 else { return nil }
        var means = [Double](repeating: 0, count: 3)
        var deviations = [Double](repeating: 0, count: 3)
        for channel in 0..<3 {
            let mean = sums[channel] / count
            means[channel] = mean
            deviations[channel] = (squareSums[channel] / count - mean * mean).squareRoot()
        }
        return (means, deviations)
    }

    static func affine(
        matching provider: (mean: [Double], deviation: [Double]),
        to reference: (mean: [Double], deviation: [Double])
    ) -> ChannelAffine {
        var gains = [Double]()
        var biases = [Double]()
        for channel in 0..<3 {
            let rawGain = provider.deviation[channel] > 1
                ? reference.deviation[channel] / provider.deviation[channel]
                : 1
            let gain = min(max(rawGain, gainRange.lowerBound), gainRange.upperBound)
            let rawBias = reference.mean[channel] - gain * provider.mean[channel]
            let bias = min(max(rawBias, biasRange.lowerBound), biasRange.upperBound)
            gains.append(gain)
            biases.append(bias)
        }
        return ChannelAffine(gains: gains, biases: biases)
    }

    static func isIdentity(_ affine: ChannelAffine) -> Bool {
        affine.gains.allSatisfy { abs($0 - 1) <= 0.02 }
            && affine.biases.allSatisfy { abs($0) <= 1 }
    }

    static func apply(_ affine: ChannelAffine, to image: CGImage) -> CGImage? {
        guard affine.gains.count == 3, affine.biases.count == 3 else { return nil }
        var tables = [[UInt8]]()
        for channel in 0..<3 {
            var table = [UInt8](repeating: 0, count: 256)
            for value in 0..<256 {
                let mapped = affine.gains[channel] * Double(value) + affine.biases[channel]
                table[value] = UInt8(min(255, max(0, mapped.rounded())))
            }
            tables.append(table)
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let rowBytes = context.bytesPerRow
        let pointer = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<image.height {
            var offset = y * rowBytes
            for _ in 0..<image.width {
                pointer[offset] = tables[0][Int(pointer[offset])]
                pointer[offset + 1] = tables[1][Int(pointer[offset + 1])]
                pointer[offset + 2] = tables[2][Int(pointer[offset + 2])]
                offset += 4
            }
        }
        return context.makeImage()
    }
}
