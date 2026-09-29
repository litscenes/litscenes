import AppKit
@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PortableSceneFrame: Sendable {
    var id: String
    var title: String
    var sourceURL: URL?
    var isVideo: Bool = false
    var startSeconds: Double = 0
    var endSeconds: Double?
    var skipped: Bool = false
}

struct PortableSceneIdea: Sendable {
    var id: String
    var slug: String
    var kind: String
    var title: String
    var definition: String
    var status: String
}

struct PortableSceneInput: Sendable {
    var projectId: String
    var projectTitle: String
    var sceneId: String
    var sceneTitle: String
    var frames: [PortableSceneFrame]
    var ideas: [PortableSceneIdea]
    var videoURL: URL?
    var videoDuration: Double = 0
    var warnings: [String] = []
}

struct PortableSceneResult: Sendable {
    var directory: URL
    var warnings: [String]
}

/// A local, presentation-only snapshot. No prompts, credentials or source paths
/// enter either manifest. Project context is never promoted to an interpretation.
enum PortableSceneExport {
    static func write(_ input: PortableSceneInput, into parent: URL) async throws -> PortableSceneResult {
        let files = FileManager.default
        let token = UUID().uuidString.lowercased()
        let staging = parent.appendingPathComponent(".preparing-scene-\(token)", isDirectory: true)
        let destination = parent.appendingPathComponent("Scene-\(token)", isDirectory: true)
        try files.createDirectory(at: staging.appendingPathComponent("media"), withIntermediateDirectories: true)
        do {
            var warnings = input.warnings
            let projectId = identity("project", input.projectId)
            let sceneId = identity("scene", input.projectId + ":" + input.sceneId)
            var artifacts: [[String: Any]] = []
            var ordered: [[String: Any]] = []
            var pictures: [(String, CGImage)] = []
            for (index, frame) in input.frames.enumerated() {
                let id = identity("frame", input.projectId + ":" + input.sceneId + ":" + frame.id)
                var entry: [String: Any] = ["id": id, "ordinal": index + 1, "title": frame.title,
                    "kind": frame.isVideo ? "footage" : "frame", "skipped": frame.skipped]
                if frame.isVideo {
                    entry["start_seconds"] = frame.startSeconds
                    if let end = frame.endSeconds { entry["end_seconds"] = end }
                }
                if let source = frame.sourceURL, let image = try? await loadImage(source, video: frame.isVideo, at: frame.startSeconds) {
                    let asset = try writeImage(image, into: staging)
                    entry["image"] = asset
                    artifacts.append(work(id: id, projectId: projectId, projectTitle: input.projectTitle,
                        title: frame.title, kind: "frame", poster: asset, full: asset))
                    if !frame.skipped { pictures.append((id, image)) }
                } else {
                    entry["omission"] = "Saved media is unavailable."
                    warnings.append("Frame \(index + 1): saved media is unavailable.")
                }
                ordered.append(entry)
            }
            if pictures.isEmpty { warnings.append("No included frames were available for the composite.") }
            if pictures.count > 16 { warnings.append("The composite shows the first 16 included frames; the folder contains every available frame.") }
            let composite = try writeImage(try contactSheet(Array(pictures.prefix(16)).map(\.1)), into: staging)
            var video: [String: Any]?
            if let source = input.videoURL {
                do {
                    let hash = try fileHash(source)
                    let name = "media/\(hash).mp4"
                    let copied = staging.appendingPathComponent(name)
                    try files.copyItem(at: source, to: copied)
                    guard try fileHash(copied) == hash else { throw CocoaError(.fileReadCorruptFile) }
                    let asset = AVURLAsset(url: copied)
                    let audio = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
                    let size = try await track.load(.naturalSize)
                    video = ["src": name, "sha256": hash, "bytes": try fileSize(copied), "mime": "video/mp4",
                        "width": Int(abs(size.width)), "height": Int(abs(size.height)),
                        "duration": input.videoDuration, "has_audio": !audio.isEmpty]
                } catch {
                    warnings.append("The prepared video could not be copied; the available storyboard frames are included.")
                }
            }
            artifacts.insert(work(id: sceneId, projectId: projectId, projectTitle: input.projectTitle,
                title: input.sceneTitle, kind: video == nil ? "frame" : "scene", poster: composite,
                full: video ?? composite), at: 0)
            // Drop only unreferenced files created by this export attempt.
            let usedPaths = Set(artifacts.compactMap { ($0["full"] as? [String: Any])?["src"] as? String }
                + [composite["src"] as! String] + [video?["src"] as? String].compactMap { $0 })
            for file in try files.contentsOfDirectory(at: staging.appendingPathComponent("media"), includingPropertiesForKeys: nil) {
                if !usedPaths.contains("media/" + file.lastPathComponent) { try files.removeItem(at: file) }
            }
            var seen = Set<String>()
            let ideas = input.ideas.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }.map { idea -> [String: Any] in
                ["id": idea.id, "slug": idea.slug, "kind": idea.kind, "label": idea.title,
                 "definition": idea.definition, "status": idea.status]
            }
            var links: [[String: Any]] = ideas.map { idea in
                link(source: idea["id"] as! String, target: projectId, relation: "references_meaning")
            }
            links += artifacts.map { link(source: projectId, target: $0["id"] as! String, relation: "same_project") }
            let collection: [String: Any] = ["schema_version": 2, "snapshot_id": "scene-\(token)",
                "title": input.sceneTitle, "description": "A locally exported scene and its saved project ideas.",
                "projects": [["id": projectId, "name": input.projectTitle]], "artifacts": artifacts,
                "meanings": ideas, "associations": [], "context_nodes": [], "context_links": links, "canonical_edges": []]
            var manifest: [String: Any] = ["schema_version": 1, "scene_id": sceneId, "title": input.sceneTitle,
                "project": ["id": projectId, "title": input.projectTitle], "frames": ordered,
                "composite": composite, "composite_frame_ids": Array(pictures.prefix(16)).map(\.0),
                "idea_scope": "project_context", "idea_ids": ideas.map { $0["id"]! },
                "warnings": warnings, "catalog": "catalog.json"]
            if let video { manifest["video"] = video }
            try writeJSON(manifest, to: staging.appendingPathComponent("scene.json"))
            try writeJSON(["schema_version": 1, "collection": collection, "media_base": "./"], to: staging.appendingPathComponent("catalog.json"))
            let note = """
            \(input.sceneTitle)

            scene.json records frame order, skipped entries, omissions, and the single composite image.
            catalog.json uses the LitScenes website catalog envelope. All media references are relative.
            Frames are portable JPEG display copies. Footage entries use their first selected frame.
            The optional MP4 is the current local playback composition, including edits and audio.
            Ideas are saved project context, not new interpretations of the frames.
            This folder is a presentation export, not an editable project backup. Review it before publishing.
            No prompts, provider credentials, inference traces, or original local paths are included.
            """
            try note.write(to: staging.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            try files.moveItem(at: staging, to: destination)
            return PortableSceneResult(directory: destination, warnings: warnings)
        } catch {
            let incomplete = parent.appendingPathComponent(".incomplete-scene-\(token)", isDirectory: true)
            try? files.moveItem(at: staging, to: incomplete)
            throw error
        }
    }

