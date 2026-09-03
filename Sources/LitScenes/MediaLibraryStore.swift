import AppKit
@preconcurrency import AVFoundation
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ManagedMediaTransferMode: Equatable, Sendable {
    case clone
    case copy
}

struct ManagedMediaStoragePreflight: Sendable {
    var cloneURLs: [URL]
    var copyRequiredURLs: [URL]
    var copyRequiredByteCount: Int64
    var availableByteCount: Int64?

    var canSafelyCopy: Bool {
        guard let availableByteCount else { return true }
        return availableByteCount >= copyRequiredByteCount + MediaLibraryStore.copySafetyReserveByteCount
    }
}

struct ManagedMediaPreparation: Sendable {
    var source: MediaSourceRecord
    var managedURL: URL
    var createdFile: Bool
}

enum ManagedMediaStoreError: LocalizedError {
    case sourceMissing(String)
    case cloningUnavailable(String)
    case destinationExists(String)
    case insufficientSpace(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case let .sourceMissing(path):
            "The original media is unavailable at \(path)."
        case let .cloningUnavailable(path):
            "APFS cloning is unavailable for \(path)."
        case let .destinationExists(path):
            "LitScenes could not safely replace the existing managed file at \(path)."
        case let .insufficientSpace(required, available):
            "Copying requires \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), but only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
        }
    }
}

struct MediaScanProgress: Hashable {
    var isScanning: Bool = false
    var currentFile: String = ""
    var scannedCount: Int = 0
    var errorCount: Int = 0
}

struct FrameExtractionProgress: Hashable {
    var isExtracting: Bool = false
    var videoMediaId: String = ""
    var completedCount: Int = 0
    var totalCount: Int = 0
    var currentTimeSeconds: Double?
    var status: String = ""
}

struct MediaScanResult: Hashable {
    var source: MediaSourceRecord
    var items: [MediaItemRecord]
    var progress: MediaScanProgress
}

struct MediaLibraryStore {
    static let copySafetyReserveByteCount: Int64 = 1_073_741_824

