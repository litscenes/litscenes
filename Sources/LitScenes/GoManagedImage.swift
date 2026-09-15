import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Adapts shared image entry points to the account service's quoted image job.
enum GoManagedImage {
    static func generate(prompt: String, instructions: String = "", sources: [OpenAIImageEditSource] = [],
                         size: String, background: String, projectId: String, runId: String,
                         workflowName: String, workflowStep: String, artifactType: String,
                         artifactId: String) async throws -> OpenAIImageGenerationResult {
        guard background != "transparent" else {
            throw GoServiceError(code: "unsupported_background", message: "Transparent image output requires your own OpenAI key. Go creates PNG images with a background.")
        }
        let references = sources.filter { !$0.data.isEmpty }
        guard references.count <= 14 else {
            throw GoServiceError(code: "reference_limit", message: "Go supports up to 14 reference images per image.")
        }
        let canvas = try dimensions(size: size, source: references.first?.data)
        let ratio = aspectRatio(width: canvas.width, height: canvas.height)
        let model = references.isEmpty ? "fal-ai/nano-banana-2" : "fal-ai/nano-banana-2/edit"
        let notes = references.enumerated().map { index, source in
            "Reference \(index + 1): \(source.fileName)" + (source.role.isEmpty ? "" : " (\(source.role))")
        }.joined(separator: "\n")
        let composed = [instructions, prompt, notes].filter { !$0.isEmpty }.joined(separator: "\n\n")
        var input: [String: Any] = ["prompt": composed, "aspect_ratio": ratio, "resolution": "1K", "num_images": 1,
                                    "output_format": "png", "limit_generations": true]
        if !references.isEmpty {
            let parts = ratio.split(separator: ":").compactMap { Int($0) }
            let scale = 2048.0 / Double(max(parts[0], parts[1]))
            input["image_urls"] = try references.map {
                let padded = try fit($0.data, width: Int(Double(parts[0]) * scale), height: Int(Double(parts[1]) * scale))
                return "data:image/png;base64," + padded.base64EncodedString()
            }
        }
        var request = URLRequest(url: URL(string: "https://queue.fal.run/" + model)!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: input)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Key " + GoConnection.marker, forHTTPHeaderField: "Authorization")
        var metadata = InferenceTraceRequestMetadata(provider: "fal", apiFamily: "images", operation: workflowStep,
            projectId: projectId, runId: runId, model: model, requestBodyFormat: "application/json",
            responseBodyFormatHint: "application/json", providerRequestIDHeaderCandidates: ["x-request-id"], captureResponseBody: false)
        metadata.workflowName = workflowName
        metadata.workflowStep = workflowStep
        metadata.traceGroupId = runId
        metadata.artifactType = artifactType
        metadata.artifactId = artifactId
        metadata.requestTextJSON = String(decoding: try GoDocument(["prompt": prompt, "instructions": instructions,
            "size": size, "provider_aspect_ratio": ratio, "output_width": canvas.width, "output_height": canvas.height,
            "image_normalization": "fit and pad without cropping", "reference_count": references.count]).data, as: UTF8.self)
        let submitted = try await TracedHTTPTransport.send(request: request, metadata: metadata)
        let jobId = GoDocument(data: submitted.data).string("request_id")
        let job = try await withTaskCancellationHandler {
            try await GoTransport.wait(jobId)
        } onCancel: {
            Task { _ = try? await GoAPI.call("jobs/" + jobId + "/cancel", method: "POST", body: GoDocument([:])) }
        }
        let local = try await GoOutputStore.shared.persist(job)
        guard let artifact = local.documents("artifacts").first(where: { $0.string("mime_type").hasPrefix("image/") }) else { throw URLError(.badServerResponse) }
        let original = try await GoOutputStore.shared.data(artifact)
        let data = try fit(original, width: canvas.width, height: canvas.height)
        return OpenAIImageGenerationResult(imageData: data, requestId: jobId, traceId: job.string("trace_id"),
                                            model: model, revisedPrompt: composed)
    }

    private static func dimensions(size: String, source: Data?) throws -> (width: Int, height: Int) {
        let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
        let pixels = source.flatMap(imagePixelSize(from:))
        let width = parts.count == 2 ? parts[0] : (pixels?.width ?? 1024)
        let height = parts.count == 2 ? parts[1] : (pixels?.height ?? 1024)
        guard width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 67_108_864 else {
            throw GoServiceError(code: "image_dimensions", message: "Choose an image canvas up to 64 megapixels and 16,384 pixels per side.")
        }
        return (width, height)
    }

    private static func aspectRatio(width: Int, height: Int) -> String {
        let ratios: [(String, Double)] = [("1:1", 1), ("2:3", 2.0/3), ("3:2", 1.5), ("3:4", 0.75),
            ("4:3", 4.0/3), ("4:5", 0.8), ("5:4", 1.25), ("9:16", 9.0/16), ("16:9", 16.0/9), ("21:9", 21.0/9)]
        let target = Double(width) / Double(height)
        return ratios.min { abs(log($0.1 / target)) < abs(log($1.1 / target)) }!.0
    }

    static func fit(_ data: Data, width: Int, height: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 16384] as CFDictionary),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw URLError(.cannotDecodeContentData)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let drawnWidth = Double(image.width) * scale, drawnHeight = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(width) - drawnWidth) / 2, y: (Double(height) - drawnHeight) / 2, width: drawnWidth, height: drawnHeight))
        guard let output = context.makeImage() else { throw URLError(.cannotDecodeContentData) }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw URLError(.cannotDecodeContentData) }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { throw URLError(.cannotDecodeContentData) }
        return bytes as Data
    }
}