    private static func work(id: String, projectId: String, projectTitle: String, title: String, kind: String,
                             poster: [String: Any], full: [String: Any]) -> [String: Any] {
        ["id": id, "project_id": projectId, "project_name": projectTitle, "title": title, "kind": kind,
         "alt": title, "description": "", "poster": poster, "full": full]
    }

    private static func link(source: String, target: String, relation: String) -> [String: Any] {
        ["id": identity("link", source + ":" + relation + ":" + target), "source": source, "target": target,
         "relation": relation, "basis": "project_context", "evidence": ""]
    }

    private static func identity(_ kind: String, _ value: String) -> String {
        kind + "-" + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
    }

    private static func loadImage(_ url: URL, video: Bool, at seconds: Double) async throws -> CGImage {
        if video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 2048, height: 2048)
            return try await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)).image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    private static func contactSheet(_ images: [CGImage]) throws -> CGImage {
        let columns = images.count <= 1 ? 1 : images.count <= 4 ? 2 : 4
        let rows = max(1, Int(ceil(Double(images.count) / Double(columns))))
        let width = 768, cellWidth = width / columns, cellHeight = cellWidth * 9 / 16
        let height = rows * cellHeight
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 12.0/255, green: 18.0/255, blue: 17.0/255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (index, image) in images.enumerated() {
            let scale = min(Double(cellWidth - 4) / Double(image.width), Double(cellHeight - 4) / Double(image.height))
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            let x = Double(index % columns * cellWidth) + (Double(cellWidth) - w) / 2
            let y = Double(height - (index / columns + 1) * cellHeight) + (Double(cellHeight) - h) / 2
            context.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    private static func writeImage(_ image: CGImage, into directory: URL) throws -> [String: Any] {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let bytes = data as Data
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let name = "media/\(hash).jpg"
        try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
        return ["src": name, "sha256": hash, "bytes": bytes.count, "width": image.width, "height": image.height, "mime": "image/jpeg"]
    }

    private static func fileHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func writeJSON(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
    }
}
