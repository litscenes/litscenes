import CoreGraphics
import Foundation
import Vision

struct FrameSignature: Codable, Hashable {
    var sha256: String
    var perceptualHash: UInt64
    var ocrFingerprint: String
}

struct DiffDecision: Codable, Hashable {
    var kind: DiffDecisionKind
    var shouldAnalyze: Bool
    var score: Int
    var reason: String
}

struct DiffEngine {
    var tinyChangeThreshold: Int = 3

    func signature(image: CGImage, data: Data) -> FrameSignature {
        FrameSignature(
            sha256: sha256Hex(data),
            perceptualHash: perceptualHash(image),
            ocrFingerprint: ocrFingerprint(image)
        )
    }

    func decide(
        current: FrameSignature,
        previousAnalyzed: FrameSignature?,
        secondsSinceLastAnalysis: TimeInterval,
        heartbeatSeconds: TimeInterval
    ) -> DiffDecision {
        guard let previous = previousAnalyzed else {
            return DiffDecision(kind: .firstFrame, shouldAnalyze: true, score: 64, reason: "first capture in session")
        }
        if current.sha256 == previous.sha256 {
            return DiffDecision(kind: .exactDuplicate, shouldAnalyze: false, score: 0, reason: "exact screenshot hash match")
        }

        let score = hammingDistance(current.perceptualHash, previous.perceptualHash)
        let ocrChanged = current.ocrFingerprint != previous.ocrFingerprint
        if ocrChanged {
            return DiffDecision(kind: .ocrChanged, shouldAnalyze: true, score: score, reason: "recognized screen text changed")
        }
        if score <= tinyChangeThreshold {
            if secondsSinceLastAnalysis >= heartbeatSeconds {
                return DiffDecision(kind: .heartbeat, shouldAnalyze: true, score: score, reason: "heartbeat after low-change interval")
            }
            return DiffDecision(kind: .cursorOnlyOrTinyChange, shouldAnalyze: false, score: score, reason: "tiny visual delta with unchanged OCR")
        }
        return DiffDecision(kind: .visualChanged, shouldAnalyze: true, score: score, reason: "meaningful visual delta")
    }

    func decideVisualOnly(
        current: FrameSignature,
        previousAnalyzed: FrameSignature?,
        secondsSinceLastAnalysis: TimeInterval,
        heartbeatSeconds: TimeInterval
    ) -> DiffDecision {
        guard let previous = previousAnalyzed else {
            return DiffDecision(kind: .firstFrame, shouldAnalyze: true, score: 64, reason: "first visual frame in session")
        }
        if current.sha256 == previous.sha256 {
            return DiffDecision(kind: .exactDuplicate, shouldAnalyze: false, score: 0, reason: "exact screenshot hash match")
        }

        let score = hammingDistance(current.perceptualHash, previous.perceptualHash)
        if score <= tinyChangeThreshold {
            if secondsSinceLastAnalysis >= heartbeatSeconds {
                return DiffDecision(kind: .heartbeat, shouldAnalyze: false, score: score, reason: "visual heartbeat without new imagery")
            }
            return DiffDecision(kind: .cursorOnlyOrTinyChange, shouldAnalyze: false, score: score, reason: "tiny visual delta ignored by aesthetic watch")
        }
        return DiffDecision(kind: .visualChanged, shouldAnalyze: true, score: score, reason: "new screen imagery detected")
    }

    func hammingDistance(_ left: UInt64, _ right: UInt64) -> Int {
        (left ^ right).nonzeroBitCount
    }

    func perceptualHash(_ image: CGImage) -> UInt64 {
        let width = 16
        let height = 16
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var lumas: [UInt8] = []
        lumas.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Double(bytes[offset])
                let g = Double(bytes[offset + 1])
                let b = Double(bytes[offset + 2])
                let luma = UInt8(max(0, min(255, Int(0.2126 * r + 0.7152 * g + 0.0722 * b))))
                lumas.append(luma)
            }
        }
        let avg = lumas.reduce(0) { $0 + Int($1) } / max(1, lumas.count)
        var hash: UInt64 = 0
        for (index, luma) in lumas.prefix(64).enumerated() {
            if Int(luma) >= avg {
                hash |= (UInt64(1) << UInt64(index))
            }
        }
        return hash
    }

    func ocrFingerprint(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        let normalized = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return shortHash(normalized, length: 24)
    }
}