    let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
    }

    private var mediaSQLiteStore: ProjectMediaSQLiteStore {
        ProjectMediaSQLiteStore(projectLibrary: projectLibrary)
    }

    func libraryDirectory(for project: ProjectRecord) -> URL {
        projectLibrary.projectDirectory(for: project).appendingPathComponent("library", isDirectory: true)
    }

    func thumbnailsDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("thumbnails", isDirectory: true)
    }

    func videoStripsDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("video_strips", isDirectory: true)
    }

    func videoFramesDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("video_frames", isDirectory: true)
    }

    func videoTrimsDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("video_trims", isDirectory: true)
    }

    func screenRecordingsDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("screen_recordings", isDirectory: true)
    }

    func cameraRecordingsDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("camera_recordings", isDirectory: true)
    }

    func chatAttachmentsDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("chat_attachments", isDirectory: true)
    }

    /// Character source images copied into the project, named by content hash.
    func characterSourcesDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("character_sources", isDirectory: true)
    }

    /// Lands original bytes under `character_sources/<sha16>.<ext>`; an existing
    /// file of the same size is the same image and is kept.
    func copyCharacterSource(data: Data, sha256: String, fileExtension: String, for project: ProjectRecord) throws -> URL {
        let cleanedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = "\(sha256.prefix(16)).\(cleanedExtension.isEmpty ? "img" : cleanedExtension)"
        let destination = characterSourcesDirectory(for: project).appendingPathComponent(name)
        try ensureDirectory(destination.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: destination.path) {
            let existingSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            if existingSize == data.count { return destination }
        }
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    func managedOriginalsDirectory(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("originals", isDirectory: true)
    }

    func mediaSourcesURL(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("media_sources.json")
    }

    func mediaInventoryURL(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("media_inventory.json")
    }

    func curationURL(for project: ProjectRecord) -> URL {
        libraryDirectory(for: project).appendingPathComponent("curation.json")
    }

    func loadSources(for project: ProjectRecord) -> [MediaSourceRecord] {
        (try? mediaSQLiteStore.loadSources(for: project)) ?? []
    }

    func saveSources(_ sources: [MediaSourceRecord], for project: ProjectRecord) throws {
        try mediaSQLiteStore.saveSources(sources, for: project)
    }

    func loadInventory(for project: ProjectRecord) -> [MediaItemRecord] {
        (try? mediaSQLiteStore.loadInventory(for: project)) ?? []
    }

    func saveInventory(_ items: [MediaItemRecord], for project: ProjectRecord) throws {
        try mediaSQLiteStore.saveInventory(items, for: project)
    }

    func saveLibrary(
        sources: [MediaSourceRecord],
        items: [MediaItemRecord],
        for project: ProjectRecord
    ) throws {
        try mediaSQLiteStore.saveLibrary(sources: sources, items: items, for: project)
    }

    func loadCuration(for project: ProjectRecord) -> [String: MediaCurationRecord] {
        (try? mediaSQLiteStore.loadCuration(for: project)) ?? [:]
    }

    func saveCuration(_ curation: [String: MediaCurationRecord], for project: ProjectRecord) throws {
        try mediaSQLiteStore.saveCuration(curation, for: project)
    }

    func generatedMediaItem(
        for url: URL,
        project: ProjectRecord,
        mediaId: String,
        derivativeKind: String,
        sourceMediaId: String? = nil,
        sourceTimestampSeconds: Double? = nil,
        frameIndex: Int? = nil,
        filename: String? = nil
    ) async throws -> MediaItemRecord {
        let sourceURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ScreenGraphError.capture("Generated media file is missing.")
        }
        let root = projectLibrary.projectDirectory(for: project)
        if isImage(sourceURL) {
            return try scanGeneratedImage(
                sourceURL,
                project: project,
                root: root,
                mediaId: mediaId,
                derivativeKind: derivativeKind,
                sourceMediaId: sourceMediaId,
                sourceTimestampSeconds: sourceTimestampSeconds,
                frameIndex: frameIndex,
                filename: filename
            )
        }
        if isVideo(sourceURL) {
            return try await scanGeneratedVideo(
                sourceURL,
                project: project,
                root: root,
                mediaId: mediaId,
                derivativeKind: derivativeKind,
                sourceMediaId: sourceMediaId,
                sourceTimestampSeconds: sourceTimestampSeconds,
                frameIndex: frameIndex,
                filename: filename
            )
        }
        throw ScreenGraphError.capture("Generated media must be an image or video file.")
    }

    func makeSource(
        from url: URL,
        kind: MediaSourceKind? = nil,
        storageMode: MediaStorageMode = .linked,
        originalURL: URL? = nil
    ) -> MediaSourceRecord {
        let bookmarkData = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        let provenanceURL = (originalURL ?? url).standardizedFileURL
        let provenanceBookmark = (try? provenanceURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? Data()
        let path = url.standardizedFileURL.path
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let resolvedKind = kind ?? (values?.isDirectory == true ? .folder : .file)
        return MediaSourceRecord(
            sourceId: "source_\(shortHash(provenanceURL.path, length: 16))",
            displayName: provenanceURL.lastPathComponent.isEmpty ? path : provenanceURL.lastPathComponent,
            path: path,
            sourceKind: resolvedKind,
            bookmarkDataBase64: storageMode == .linked ? bookmarkData.base64EncodedString() : "",
            storageMode: storageMode,
            originalPath: provenanceURL.path,
            originalBookmarkDataBase64: provenanceBookmark.base64EncodedString(),
            addedAt: DateFormats.now(),
            lastScannedAt: nil
        )
    }

    func managedStoragePreflight(
        for urls: [URL],
        project: ProjectRecord
    ) -> ManagedMediaStoragePreflight {
        let destinationRoot = projectLibrary.projectDirectory(for: project)
        var cloneURLs: [URL] = []
        var copyRequiredURLs: [URL] = []
        var copyRequiredByteCount: Int64 = 0
        for url in urls.map(\.standardizedFileURL) {
            if canCloneFile(at: url, into: destinationRoot) {
                cloneURLs.append(url)
            } else {
                copyRequiredURLs.append(url)
                copyRequiredByteCount += logicalByteCount(for: url)
            }
        }
        return ManagedMediaStoragePreflight(
            cloneURLs: cloneURLs,
            copyRequiredURLs: copyRequiredURLs,
            copyRequiredByteCount: copyRequiredByteCount,
            availableByteCount: availableCapacity(for: destinationRoot)
        )
    }

    func copyStoragePreflight(
        for urls: [URL],
        project: ProjectRecord
    ) -> ManagedMediaStoragePreflight {
        let standardizedURLs = urls.map(\.standardizedFileURL)
        let copyRequiredByteCount = standardizedURLs.reduce(Int64(0)) {
            $0 + logicalByteCount(for: $1)
        }
        return ManagedMediaStoragePreflight(
            cloneURLs: [],
            copyRequiredURLs: standardizedURLs,
            copyRequiredByteCount: copyRequiredByteCount,
            availableByteCount: availableCapacity(for: projectLibrary.projectDirectory(for: project))
        )
    }

    func prepareManagedSource(
        from originalURL: URL,
        for project: ProjectRecord,
        transferMode: ManagedMediaTransferMode
    ) async throws -> ManagedMediaPreparation {
        let original = originalURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: original.path) else {
            throw ManagedMediaStoreError.sourceMissing(original.path)
        }

        let sourceId = "source_\(shortHash(original.path, length: 16))"
        let sourceDirectory = managedOriginalsDirectory(for: project)
            .appendingPathComponent(sourceId, isDirectory: true)
        let managedURL = managedFileURL(for: original, in: sourceDirectory)
        let requiredByteCount = logicalByteCount(for: original)
        let availableByteCount = availableCapacity(for: projectLibrary.projectDirectory(for: project))
        if transferMode == .copy,
           let availableByteCount,
           availableByteCount < requiredByteCount + Self.copySafetyReserveByteCount {
            throw ManagedMediaStoreError.insufficientSpace(
                required: requiredByteCount + Self.copySafetyReserveByteCount,
                available: availableByteCount
            )
        }

        let transfer = try await Task.detached(priority: .userInitiated) {
            try Self.transferManagedFile(
                from: original,
                to: managedURL,
                mode: transferMode
            )
        }.value
        let source = makeSource(
            from: transfer.url,
            kind: .file,
            storageMode: .managed,
            originalURL: original
        )
        return ManagedMediaPreparation(
            source: source,
            managedURL: transfer.url,
            createdFile: transfer.createdFile
        )
    }

    func discardManagedPreparation(_ preparation: ManagedMediaPreparation) {
        guard preparation.createdFile,
              FileManager.default.fileExists(atPath: preparation.managedURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: preparation.managedURL)
    }

    private func canCloneFile(at sourceURL: URL, into destinationURL: URL) -> Bool {
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if access { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard let sourceValues = try? sourceURL.resourceValues(forKeys: [.volumeIdentifierKey]),
              let destinationValues = try? destinationURL.resourceValues(
                forKeys: [.volumeIdentifierKey, .volumeSupportsFileCloningKey]
              ),
              destinationValues.volumeSupportsFileCloning == true,
              let sourceVolume = sourceValues.volumeIdentifier,
              let destinationVolume = destinationValues.volumeIdentifier else {
            return false
        }
        return String(describing: sourceVolume) == String(describing: destinationVolume)
    }

    private func logicalByteCount(for url: URL) -> Int64 {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return Int64(size)
    }

    private func availableCapacity(for destinationURL: URL) -> Int64? {
        guard let capacity = try? destinationURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return capacity
    }

    private func managedFileURL(for originalURL: URL, in directory: URL) -> URL {
        let values = try? originalURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let byteCount = values?.fileSize ?? 0
        let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fingerprint = shortHash("\(originalURL.path):\(byteCount):\(modifiedAt)", length: 16)
        return directory
            .appendingPathComponent(fingerprint, isDirectory: true)
            .appendingPathComponent(originalURL.lastPathComponent, isDirectory: false)
    }

    private static func transferManagedFile(
        from sourceURL: URL,
        to destinationURL: URL,
        mode: ManagedMediaTransferMode
    ) throws -> (url: URL, createdFile: Bool) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            let sourceSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            let destinationSize = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
            guard sourceSize == destinationSize else {
                throw ManagedMediaStoreError.destinationExists(destinationURL.path)
            }
            return (destinationURL, false)
        }

        try ensureDirectory(destinationURL.deletingLastPathComponent())
        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".importing_\(UUID().uuidString)")
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        switch mode {
        case .clone:
            let result = sourceURL.path.withCString { sourcePath in
                stagingURL.path.withCString { destinationPath in
                    clonefile(sourcePath, destinationPath, 0)
                }
            }
            guard result == 0 else {
                throw ManagedMediaStoreError.cloningUnavailable(sourceURL.path)
            }
        case .copy:
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
        }

        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        return (destinationURL, true)
    }

    func extractFrames(
        from video: MediaItemRecord,
        source: MediaSourceRecord?,
        for project: ProjectRecord,
        maxFrames: Int = 240,
        progress: @MainActor @escaping (FrameExtractionProgress) -> Void
    ) async throws -> [MediaItemRecord] {
        guard video.kind == .video else { return [] }
        let durationSeconds = try await videoDurationSeconds(video)
        let sampleTimes = frameSampleTimes(durationSeconds: durationSeconds, maxFrames: maxFrames)
        return try await extractFrames(
            from: video,
            source: source,
            for: project,
            sampleTimes: sampleTimes,
            progress: progress
        )
    }

    func extractFramesAtRate(
        from video: MediaItemRecord,
        source: MediaSourceRecord?,
        for project: ProjectRecord,
        framesPerSecond: Int,
        capSeconds: Double,
        maxFrames: Int = 300,
        progress: @MainActor @escaping (FrameExtractionProgress) -> Void
    ) async throws -> [MediaItemRecord] {
        guard video.kind == .video else { return [] }
        let durationSeconds = try await videoDurationSeconds(video)
        let sampleTimes = frameRateSampleTimes(
            durationSeconds: durationSeconds,
            framesPerSecond: framesPerSecond,
            capSeconds: capSeconds,
            maxFrames: maxFrames
        )
        return try await extractFrames(
            from: video,
            source: source,
            for: project,
            sampleTimes: sampleTimes,
            progress: progress
        )
    }

    private func extractFrames(
        from video: MediaItemRecord,
        source: MediaSourceRecord?,
        for project: ProjectRecord,
        sampleTimes: [Double],
        progress: @MainActor @escaping (FrameExtractionProgress) -> Void
    ) async throws -> [MediaItemRecord] {
        let sourceURL = source.map { sourceAccessURL(for: $0) }
        let access = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if access {
                sourceURL?.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: URL(fileURLWithPath: video.path))
        guard !sampleTimes.isEmpty else {
            await progress(FrameExtractionProgress(
                isExtracting: false,
                videoMediaId: video.mediaId,
                completedCount: 0,
                totalCount: 0,
                currentTimeSeconds: nil,
                status: "No frames available"
            ))
            return []
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)

        let frameDirectory = framesDirectory(for: video, project: project)
        try ensureDirectory(frameDirectory)
        try ensureDirectory(thumbnailsDirectory(for: project))

        await progress(FrameExtractionProgress(
            isExtracting: true,
            videoMediaId: video.mediaId,
            completedCount: 0,
            totalCount: sampleTimes.count,
            currentTimeSeconds: nil,
            status: "Extracting frames"
        ))

        var records: [MediaItemRecord] = []
        for (index, seconds) in sampleTimes.enumerated() {
            let frameId = videoFrameId(videoMediaId: video.mediaId, index: index, seconds: seconds)
            let frameURL = frameDirectory.appendingPathComponent("\(frameId).jpg")
            let thumbnailURL = thumbnailsDirectory(for: project).appendingPathComponent("\(frameId).jpg")
            var generated: CGImage?

            if !FileManager.default.fileExists(atPath: frameURL.path) || !FileManager.default.fileExists(atPath: thumbnailURL.path) {
                let image = try await generatedImage(
                    generator: generator,
                    at: CMTime(seconds: seconds, preferredTimescale: 600)
                )
                generated = image
                if !FileManager.default.fileExists(atPath: frameURL.path) {
                    try writeJPEG(image, to: frameURL, quality: 0.86)
                }
                if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
                    let thumbnail = resizedImage(image, maxPixelSize: 640) ?? image
                    try writeJPEG(thumbnail, to: thumbnailURL)
                }
            }

            let imageSource = generated == nil ? CGImageSourceCreateWithURL(frameURL as CFURL, nil) : nil
            let dimensions = generated.map { (width: $0.width, height: $0.height) } ?? imageDimensions(from: imageSource)
            let metadata = try fileMetadata(for: frameURL)
            records.append(MediaItemRecord(
                mediaId: frameId,
                sourceId: video.sourceId,
                kind: .image,
                filename: frameFilename(for: video, seconds: seconds, index: index),
                path: frameURL.path,
                relativePath: frameURL.relativePath(from: libraryDirectory(for: project)),
                byteCount: metadata.byteCount,
                modifiedAt: metadata.modifiedAt,
                width: dimensions.width,
                height: dimensions.height,
                durationSeconds: nil,
                nominalFrameRate: nil,
                thumbnailPath: thumbnailURL.path,
                videoStripPath: nil,
                scannedAt: DateFormats.now(),
                scanError: nil,
                derivativeKind: MediaItemRecord.videoFrameDerivativeKind,
                sourceMediaId: video.mediaId,
                sourceTimestampSeconds: seconds,
                frameIndex: index
            ))

            await progress(FrameExtractionProgress(
                isExtracting: true,
                videoMediaId: video.mediaId,
                completedCount: index + 1,
                totalCount: sampleTimes.count,
                currentTimeSeconds: seconds,
                status: "Extracting frames"
            ))
        }

        await progress(FrameExtractionProgress(
            isExtracting: false,
            videoMediaId: video.mediaId,
            completedCount: records.count,
            totalCount: sampleTimes.count,
            currentTimeSeconds: nil,
            status: "Frames ready"
        ))
        return records
    }

    func captureFrame(
        from video: MediaItemRecord,
        source: MediaSourceRecord?,
        for project: ProjectRecord,
        at seconds: Double
    ) async throws -> MediaItemRecord {
        guard video.kind == .video else {
            throw ScreenGraphError.capture("Only video sources can provide frame captures.")
        }

        let sourceURL = source.map { sourceAccessURL(for: $0) }
        let access = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if access {
                sourceURL?.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: URL(fileURLWithPath: video.path))
        let durationSeconds = try await VideoChainMedia.videoDurationSeconds(
            videoURL: URL(fileURLWithPath: video.path)
        )
        let clampedSeconds = clampedFrameTime(seconds, durationSeconds: durationSeconds)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)

        let frameDirectory = framesDirectory(for: video, project: project)
        try ensureDirectory(frameDirectory)
        try ensureDirectory(thumbnailsDirectory(for: project))

        let frameId = capturedFrameId(videoMediaId: video.mediaId, seconds: clampedSeconds)
        let frameURL = frameDirectory.appendingPathComponent("\(frameId).jpg")
        let thumbnailURL = thumbnailsDirectory(for: project).appendingPathComponent("\(frameId).jpg")
        let image = try await generatedImage(
            generator: generator,
            at: CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        )
        try writeJPEG(image, to: frameURL, quality: 0.86)
        let thumbnail = resizedImage(image, maxPixelSize: 640) ?? image
        try writeJPEG(thumbnail, to: thumbnailURL)

        let metadata = try fileMetadata(for: frameURL)
        return MediaItemRecord(
            mediaId: frameId,
            sourceId: video.sourceId,
            kind: .image,
            filename: frameFilename(for: video, seconds: clampedSeconds, index: nil),
            path: frameURL.path,
            relativePath: frameURL.relativePath(from: libraryDirectory(for: project)),
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            width: image.width,
            height: image.height,
            durationSeconds: nil,
            nominalFrameRate: nil,
            thumbnailPath: thumbnailURL.path,
            videoStripPath: nil,
            scannedAt: DateFormats.now(),
            scanError: nil,
            derivativeKind: MediaItemRecord.videoFrameDerivativeKind,
            sourceMediaId: video.mediaId,
            sourceTimestampSeconds: clampedSeconds,
            frameIndex: nil
        )
    }

    /// Runs `body` holding security-scoped access to an external source (nil
    /// source ⇒ project-local file, no scope needed). The render loop uses
    /// this to read externally referenced footage placed in a shot.
    func withSourceAccess<T: Sendable>(
        _ source: MediaSourceRecord?,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let sourceURL = source.map { sourceAccessURL(for: $0) }
        let access = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if access {
                sourceURL?.stopAccessingSecurityScopedResource()
            }
        }
        return try await body()
    }

    /// Cuts [start, end] out of a source video and registers the result as a
    /// new source-like asset (`video_trim` derivative) living inside the
    /// project library. Frame-accurate by design: extractTimeRange re-encodes.
    func trimVideo(
        from video: MediaItemRecord,
        source: MediaSourceRecord?,
        for project: ProjectRecord,
        startSeconds: Double,
        endSeconds: Double
    ) async throws -> MediaItemRecord {
        guard video.kind == .video else {
            throw ScreenGraphError.capture("Only video sources can be trimmed.")
        }

        let sourceURL = source.map { sourceAccessURL(for: $0) }
        let access = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if access {
                sourceURL?.stopAccessingSecurityScopedResource()
            }
        }

        let durationSeconds = try await VideoChainMedia.videoDurationSeconds(
            videoURL: URL(fileURLWithPath: video.path)
        )
        let range = VideoTrimRange.clamped(
            start: startSeconds,
            end: endSeconds,
            videoDurationSeconds: durationSeconds
        )
        guard range.isSaveable else {
            throw ScreenGraphError.capture("Cut selection must be at least \(VideoTrimRange.minimumTrimSeconds) seconds.")
        }

        let trimId = videoTrimMediaId(parentMediaId: video.mediaId, range: range)
        let trimDirectory = videoTrimsDirectory(for: project)
            .appendingPathComponent(video.mediaId, isDirectory: true)
        try ensureDirectory(trimDirectory)
        let outputURL = trimDirectory.appendingPathComponent("\(trimId).mp4")
        _ = try await VideoChainMedia.extractTimeRange(
            videoURL: URL(fileURLWithPath: video.path),
            outputURL: outputURL,
            startSeconds: range.startSeconds,
            durationSeconds: range.durationSeconds
        )

        return try await generatedMediaItem(
            for: outputURL,
            project: project,
            mediaId: trimId,
            derivativeKind: MediaItemRecord.videoTrimDerivativeKind,
            sourceMediaId: video.mediaId,
            sourceTimestampSeconds: range.startSeconds,
            filename: videoTrimFilename(parentFilename: video.filename, range: range)
        )
    }

    func scan(
        source: MediaSourceRecord,
        for project: ProjectRecord,
        progress: @MainActor @escaping (MediaScanProgress) -> Void
    ) async -> MediaScanResult {
        var scanProgress = MediaScanProgress(isScanning: true)
        await progress(scanProgress)
        let sourceURL = sourceAccessURL(for: source)
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var items: [MediaItemRecord] = []
        let root = scanRoot(for: sourceURL, source: source)
        for file in mediaFiles(for: sourceURL, source: source) {
            scanProgress.currentFile = file.lastPathComponent
            await progress(scanProgress)
            do {
                if isImage(file) {
                    items.append(try scanImage(file, source: source, root: root, project: project))
                } else if isVideo(file) {
                    items.append(try await scanVideo(file, source: source, root: root, project: project))
                } else if isAudio(file) {
                    items.append(try await scanAudio(file, source: source, root: root, project: project))
                }
                scanProgress.scannedCount += 1
            } catch {
                items.append(failedItem(file, source: source, root: root, error: error))
                scanProgress.errorCount += 1
                scanProgress.scannedCount += 1
            }
            await progress(scanProgress)
        }

        scanProgress.isScanning = false
        scanProgress.currentFile = ""
        await progress(scanProgress)

        var updatedSource = source
        updatedSource.lastScannedAt = DateFormats.now()
        return MediaScanResult(source: updatedSource, items: items, progress: scanProgress)
    }

    private func sourceAccessURL(for source: MediaSourceRecord) -> URL {
        URL(fileURLWithPath: source.path, isDirectory: source.resolvedSourceKind == .folder)
    }

    private func scanRoot(for sourceURL: URL, source: MediaSourceRecord) -> URL {
        switch source.resolvedSourceKind {
        case .folder:
            return sourceURL
        case .file:
            return sourceURL.deletingLastPathComponent()
        }
    }

    private func mediaFiles(for sourceURL: URL, source: MediaSourceRecord) -> [URL] {
        switch source.resolvedSourceKind {
        case .folder:
            return mediaFiles(under: sourceURL)
        case .file:
            return (isImage(sourceURL) || isVideo(sourceURL) || isAudio(sourceURL)) ? [sourceURL] : []
        }
    }

    private func mediaFiles(under root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isHidden != true else {
                continue
            }
            if isImage(url) || isVideo(url) || isAudio(url) {
                urls.append(url)
            }
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private func isVideo(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video) || ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    /// The extension list matches the one the sound rail already used
    /// (`SoundSceneTimelineStore`), so a file that browser would have listed is
    /// a file the project can now import.
    private func isAudio(_ url: URL) -> Bool {
        if ["wav", "m4a", "mp3", "aiff", "aif", "aac", "caf", "flac"].contains(url.pathExtension.lowercased()) {
            return true
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio)
    }

    /// Audio has no frame to grab, so there is no thumbnail and no strip — the
    /// waveform is drawn on demand from the file itself. Duration is the one
    /// piece of metadata worth reading up front, since every audio surface
    /// shows it.
    private func scanAudio(_ url: URL, source: MediaSourceRecord, root: URL, project: ProjectRecord) async throws -> MediaItemRecord {
        let metadata = try fileMetadata(for: url)
        let mediaId = mediaId(for: url, metadata: metadata)
        let durationSeconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        return MediaItemRecord(
            mediaId: mediaId,
            sourceId: source.sourceId,
            kind: .audio,
            filename: url.lastPathComponent,
            path: url.path,
            relativePath: url.relativePath(from: root),
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            width: 0,
            height: 0,
            durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
            nominalFrameRate: 0,
            thumbnailPath: "",
            videoStripPath: "",
            scannedAt: DateFormats.now(),
            scanError: nil
        )
    }

    private func scanImage(_ url: URL, source: MediaSourceRecord, root: URL, project: ProjectRecord) throws -> MediaItemRecord {
        let metadata = try fileMetadata(for: url)
        let mediaId = mediaId(for: url, metadata: metadata)
        let thumbnailURL = thumbnailsDirectory(for: project).appendingPathComponent("\(mediaId).jpg")
        let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        let dimensions = imageDimensions(from: imageSource)
        if let imageSource, !FileManager.default.fileExists(atPath: thumbnailURL.path) {
            try ensureDirectory(thumbnailURL.deletingLastPathComponent())
            if let image = imageThumbnail(from: imageSource, maxPixelSize: 640) {
                try writeJPEG(image, to: thumbnailURL)
            }
        }
        return MediaItemRecord(
            mediaId: mediaId,
            sourceId: source.sourceId,
            kind: .image,
            filename: url.lastPathComponent,
            path: url.path,
            relativePath: url.relativePath(from: root),
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            width: dimensions.width,
            height: dimensions.height,
            durationSeconds: nil,
            nominalFrameRate: nil,
            thumbnailPath: thumbnailURL.path,
            videoStripPath: nil,
            scannedAt: DateFormats.now(),
            scanError: nil
        )
    }

    private func scanGeneratedImage(
        _ url: URL,
        project: ProjectRecord,
        root: URL,
        mediaId: String,
        derivativeKind: String,
        sourceMediaId: String?,
        sourceTimestampSeconds: Double?,
        frameIndex: Int?,
        filename: String?
    ) throws -> MediaItemRecord {
        let metadata = try fileMetadata(for: url)
        let thumbnailURL = thumbnailsDirectory(for: project).appendingPathComponent("\(mediaId).jpg")
        let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        let dimensions = imageDimensions(from: imageSource)
        if let imageSource {
            try ensureDirectory(thumbnailURL.deletingLastPathComponent())
            if let image = imageThumbnail(from: imageSource, maxPixelSize: 640) {
                try writeJPEG(image, to: thumbnailURL)
            }
        }
        // Derived items are one file each: hashing them here is cheap and makes a
        // copied source recognizable on its next import.
        let contentSha256 = (try? Data(contentsOf: url)).map(sha256Hex) ?? ""
        return MediaItemRecord(
            mediaId: mediaId,
            sourceId: MediaItemRecord.generatedMediaSourceId,
            kind: .image,
            filename: resolvedGeneratedFilename(filename, fallbackURL: url),
            path: url.path,
            relativePath: url.relativePath(from: root),
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            width: dimensions.width,
            height: dimensions.height,
            durationSeconds: nil,
            nominalFrameRate: nil,
            thumbnailPath: thumbnailURL.path,
            videoStripPath: nil,
            scannedAt: DateFormats.now(),
            scanError: nil,
            derivativeKind: derivativeKind,
            sourceMediaId: sourceMediaId,
            sourceTimestampSeconds: sourceTimestampSeconds,
            frameIndex: frameIndex,
            contentSha256: contentSha256
        )
    }

    private func failedItem(_ url: URL, source: MediaSourceRecord, root: URL, error: Error) -> MediaItemRecord {
        let metadata = (try? fileMetadata(for: url)) ?? (byteCount: Int64(0), modifiedAt: DateFormats.now())
        let mediaId = mediaId(for: url, metadata: metadata)
        return MediaItemRecord(
            mediaId: mediaId,
            sourceId: source.sourceId,
            kind: isVideo(url) ? .video : (isAudio(url) ? .audio : .image),
            filename: url.lastPathComponent,
            path: url.path,
            relativePath: url.relativePath(from: root),
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            width: 0,
            height: 0,
            durationSeconds: nil,
            nominalFrameRate: nil,
            thumbnailPath: "",
            videoStripPath: nil,
            scannedAt: DateFormats.now(),
            scanError: error.localizedDescription
        )
    }

    private func scanVideo(_ url: URL, source: MediaSourceRecord, root: URL, project: ProjectRecord) async throws -> MediaItemRecord {
        let metadata = try fileMetadata(for: url)
        let mediaId = mediaId(for: url, metadata: metadata)
        let thumbnailURL = thumbnailsDirectory(for: project).appendingPathComponent("\(mediaId).jpg")
        let stripURL = videoStripsDirectory(for: project).appendingPathComponent("\(mediaId).jpg")
        let asset = AVURLAsset(url: url)
        let durationSeconds = try await VideoChainMedia.videoDurationSeconds(videoURL: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = tracks.first
        let naturalSize = try await videoTrack?.load(.naturalSize) ?? .zero
        let transform = try await videoTrack?.load(.preferredTransform) ?? .identity
        let nominalFrameRate = Double(try await videoTrack?.load(.nominalFrameRate) ?? 0)
        let oriented = naturalSize.applying(transform)
        let width = Int(abs(oriented.width).rounded())
        let height = Int(abs(oriented.height).rounded())
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
            try ensureDirectory(thumbnailURL.deletingLastPathComponent())
            let time = CMTime(seconds: min(max(durationSeconds * 0.12, 0), max(durationSeconds - 0.01, 0)), preferredTimescale: 600)
            let image = try await generatedImage(generator: generator, at: time)
            try writeJPEG(image, to: thumbnailURL)
        }
        if !FileManager.default.fileExists(atPath: stripURL.path) {
            try ensureDirectory(stripURL.deletingLastPathComponent())
            if let strip = try await videoStrip(generator: generator, durationSeconds: durationSeconds) {
                try writeJPEG(strip, to: stripURL)
            }
        }
        return MediaItemRecord(
            mediaId: mediaId,
            sourceId: source.sourceId,
            kind: .video,
            filename: url.lastPathComponent,
            path: url.path,
            relativePath: url.relativePath(from: root),
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            width: width,
            height: height,
            durationSeconds: durationSeconds,
            nominalFrameRate: nominalFrameRate,
            thumbnailPath: thumbnailURL.path,
            videoStripPath: stripURL.path,
            scannedAt: DateFormats.now(),
            scanError: nil
        )
    }

    private func scanGeneratedVideo(
        _ url: URL,
        project: ProjectRecord,
        root: URL,
        mediaId: String,
        derivativeKind: String,
        sourceMediaId: String?,
        sourceTimestampSeconds: Double?,
        frameIndex: Int?,
        filename: String?
    ) async throws -> MediaItemRecord {
        let metadata = try fileMetadata(for: url)
        let thumbnailURL = thumbnailsDirectory(for: project).appendingPathComponent("\(mediaId).jpg")
        let stripURL = videoStripsDirectory(for: project).appendingPathComponent("\(mediaId).jpg")
        let asset = AVURLAsset(url: url)
        let durationSeconds = try await VideoChainMedia.videoDurationSeconds(videoURL: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = tracks.first
        let naturalSize = try await videoTrack?.load(.naturalSize) ?? .zero
        let transform = try await videoTrack?.load(.preferredTransform) ?? .identity
        let nominalFrameRate = Double(try await videoTrack?.load(.nominalFrameRate) ?? 0)
        let oriented = naturalSize.applying(transform)
        let width = Int(abs(oriented.width).rounded())
        let height = Int(abs(oriented.height).rounded())
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        try ensureDirectory(thumbnailURL.deletingLastPathComponent())
        let time = CMTime(seconds: min(max(durationSeconds * 0.12, 0), max(durationSeconds - 0.01, 0)), preferredTimescale: 600)
        if let image = try? await generatedImage(generator: generator, at: time) {
            try writeJPEG(image, to: thumbnailURL)
        }
        try ensureDirectory(stripURL.deletingLastPathComponent())
        if let strip = try? await videoStrip(generator: generator, durationSeconds: durationSeconds) {
            try writeJPEG(strip, to: stripURL)
        }
        return MediaItemRecord(
            mediaId: mediaId,
            sourceId: MediaItemRecord.generatedMediaSourceId,
            kind: .video,
            filename: resolvedGeneratedFilename(filename, fallbackURL: url),
            path: url.path,
            relativePath: url.relativePath(from: root),
            byteCount: metadata.byteCount,
            modifiedAt: metadata.modifiedAt,
            width: width,
            height: height,
            durationSeconds: durationSeconds,
            nominalFrameRate: nominalFrameRate,
            thumbnailPath: thumbnailURL.path,
            videoStripPath: stripURL.path,
            scannedAt: DateFormats.now(),
            scanError: nil,
            derivativeKind: derivativeKind,
            sourceMediaId: sourceMediaId,
            sourceTimestampSeconds: sourceTimestampSeconds,
            frameIndex: frameIndex
        )
    }

    private func imageDimensions(from source: CGImageSource?) -> (width: Int, height: Int) {
        guard let properties = source.flatMap({ CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }) else {
            return (0, 0)
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (width, height)
    }

    private func imageThumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func videoStrip(generator: AVAssetImageGenerator, durationSeconds: Double) async throws -> CGImage? {
        guard durationSeconds > 0 else { return nil }
        let times = [0.08, 0.28, 0.5, 0.72, 0.92].map {
            CMTime(seconds: max(0, min(durationSeconds * $0, durationSeconds - 0.01)), preferredTimescale: 600)
        }
        var images: [CGImage] = []
        for time in times {
            images.append(try await generatedImage(generator: generator, at: time))
        }
        guard let first = images.first else { return nil }
        let tileHeight = 120
        let tileWidth = max(1, Int((Double(first.width) / Double(max(first.height, 1))) * Double(tileHeight)))
        let width = tileWidth * images.count
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: tileHeight * bytesPerRow)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: tileHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        for (index, image) in images.enumerated() {
            context.draw(image, in: CGRect(x: index * tileWidth, y: 0, width: tileWidth, height: tileHeight))
        }
        return context.makeImage()
    }

    private func generatedImage(generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ScreenGraphError.capture("Could not generate video preview frame."))
                }
            }
        }
    }

    private func framesDirectory(for video: MediaItemRecord, project: ProjectRecord) -> URL {
        videoFramesDirectory(for: project).appendingPathComponent(video.mediaId, isDirectory: true)
    }

    private func frameSampleTimes(durationSeconds: Double, maxFrames: Int) -> [Double] {
        guard durationSeconds > 0, maxFrames > 0 else { return [] }
        let count = min(maxFrames, max(1, Int(ceil(durationSeconds))))
        let step = durationSeconds / Double(count)
        let latest = max(durationSeconds - 0.01, 0)
        return (0..<count).map { index in
            min(latest, max(0, Double(index) * step + step * 0.5))
        }
    }

    private func frameRateSampleTimes(
        durationSeconds: Double,
        framesPerSecond: Int,
        capSeconds: Double,
        maxFrames: Int
    ) -> [Double] {
        guard durationSeconds > 0, framesPerSecond > 0, capSeconds > 0, maxFrames > 0 else { return [] }
        let captureDuration = min(durationSeconds, capSeconds)
        let count = min(maxFrames, max(1, Int(floor(captureDuration * Double(framesPerSecond)))))
        let step = 1 / Double(framesPerSecond)
        let latest = max(durationSeconds - 0.01, 0)
        return (0..<count).map { index in
            min(latest, Double(index) * step)
        }
    }

    private func videoDurationSeconds(_ video: MediaItemRecord) async throws -> Double {
        try await VideoChainMedia.videoDurationSeconds(
            videoURL: URL(fileURLWithPath: video.path)
        )
    }

    private func videoFrameId(videoMediaId: String, index: Int, seconds: Double) -> String {
        "frame_\(shortHash("\(videoMediaId)|\(index)|\(String(format: "%.3f", seconds))", length: 20))"
    }

    private func capturedFrameId(videoMediaId: String, seconds: Double) -> String {
        "frame_\(shortHash("\(videoMediaId)|capture|\(String(format: "%.3f", seconds))", length: 20))"
    }

    private func frameFilename(for video: MediaItemRecord, seconds: Double, index: Int?) -> String {
        let baseName = URL(fileURLWithPath: video.filename).deletingPathExtension().lastPathComponent
        let slug = stableSlug(baseName, fallback: "video")
        let suffix = index.map { "_\(String(format: "%04d", $0 + 1))" } ?? ""
        return "\(slug)_\(timecodeSlug(seconds))\(suffix).jpg"
    }

    private func clampedFrameTime(_ seconds: Double, durationSeconds: Double) -> Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(seconds, 0), max(durationSeconds - 0.01, 0))
    }

    private func timecodeSlug(_ seconds: Double) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        let remainder = wholeSeconds % 60
        if hours > 0 {
            return String(format: "%02dh%02dm%02ds", hours, minutes, remainder)
        }
        return String(format: "%02dm%02ds", minutes, remainder)
    }

    private func resizedImage(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let longestSide = max(image.width, image.height)
        guard longestSide > maxPixelSize else { return image }
        let scale = CGFloat(maxPixelSize) / CGFloat(longestSide)
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
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
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.82) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ScreenGraphError.invalidImageDestination
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenGraphError.invalidImageDestination
        }
    }

    private func fileMetadata(for url: URL) throws -> (byteCount: Int64, modifiedAt: String) {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let byteCount = Int64(values.fileSize ?? 0)
        let modifiedAt = DateFormats.string(from: values.contentModificationDate ?? Date.distantPast)
        return (byteCount, modifiedAt)
    }

    private func mediaId(for url: URL, metadata: (byteCount: Int64, modifiedAt: String)) -> String {
        "media_\(shortHash("\(url.standardizedFileURL.path)|\(metadata.byteCount)|\(metadata.modifiedAt)", length: 20))"
    }

    private func resolvedGeneratedFilename(_ filename: String?, fallbackURL: URL) -> String {
        let cleaned = filename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? fallbackURL.lastPathComponent : cleaned
    }
}
