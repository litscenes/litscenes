import Foundation
import SQLite3

struct StoryPersistenceRecoveryDocument: Codable, Hashable {
    static let schemaVersion = "litscenes.story_persistence_recovery.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var projectId: String
    var message: String
    var createdAt: String = DateFormats.now()
}

private struct StorySQLiteIDPacket: Codable {
    var namespace: String
    var kind: String
    var components: [String]
    var collisionIndex: Int
}

private struct BeatEntityProjection {
    var rowsByEntityId: [String: String] = [:]
    var orderedRows: [String] = []
}

final class ProjectStorySQLiteStore {
    private static let queue = DispatchQueue(label: "local.litscenes.project-story-sqlite-store")

    private let projectLibrary: ProjectLibrary

    init(projectLibrary: ProjectLibrary = ProjectLibrary()) {
        self.projectLibrary = projectLibrary
    }

    func loadRecovery(for project: ProjectRecord) -> StoryPersistenceRecoveryDocument? {
        try? ProjectSQLiteDocumentStore(projectLibrary: projectLibrary)
            .loadDocument(
                StoryPersistenceRecoveryDocument.self,
                for: project,
                documentType: "story_persistence_recovery"
            )
    }

    func loadProjectStory(for project: ProjectRecord) throws -> ProjectStoryDocument {
        try ensureImported(for: project)
        return try withProjectConnection(project, readOnly: true) { connection in
            let sql = "SELECT story_json FROM project_story_documents WHERE project_id = ? LIMIT 1;"
            guard let json = try self.optionalString(connection, sql: sql, bindings: [project.projectId]) else {
                return ProjectStoryDocument.empty(projectId: project.projectId)
            }
            do {
                var document = try JSONCoding.decoder.decode(ProjectStoryDocument.self, from: Data(json.utf8))
                if document.projectId.isEmpty {
                    document.projectId = project.projectId
                }
                return document
            } catch {
                try self.recordRecovery(project: project, message: "Project Story decode failed after SQLite import: \(error.localizedDescription)")
                return ProjectStoryDocument.empty(projectId: project.projectId)
            }
        }
    }

    func saveProjectStory(_ story: ProjectStoryDocument, for project: ProjectRecord) throws {
        var normalized = story
        if normalized.projectId.isEmpty {
            normalized.projectId = project.projectId
        }
        let data = try JSONCoding.encoder.encode(normalized)
        try writeTransaction(project: project) { connection in
            try self.upsertProjectStoryDocument(normalized, data: data, connection: connection)
        }
    }

    func loadSceneStorySets(for project: ProjectRecord) throws -> [SceneStorySetDocument] {
        try ensureImported(for: project)
        return try withProjectConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT source_json FROM scene_story_imports
            WHERE project_id = ? AND source_kind = 'scene_story_set'
            ORDER BY imported_at DESC;
            """
            return try self.queryStrings(connection, sql: sql, bindings: [project.projectId])
                .compactMap { json in
                    do {
                        var document = try SceneStorySetDocument.decode(from: Data(json.utf8))
                        if document.projectId.isEmpty {
                            document.projectId = project.projectId
                        }
                        return document.normalized()
                    } catch {
                        try? self.recordRecovery(project: project, message: "SceneStory set decode failed after SQLite import: \(error.localizedDescription)")
                        return nil
                    }
                }
                .sorted { lhs, rhs in
                    if lhs.generatedAt == rhs.generatedAt {
                        return lhs.sceneStorySetId < rhs.sceneStorySetId
                    }
                    return lhs.generatedAt > rhs.generatedAt
                }
        }
    }

    func loadSceneStorySet(for project: ProjectRecord, sceneStorySetId: String?) throws -> SceneStorySetDocument? {
        try ensureImported(for: project)
        let trimmed = sceneStorySetId?.trimmed ?? ""
        if trimmed.isEmpty {
            return try loadSceneStorySets(for: project).first
        }
        return try withProjectConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT source_json FROM scene_story_imports
            WHERE project_id = ? AND source_kind = 'scene_story_set' AND source_id = ?
            ORDER BY imported_at DESC LIMIT 1;
            """
            guard let json = try self.optionalString(connection, sql: sql, bindings: [project.projectId, trimmed]) else {
                return nil
            }
            do {
                var document = try SceneStorySetDocument.decode(from: Data(json.utf8))
                if document.projectId.isEmpty {
                    document.projectId = project.projectId
                }
                return document.normalized()
            } catch {
                try self.recordRecovery(project: project, message: "SceneStory set \(trimmed) decode failed after SQLite import: \(error.localizedDescription)")
                return nil
            }
        }
    }

    func saveSceneStorySet(_ set: SceneStorySetDocument, for project: ProjectRecord) throws {
        let normalized = set.normalized()
        let data = try normalized.encoded(pretty: false)
        try writeTransaction(project: project) { connection in
            try self.upsertSceneStoryImport(
                project: project,
                sourceKind: "scene_story_set",
                sourceId: normalized.sceneStorySetId,
                sourcePath: "db/scene_story_imports/\(normalized.sceneStorySetId)",
                data: data,
                connection: connection
            )
        }
    }

    func loadStoryGenerationSessions(for project: ProjectRecord) throws -> [StoryGenerationSessionDocument] {
        try ensureImported(for: project)
        return try withProjectConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT session_json FROM story_generation_sessions
            WHERE project_id = ? ORDER BY started_at DESC;
            """
            return try self.queryStrings(connection, sql: sql, bindings: [project.projectId])
                .compactMap { json in
                    do {
                        var document = try JSONCoding.decoder.decode(StoryGenerationSessionDocument.self, from: Data(json.utf8))
                        if document.projectId.isEmpty {
                            document.projectId = project.projectId
                        }
                        return document.normalized()
                    } catch {
                        try? self.recordRecovery(project: project, message: "Story generation session decode failed after SQLite import: \(error.localizedDescription)")
                        return nil
                    }
                }
        }
    }

    func saveStoryGenerationSession(_ session: StoryGenerationSessionDocument, for project: ProjectRecord) throws {
        var normalized = session.normalized()
        if normalized.projectId.isEmpty {
            normalized.projectId = project.projectId
        }
        let data = try JSONCoding.encoder.encode(normalized)
        try writeTransaction(project: project) { connection in
            try self.upsertStoryGenerationSession(normalized, data: data, connection: connection)
        }
    }

    func loadProjectStoryLibrary(for project: ProjectRecord) throws -> ProjectStoryLibraryDocument {
        try ensureImported(for: project)
        return try withProjectConnection(project, readOnly: true) { connection in
            let activeStoryId = try self.optionalString(
                connection,
                sql: "SELECT active_story_id FROM project_story_library_state WHERE project_id = ? LIMIT 1;",
                bindings: [project.projectId]
            ) ?? ""
            let sql = """
            SELECT payload_json FROM project_stories
            WHERE project_id = ? ORDER BY updated_at DESC, title COLLATE NOCASE ASC;
            """
            let entries = try self.queryStrings(connection, sql: sql, bindings: [project.projectId])
                .compactMap { json in
                    do {
                        return try JSONCoding.decoder.decode(ProjectStoryLibraryEntry.self, from: Data(json.utf8)).normalized()
                    } catch {
                        try? self.recordRecovery(project: project, message: "Story Library entry decode failed after SQLite import: \(error.localizedDescription)")
                        return nil
                    }
                }
            return ProjectStoryLibraryDocument(
                projectId: project.projectId,
                entries: entries,
                activeStoryId: activeStoryId,
                updatedAt: DateFormats.now()
            ).normalized()
        }
    }

    func saveProjectStoryLibrary(_ library: ProjectStoryLibraryDocument, for project: ProjectRecord) throws {
        var normalized = library.normalized()
        if normalized.projectId.isEmpty {
            normalized.projectId = project.projectId
        }
        try writeTransaction(project: project) { connection in
            try self.upsertLibraryState(normalized, connection: connection)
            for entry in normalized.entries {
                try self.upsertProjectStoryEntry(entry, project: project, connection: connection)
            }
        }
    }

    func loadStorySignatures(for project: ProjectRecord) throws -> [StorySignatureDocument] {
        try ensureImported(for: project)
        return try withProjectConnection(project, readOnly: true) { connection in
            let sql = "SELECT signature_json FROM story_signatures WHERE project_id = ? ORDER BY updated_at DESC;"
            return try self.queryStrings(connection, sql: sql, bindings: [project.projectId])
                .compactMap { json in
                    do {
                        var document = try JSONCoding.decoder.decode(StorySignatureDocument.self, from: Data(json.utf8))
                        if document.projectId.isEmpty {
                            document.projectId = project.projectId
                        }
                        return document.normalized()
                    } catch {
                        try? self.recordRecovery(project: project, message: "Story signature decode failed after SQLite import: \(error.localizedDescription)")
                        return nil
                    }
                }
        }
    }

    func loadStorySignature(for project: ProjectRecord, storySignatureId: String?) throws -> StorySignatureDocument? {
        try ensureImported(for: project)
        let trimmed = storySignatureId?.trimmed ?? ""
        guard !trimmed.isEmpty else { return nil }
        return try withProjectConnection(project, readOnly: true) { connection in
            let sql = "SELECT signature_json FROM story_signatures WHERE project_id = ? AND story_signature_id = ? LIMIT 1;"
            guard let json = try self.optionalString(connection, sql: sql, bindings: [project.projectId, trimmed]) else {
                return nil
            }
            do {
                var document = try JSONCoding.decoder.decode(StorySignatureDocument.self, from: Data(json.utf8))
                if document.projectId.isEmpty {
                    document.projectId = project.projectId
                }
                return document.normalized()
            } catch {
                try self.recordRecovery(project: project, message: "Story signature \(trimmed) decode failed after SQLite import: \(error.localizedDescription)")
                return nil
            }
        }
    }

    func saveStorySignature(_ signature: StorySignatureDocument, for project: ProjectRecord) throws {
        var normalized = signature.normalized()
        if normalized.projectId.isEmpty {
            normalized.projectId = project.projectId
        }
        let data = try JSONCoding.encoder.encode(normalized)
        try writeTransaction(project: project) { connection in
            try self.upsertStorySignature(normalized, data: data, connection: connection)
        }
    }

    func loadProjectStoryVersion(for project: ProjectRecord, projectStoryId: String, storyVersionId: String) throws -> ProjectStoryVersionDocument? {
        try ensureImported(for: project)
        guard !projectStoryId.trimmed.isEmpty, !storyVersionId.trimmed.isEmpty else { return nil }
        return try withProjectConnection(project, readOnly: true) { connection in
            let sql = """
            SELECT story_payload_json FROM story_versions
            WHERE project_story_id = ? AND story_version_id = ? LIMIT 1;
            """
            guard let json = try self.optionalString(connection, sql: sql, bindings: [projectStoryId, storyVersionId]) else {
                return nil
            }
            do {
                return try JSONCoding.decoder.decode(ProjectStoryVersionDocument.self, from: Data(json.utf8))
            } catch {
                try self.recordRecovery(project: project, message: "Story version \(storyVersionId) decode failed after SQLite import: \(error.localizedDescription)")
                return nil
            }
        }
    }

    func saveProjectStoryVersion(_ version: ProjectStoryVersionDocument, for project: ProjectRecord) throws {
        var normalized = version
        if normalized.projectStoryId.trimmed.isEmpty {
            normalized.projectStoryId = deterministicId(kind: "project_story", components: [project.projectId, normalized.story.storyId, normalized.storyVersionId])
        }
        let data = try JSONCoding.encoder.encode(normalized)
        try writeTransaction(project: project) { connection in
            try self.insertStoryVersionIfNeeded(normalized, project: project, data: data, connection: connection)
        }
    }

    // MARK: - Import

    private func ensureImported(for project: ProjectRecord) throws {
        _ = project
    }

    // MARK: - Upserts

    private func upsertProjectStoryDocument(_ document: ProjectStoryDocument, data: Data, connection: OpaquePointer) throws {
        let sql = """
        INSERT INTO project_story_documents (
            project_id, accepted_story_id, project_story_id, story_json, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(project_id) DO UPDATE SET
            accepted_story_id = excluded.accepted_story_id,
            project_story_id = excluded.project_story_id,
            story_json = excluded.story_json,
            updated_at = excluded.updated_at,
            record_revision = project_story_documents.record_revision + 1;
        """
        try execute(sql, connection: connection, bindings: [
            document.projectId,
            document.acceptedStoryId,
            document.projectStoryId ?? "",
            String(decoding: data, as: UTF8.self),
            document.updatedAt
        ])
    }

    private func upsertSceneStoryImport(
        project: ProjectRecord,
        sourceKind: String,
        sourceId: String,
        sourcePath: String,
        data: Data,
        connection: OpaquePointer
    ) throws {
        let sourceHash = sha256Hex(data)
        let importRowId = deterministicId(kind: "scene_story_import", components: [project.projectId, sourceKind, sourceId, sourceHash])
        let sql = """
        INSERT INTO scene_story_imports (
            import_row_id, project_id, source_kind, source_id, source_path, source_sha256, source_json, imported_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_id, source_kind, source_id, source_sha256) DO UPDATE SET
            source_path = excluded.source_path,
            source_json = excluded.source_json,
            imported_at = excluded.imported_at;
        """
        try execute(sql, connection: connection, bindings: [
            importRowId,
            project.projectId,
            sourceKind,
            sourceId,
            sourcePath,
            sourceHash,
            String(decoding: data, as: UTF8.self),
            DateFormats.now()
        ])
    }

    private func upsertStoryGenerationSession(_ session: StoryGenerationSessionDocument, data: Data, connection: OpaquePointer) throws {
        let sql = """
        INSERT INTO story_generation_sessions (
            generation_session_id, project_id, status, started_at, completed_at, session_json, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(generation_session_id) DO UPDATE SET
            project_id = excluded.project_id,
            status = excluded.status,
            started_at = excluded.started_at,
            completed_at = excluded.completed_at,
            session_json = excluded.session_json,
            updated_at = excluded.updated_at;
        """
        try execute(sql, connection: connection, bindings: [
            session.generationSessionId,
            session.projectId,
            session.status,
            session.startedAt,
            session.completedAt,
            String(decoding: data, as: UTF8.self),
            DateFormats.now()
        ])
    }

    private func upsertStorySignature(_ signature: StorySignatureDocument, data: Data, connection: OpaquePointer) throws {
        let sql = """
        INSERT INTO story_signatures (
            story_signature_id, project_id, project_story_id, story_version_id, title, context_class, signature_json, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(story_signature_id) DO UPDATE SET
            project_id = excluded.project_id,
            project_story_id = excluded.project_story_id,
            story_version_id = excluded.story_version_id,
            title = excluded.title,
            context_class = excluded.context_class,
            signature_json = excluded.signature_json,
            updated_at = excluded.updated_at;
        """
        try execute(sql, connection: connection, bindings: [
            signature.storySignatureId,
            signature.projectId,
            signature.projectStoryId,
            signature.storyVersionId,
            signature.title,
            signature.contextClass.rawValue,
            String(decoding: data, as: UTF8.self),
            signature.updatedAt
        ])
    }

    private func insertStoryVersionIfNeeded(
        _ version: ProjectStoryVersionDocument,
        project: ProjectRecord,
        data: Data,
        connection: OpaquePointer
    ) throws {
        let projectStoryId = version.projectStoryId.trimmed.isEmpty
            ? deterministicId(kind: "project_story", components: [project.projectId, version.story.storyId, version.storyVersionId])
            : version.projectStoryId.trimmed
        try upsertProjectStoryShell(projectStoryId: projectStoryId, project: project, title: version.story.title, connection: connection)
        let fingerprint = sha256Hex(data)
        if let existing = try optionalString(
            connection,
            sql: "SELECT content_fingerprint FROM story_versions WHERE story_version_id = ? LIMIT 1;",
            bindings: [version.storyVersionId]
        ) {
            if existing == fingerprint {
                return
            }
            throw ScreenGraphError.capture("Published Story version \(version.storyVersionId) already exists with different content.")
        }
        let versionNumber = try nextVersionNumber(projectStoryId: projectStoryId, connection: connection)
        let sql = """
        INSERT INTO story_versions (
            story_version_id, project_story_id, version_number, lifecycle_state, parent_story_version_id,
            source_story_suggestion_id, reason, story_payload_json, lock_manifest_json, content_fingerprint,
            created_at, updated_at
        ) VALUES (?, ?, ?, 'published', ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try execute(sql, connection: connection, bindings: [
            version.storyVersionId,
            projectStoryId,
            versionNumber,
            version.parentStoryVersionId.trimmed.isEmpty ? nil : version.parentStoryVersionId,
            version.sourceStorySuggestionId,
            version.reason,
            String(decoding: data, as: UTF8.self),
            try jsonString(version.lockManifest),
            fingerprint,
            version.createdAt,
            version.updatedAt
        ])
        try insertStoryStructure(version: version, connection: connection)
    }

    private func upsertProjectStoryShell(projectStoryId: String, project: ProjectRecord, title: String, connection: OpaquePointer) throws {
        let entry = ProjectStoryLibraryEntry(
            projectStoryId: projectStoryId,
            editorialState: .kept,
            productionState: .notStarted,
            title: title,
            createdAt: DateFormats.now(),
            updatedAt: DateFormats.now()
        ).normalized()
        try upsertProjectStoryEntry(entry, project: project, connection: connection)
    }

    private func upsertProjectStoryEntry(_ entry: ProjectStoryLibraryEntry, project: ProjectRecord, connection: OpaquePointer) throws {
        let normalized = entry.normalized()
        let projectStoryId = normalized.projectStoryId.trimmed.isEmpty
            ? deterministicId(kind: "project_story", components: [project.projectId, normalized.sourceSceneStorySetId, normalized.sourceStoryId, normalized.libraryEntryId])
            : normalized.projectStoryId
        let currentVersionId = normalized.currentVersionId.trimmed.isEmpty
            ? nil
            : (try storyVersionExists(normalized.currentVersionId, connection: connection) ? normalized.currentVersionId : nil)
        var payloadEntry = normalized
        payloadEntry.projectStoryId = projectStoryId
        payloadEntry.currentVersionId = currentVersionId ?? ""
        let sql = """
        INSERT INTO project_stories (
            project_story_id, project_id, library_entry_id, source_scene_story_set_id, source_story_id,
            current_story_version_id, story_signature_id, editorial_state, production_state, title,
            lens_ids_json, payload_json, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(project_story_id) DO UPDATE SET
            library_entry_id = excluded.library_entry_id,
            source_scene_story_set_id = excluded.source_scene_story_set_id,
            source_story_id = excluded.source_story_id,
            current_story_version_id = excluded.current_story_version_id,
            story_signature_id = excluded.story_signature_id,
            editorial_state = excluded.editorial_state,
            production_state = excluded.production_state,
            title = excluded.title,
            lens_ids_json = excluded.lens_ids_json,
            payload_json = excluded.payload_json,
            updated_at = excluded.updated_at,
            record_revision = project_stories.record_revision + 1;
        """
        try execute(sql, connection: connection, bindings: [
            projectStoryId,
            project.projectId,
            normalized.libraryEntryId,
            normalized.sourceSceneStorySetId,
            normalized.sourceStoryId,
            currentVersionId as Any?,
            normalized.storySignatureId,
            normalized.editorialState.rawValue,
            normalized.productionState.rawValue,
            normalized.title,
            try jsonString(payloadEntry.lensIds),
            try jsonString(payloadEntry),
            normalized.createdAt,
            normalized.updatedAt
        ])
    }

    private func upsertLibraryState(_ library: ProjectStoryLibraryDocument, connection: OpaquePointer) throws {
        let sql = """
        INSERT INTO project_story_library_state (project_id, active_story_id, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(project_id) DO UPDATE SET
            active_story_id = excluded.active_story_id,
            updated_at = excluded.updated_at,
            record_revision = project_story_library_state.record_revision + 1;
        """
        try execute(sql, connection: connection, bindings: [library.projectId, library.activeStoryId, library.updatedAt])
    }

    private func insertProjectionRebuild(
        project: ProjectRecord,
        projectionKind: String,
        status: String,
        details: [String: String],
        connection: OpaquePointer
    ) throws {
        let completedAt = DateFormats.now()
        let rebuildId = deterministicId(kind: "projection_rebuild", components: [project.projectId, projectionKind, completedAt])
        try execute("""
        INSERT INTO project_projection_rebuilds (
            rebuild_id, project_id, projection_kind, status, details_json, completed_at
        ) VALUES (?, ?, ?, ?, ?, ?);
        """, connection: connection, bindings: [
            rebuildId,
            project.projectId,
            projectionKind,
            status,
            try jsonString(details),
            completedAt
        ])
    }

    private func insertStoryStructure(version: ProjectStoryVersionDocument, connection: OpaquePointer) throws {
        let storyVersionId = version.storyVersionId
        let story = version.story.normalized()
        for scene in story.scenes {
            let sceneRowId = deterministicId(kind: "story_scene", components: [storyVersionId, scene.sceneId, "\(scene.order)"])
            try execute("""
            INSERT INTO story_scenes (
                scene_row_id, story_version_id, source_scene_id, scene_order, title, scene_function,
                support_status, locked, scene_payload_json, content_fingerprint, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, connection: connection, bindings: [
                sceneRowId,
                storyVersionId,
                scene.sceneId,
                scene.order,
                scene.title,
                scene.sceneFunction,
                scene.supportStatus,
                scene.locked ? 1 : 0,
                try jsonString(scene),
                stableHash(scene, length: 32),
                version.createdAt,
                version.updatedAt
            ])
            for beat in scene.sceneBeats {
                try insertBeat(
                    beat,
                    scene: scene,
                    sceneRowId: sceneRowId,
                    storyVersionId: storyVersionId,
                    version: version,
                    connection: connection
                )
            }
        }
    }

    private func insertBeat(
        _ beat: SceneStoryBeat,
        scene: SceneStoryScene,
        sceneRowId: String,
        storyVersionId: String,
        version: ProjectStoryVersionDocument,
        connection: OpaquePointer
    ) throws {
        let normalized = beat.normalized()
        let beatRowId = deterministicId(kind: "story_beat", components: [sceneRowId, normalized.beatId, "\(normalized.order)"])
        let productionContract = mergedProductionContract(for: normalized, scene: scene)
        try execute("""
        INSERT INTO story_beats (
            beat_row_id, scene_row_id, source_beat_id, beat_order, title, beat_description, shot_type,
            support_status, evidence_basis, locked, prompt_intent, continuity_in, continuity_out,
            beat_payload_json, production_contract_json, content_fingerprint, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, connection: connection, bindings: [
            beatRowId,
            sceneRowId,
            normalized.beatId,
            normalized.order,
            synthesizedBeatTitle(normalized),
            normalized.beatDescription,
            normalized.shotType,
            normalized.supportStatus,
            normalized.evidenceBasis,
            normalized.locked ? 1 : 0,
            normalized.promptIntent,
            normalized.continuityIn,
            normalized.continuityOut,
            try jsonString(normalized),
            try jsonString(productionContract),
            stableHash(normalized, length: 32),
            version.createdAt,
            version.updatedAt
        ])
        var entityProjection = try insertEntities(
            for: normalized,
            contract: productionContract,
            storyVersionId: storyVersionId,
            beatRowId: beatRowId,
            connection: connection
        )
        try validateAcyclicDependencies(productionContract.events)
        let eventRows = try insertEvents(
            productionContract.events,
            beat: normalized,
            beatRowId: beatRowId,
            storyVersionId: storyVersionId,
            entityProjection: &entityProjection,
            connection: connection
        )
        try insertWorldStateDeltas(
            productionContract.worldStateDelta,
            beatRowId: beatRowId,
            storyVersionId: storyVersionId,
            entityProjection: &entityProjection,
            connection: connection
        )
        try insertEditorialShots(
            productionContract.editorialShots,
            contract: productionContract,
            beat: normalized,
            beatRowId: beatRowId,
            eventRows: eventRows,
            connection: connection
        )
    }

    private func mergedProductionContract(for beat: SceneStoryBeat, scene: SceneStoryScene) -> SceneBeatProductionContract {
        let legacy = legacyProductionContract(for: beat, scene: scene)
        guard var contract = beat.productionContract else {
            return legacy
        }
        if contract.durationValue <= 0 {
            contract.durationValue = legacy.durationValue
        }
        if contract.rateNum <= 0 {
            contract.rateNum = legacy.rateNum
        }
        if contract.rateDen <= 0 {
            contract.rateDen = legacy.rateDen
        }
        if contract.continuityMode.trimmed.isEmpty {
            contract.continuityMode = legacy.continuityMode
        }
        if contract.entityRefs.isEmpty {
            contract.entityRefs = beat.entityRefs.isEmpty ? legacy.entityRefs : beat.entityRefs
        }
        if contract.worldStateDelta.isEmpty {
            contract.worldStateDelta = beat.worldStateDelta
        }
        if contract.events.isEmpty {
            contract.events = legacy.events
        }
        if contract.editorialShots.isEmpty {
            contract.editorialShots = beat.editorialShots.isEmpty ? legacy.editorialShots : beat.editorialShots
        }
        if contract.constraints.isEmpty {
            contract.constraints = legacy.constraints
        }
        if contract.generationPolicy.isEmpty {
            contract.generationPolicy = legacy.generationPolicy
        }
        return contract
    }

    private func insertEntities(
        for beat: SceneStoryBeat,
        contract: SceneBeatProductionContract,
        storyVersionId: String,
        beatRowId: String,
        connection: OpaquePointer
    ) throws -> BeatEntityProjection {
        var projection = BeatEntityProjection()
        let refs = projectedEntityRefs(for: beat, contract: contract)
        for (index, ref) in refs.enumerated() {
            let entityId = ref.entityId.trimmed.isEmpty
                ? "provisional_\(safeIdentifier(beat.beatId))_entity_\(String(format: "%02d", index + 1))"
                : ref.entityId.trimmed
            let displayLabel = ref.displayLabel.trimmed.isEmpty ? entityId : ref.displayLabel.trimmed
            let role = ref.role.trimmed.isEmpty ? "subject" : ref.role.trimmed
            let referenceSetRowId = try upsertReferenceSetIfNeeded(
                referenceSetId: ref.referenceSetId,
                label: displayLabel,
                storyVersionId: storyVersionId,
                connection: connection
            )
            let entityRowId = deterministicId(kind: "story_entity", components: [storyVersionId, entityId])
            let resolutionStatus = referenceSetRowId == nil && entityId.hasPrefix("provisional_") ? "provisional" : "unresolved"
            let resolutionBasis = referenceSetRowId == nil ? "legacy_or_contract_label" : "unresolved_reference_set"
            try execute("""
            INSERT INTO story_entities (
                entity_row_id, story_version_id, entity_id, kind, display_label, resolution_status,
                resolution_basis, reference_set_row_id, appearance_invariants_json, initial_state_json,
                final_state_json, allowed_variation_json, forbidden_transformations_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '{}', '{}', '[]', ?, ?, ?)
            ON CONFLICT(story_version_id, entity_id) DO NOTHING;
            """, connection: connection, bindings: [
                entityRowId,
                storyVersionId,
                entityId,
                role,
                displayLabel,
                resolutionStatus,
                resolutionBasis,
                referenceSetRowId as Any?,
                try jsonString(ref.appearanceInvariants),
                try jsonString(ref.forbiddenTransformations),
                DateFormats.now(),
                DateFormats.now()
            ])
            try execute("""
            INSERT OR IGNORE INTO beat_entity_refs (beat_row_id, entity_row_id, role, visibility, state_json)
            VALUES (?, ?, ?, '', '{}');
            """, connection: connection, bindings: [beatRowId, entityRowId, role])
            projection.rowsByEntityId[entityId] = entityRowId
            projection.orderedRows.append(entityRowId)
        }
        return projection
    }

    private func projectedEntityRefs(for beat: SceneStoryBeat, contract: SceneBeatProductionContract) -> [SceneBeatEntityRef] {
        var refs = contract.entityRefs
        if refs.isEmpty {
            refs = beat.entityRefs
        }
        if refs.isEmpty {
            refs = beat.subjects.enumerated().map { index, label in
                SceneBeatEntityRef(
                    entityId: "provisional_\(safeIdentifier(beat.beatId))_subject_\(String(format: "%02d", index + 1))",
                    referenceSetId: "",
                    role: "subject",
                    displayLabel: label.trimmed,
                    appearanceInvariants: [],
                    forbiddenTransformations: []
                )
            }
        }
        var seen: Set<String> = []
        return refs.filter { ref in
            let key = [ref.entityId.trimmed, ref.role.trimmed, ref.displayLabel.trimmed].joined(separator: "|")
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func upsertReferenceSetIfNeeded(
        referenceSetId: String,
        label: String,
        storyVersionId: String,
        connection: OpaquePointer
    ) throws -> String? {
        let trimmed = referenceSetId.trimmed
        guard !trimmed.isEmpty else { return nil }
        let rowId = deterministicId(kind: "reference_set", components: [storyVersionId, trimmed])
        try execute("""
        INSERT INTO reference_sets (
            reference_set_row_id, story_version_id, reference_set_id, label, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 'unresolved', ?, ?)
        ON CONFLICT(story_version_id, reference_set_id) DO UPDATE SET
            label = excluded.label,
            updated_at = excluded.updated_at;
        """, connection: connection, bindings: [rowId, storyVersionId, trimmed, label, DateFormats.now(), DateFormats.now()])
        return rowId
    }

    private func ensureUnresolvedEntity(
        entityId: String,
        storyVersionId: String,
        beatRowId: String,
        role: String,
        entityProjection: inout BeatEntityProjection,
        connection: OpaquePointer
    ) throws -> String? {
        let trimmed = entityId.trimmed
        guard !trimmed.isEmpty else { return nil }
        if let rowId = entityProjection.rowsByEntityId[trimmed] {
            return rowId
        }
        let rowId = deterministicId(kind: "story_entity", components: [storyVersionId, trimmed])
        try execute("""
        INSERT INTO story_entities (
            entity_row_id, story_version_id, entity_id, kind, display_label, resolution_status,
            resolution_basis, reference_set_row_id, appearance_invariants_json, initial_state_json,
            final_state_json, allowed_variation_json, forbidden_transformations_json, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 'unresolved', 'contract_reference', NULL, '[]', '{}', '{}', '[]', '[]', ?, ?)
        ON CONFLICT(story_version_id, entity_id) DO NOTHING;
        """, connection: connection, bindings: [rowId, storyVersionId, trimmed, role, trimmed, DateFormats.now(), DateFormats.now()])
        try execute("""
        INSERT OR IGNORE INTO beat_entity_refs (beat_row_id, entity_row_id, role, visibility, state_json)
        VALUES (?, ?, ?, '', '{}');
        """, connection: connection, bindings: [beatRowId, rowId, role])
        entityProjection.rowsByEntityId[trimmed] = rowId
        entityProjection.orderedRows.append(rowId)
        return rowId
    }

    private func insertEvents(
        _ events: [SceneBeatEvent],
        beat: SceneStoryBeat,
        beatRowId: String,
        storyVersionId: String,
        entityProjection: inout BeatEntityProjection,
        connection: OpaquePointer
    ) throws -> [String: (rowId: String, event: SceneBeatEvent)] {
        var output: [String: (rowId: String, event: SceneBeatEvent)] = [:]
        for (index, rawEvent) in events.enumerated() {
            var event = rawEvent
            let eventId = event.eventId.trimmed.isEmpty ? "event_\(String(format: "%03d", index + 1))" : event.eventId.trimmed
            event.eventId = eventId
            if event.action.trimmed.isEmpty {
                event.action = beat.action.trimmed.isEmpty ? beat.beatDescription : beat.action
            }
            let eventRowId = deterministicId(kind: "beat_event", components: [beatRowId, eventId])
            let actorRowId = try ensureUnresolvedEntity(
                entityId: event.actorEntityId,
                storyVersionId: storyVersionId,
                beatRowId: beatRowId,
                role: "actor",
                entityProjection: &entityProjection,
                connection: connection
            ) ?? entityProjection.orderedRows.first
            let objectRowId = try ensureUnresolvedEntity(
                entityId: event.objectEntityId,
                storyVersionId: storyVersionId,
                beatRowId: beatRowId,
                role: "object",
                entityProjection: &entityProjection,
                connection: connection
            )
            try execute("""
            INSERT INTO beat_events (
                event_row_id, beat_row_id, event_id, start_value, duration_value, rate_num, rate_den,
                actor_entity_row_id, object_entity_row_id, action, attention_track, hold_duration_value,
                easing, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, connection: connection, bindings: [
                eventRowId,
                beatRowId,
                eventId,
                max(0, event.startValue),
                positive(event.durationValue, fallback: 24),
                positive(event.rateNum, fallback: 24),
                positive(event.rateDen, fallback: 1),
                actorRowId as Any?,
                objectRowId as Any?,
                event.action,
                event.attentionTrack,
                max(0, event.holdDurationValue),
                event.easing,
                try jsonString(event)
            ])
            output[eventId] = (eventRowId, event)
        }
        for event in events {
            let eventId = event.eventId.trimmed
            guard let eventRow = output[eventId] else { continue }
            for dependencyId in event.dependsOn.map(\.trimmed).filter({ !$0.isEmpty }) {
                guard let dependencyRow = output[dependencyId]?.rowId else { continue }
                try execute("""
                INSERT OR IGNORE INTO beat_event_dependencies (event_row_id, depends_on_event_row_id, dependency_kind)
                VALUES (?, ?, 'depends_on');
                """, connection: connection, bindings: [eventRow.rowId, dependencyRow])
            }
        }
        return output
    }

    private func insertWorldStateDeltas(
        _ deltas: [SceneBeatWorldStateDelta],
        beatRowId: String,
        storyVersionId: String,
        entityProjection: inout BeatEntityProjection,
        connection: OpaquePointer
    ) throws {
        for (index, delta) in deltas.enumerated() {
            guard let entityRowId = try ensureUnresolvedEntity(
                entityId: delta.entityId,
                storyVersionId: storyVersionId,
                beatRowId: beatRowId,
                role: "state",
                entityProjection: &entityProjection,
                connection: connection
            ) else {
                continue
            }
            try execute("""
            INSERT INTO beat_world_state_deltas (
                delta_row_id, beat_row_id, entity_row_id, property_path, from_json, to_json, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """, connection: connection, bindings: [
                deterministicId(kind: "beat_world_state_delta", components: [beatRowId, "\(index)", delta.entityId, delta.propertyPath]),
                beatRowId,
                entityRowId,
                delta.propertyPath.trimmed.isEmpty ? "unspecified" : delta.propertyPath.trimmed,
                try jsonString(delta.from),
                try jsonString(delta.to),
                delta.source.trimmed.isEmpty ? "contract" : delta.source.trimmed
            ])
        }
    }

    private func insertEditorialShots(
        _ shots: [SceneEditorialShotContract],
        contract: SceneBeatProductionContract,
        beat: SceneStoryBeat,
        beatRowId: String,
        eventRows: [String: (rowId: String, event: SceneBeatEvent)],
        connection: OpaquePointer
    ) throws {
        for (index, rawShot) in shots.enumerated() {
            var shot = rawShot
            let shotId = shot.shotId.trimmed.isEmpty ? "shot_\(String(format: "%03d", index + 1))" : shot.shotId.trimmed
            shot.shotId = shotId
            let shotRowId = deterministicId(kind: "editorial_shot", components: [beatRowId, shotId])
            try execute("""
            INSERT INTO editorial_shots (
                shot_row_id, beat_row_id, shot_id, shot_order, duration_value, rate_num, rate_den,
                continuity_mode, camera_json, lighting_json, audio_json, performance_json, spatial_blocking_json,
                field_policies_json, generation_policy_json, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, connection: connection, bindings: [
                shotRowId,
                beatRowId,
                shotId,
                max(1, shot.order),
                positive(shot.durationValue, fallback: positive(contract.durationValue, fallback: 120)),
                positive(shot.rateNum, fallback: positive(contract.rateNum, fallback: 24)),
                positive(shot.rateDen, fallback: positive(contract.rateDen, fallback: 1)),
                shot.continuityMode.trimmed.isEmpty ? contract.continuityMode : shot.continuityMode,
                try jsonString(shot.camera),
                try jsonString(shot.lighting),
                try jsonString(shot.audio),
                try jsonString(shot.performance),
                try jsonString(shot.spatialBlocking),
                try jsonString(shot.fieldPolicies),
                try jsonString(shot.generationPolicy.isEmpty ? contract.generationPolicy : shot.generationPolicy),
                try jsonString(shot)
            ])
            let shotEventIds = shot.eventIds.isEmpty ? Array(eventRows.keys).sorted() : shot.eventIds
            for eventId in shotEventIds.map(\.trimmed).filter({ !$0.isEmpty }) {
                guard let eventRow = eventRows[eventId] else { continue }
                try execute("""
                INSERT OR IGNORE INTO shot_event_spans (shot_row_id, event_row_id, start_value, duration_value, rate_num, rate_den)
                VALUES (?, ?, ?, ?, ?, ?);
                """, connection: connection, bindings: [
                    shotRowId,
                    eventRow.rowId,
                    max(0, eventRow.event.startValue),
                    positive(eventRow.event.durationValue, fallback: 24),
                    positive(eventRow.event.rateNum, fallback: 24),
                    positive(eventRow.event.rateDen, fallback: 1)
                ])
            }
            let constraints = shot.constraints.isEmpty ? contract.constraints : shot.constraints
            for (constraintIndex, constraint) in constraints.enumerated() {
                let rule = constraint.rule.trimmed
                guard !rule.isEmpty else { continue }
                try execute("""
                INSERT INTO shot_constraints (
                    constraint_row_id, shot_row_id, rule, strength, priority, scope, source, failure_action
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """, connection: connection, bindings: [
                    deterministicId(kind: "shot_constraint", components: [shotRowId, "\(constraintIndex)", rule]),
                    shotRowId,
                    rule,
                    normalizedConstraintStrength(constraint.strength),
                    min(100, max(0, constraint.priority)),
                    constraint.scope.trimmed.isEmpty ? "shot" : constraint.scope.trimmed,
                    constraint.source.trimmed.isEmpty ? "contract" : constraint.source.trimmed,
                    constraint.failureAction.trimmed.isEmpty ? "review" : constraint.failureAction.trimmed
                ])
            }
            let criteria = shot.acceptanceCriteria.isEmpty ? beat.acceptanceCriteria : shot.acceptanceCriteria
            for (criterionIndex, criterion) in criteria.enumerated() {
                let text = criterion.criterion.trimmed
                guard !text.isEmpty else { continue }
                try execute("""
                INSERT INTO shot_acceptance_criteria (
                    criterion_row_id, shot_row_id, criterion, severity, method, repair_action
                ) VALUES (?, ?, ?, ?, ?, ?);
                """, connection: connection, bindings: [
                    deterministicId(kind: "shot_acceptance", components: [shotRowId, "\(criterionIndex)", text]),
                    shotRowId,
                    text,
                    normalizedCriterionSeverity(criterion.severity),
                    criterion.method.trimmed.isEmpty ? "human_review" : criterion.method.trimmed,
                    criterion.repairAction
                ])
            }
        }
    }

    private func validateAcyclicDependencies(_ events: [SceneBeatEvent]) throws {
        var graph: [String: [String]] = [:]
        for (index, event) in events.enumerated() {
            let eventId = event.eventId.trimmed.isEmpty ? "event_\(String(format: "%03d", index + 1))" : event.eventId.trimmed
            if graph[eventId] != nil {
                throw ScreenGraphError.capture("Beat event id \(eventId) is duplicated.")
            }
            graph[eventId] = event.dependsOn.map(\.trimmed).filter { !$0.isEmpty }
        }
        var visiting: Set<String> = []
        var visited: Set<String> = []
        func visit(_ eventId: String) throws {
            guard graph[eventId] != nil else { return }
            if visiting.contains(eventId) {
                throw ScreenGraphError.capture("Beat event dependency cycle includes \(eventId).")
            }
            guard !visited.contains(eventId) else { return }
            visiting.insert(eventId)
            for dependency in graph[eventId] ?? [] {
                try visit(dependency)
            }
            visiting.remove(eventId)
            visited.insert(eventId)
        }
        for eventId in graph.keys {
            try visit(eventId)
        }
    }

    private func positive(_ value: Int, fallback: Int) -> Int {
        value > 0 ? value : fallback
    }

    private func normalizedConstraintStrength(_ value: String) -> String {
        let allowed = Set(["hard", "soft", "exploratory", "forbidden"])
        let trimmed = value.trimmed
        return allowed.contains(trimmed) ? trimmed : "soft"
    }

    private func normalizedCriterionSeverity(_ value: String) -> String {
        let allowed = Set(["reject", "repairable", "advisory"])
        let trimmed = value.trimmed
        return allowed.contains(trimmed) ? trimmed : "advisory"
    }

    private func legacyProductionContract(for beat: SceneStoryBeat, scene: SceneStoryScene) -> SceneBeatProductionContract {
        let event = SceneBeatEvent(
            eventId: "event_001",
            startValue: 0,
            durationValue: 120,
            rateNum: 24,
            rateDen: 1,
            actorEntityId: "",
            objectEntityId: "",
            action: beat.action.trimmed.isEmpty ? beat.beatDescription : beat.action,
            dependsOn: [],
            attentionTrack: beat.meaningProof,
            holdDurationValue: 0,
            easing: ""
        )
        let shot = SceneEditorialShotContract(
            shotId: "shot_001",
            order: 1,
            durationValue: 120,
            rateNum: 24,
            rateDen: 1,
            continuityMode: "single_beat_shot",
            eventIds: [event.eventId],
            camera: ["summary": .string(beat.camera)],
            lighting: ["summary": .string(beat.lighting)],
            audio: ["dialogue_intent": .string(beat.dialogue.isEmpty ? "unknown" : "specified")],
            performance: ["summary": .string(beat.emotionalTurn.performanceDirection.joined(separator: "\n"))],
            spatialBlocking: ["setting": .string(beat.setting), "composition": .string(beat.composition)],
            fieldPolicies: [:],
            generationPolicy: ["source": .string("legacy_scene_story_compiler")],
            constraints: beat.negativeConstraints.map {
                SceneProductionConstraint(rule: $0, strength: "forbidden", priority: 80, scope: "shot", source: "legacy_negative_constraint", failureAction: "reject_take")
            },
            acceptanceCriteria: []
        )
        return SceneBeatProductionContract(
            durationValue: 120,
            rateNum: 24,
            rateDen: 1,
            creativeLatitude: beat.locked ? 0.2 : 0.5,
            continuityMode: "single_beat_shot",
            entityRefs: beat.subjects.enumerated().map { index, label in
                SceneBeatEntityRef(
                    entityId: "provisional_\(safeIdentifier(beat.beatId))_subject_\(String(format: "%02d", index + 1))",
                    role: "subject",
                    displayLabel: label.trimmed
                )
            },
            worldStateDelta: [],
            events: [event],
            editorialShots: [shot],
            constraints: shot.constraints,
            generationPolicy: [
                "compiler": .string("legacy_scene_story_compiler"),
                "scene_id": .string(scene.sceneId)
            ]
        )
    }

    private func synthesizedBeatTitle(_ beat: SceneStoryBeat) -> String {
        let candidates = [
            beat.beatDescription.split(separator: ".").first.map(String.init) ?? "",
            beat.shotType,
            beat.action,
            "Beat \(beat.order)"
        ]
        return candidates.map(\.trimmed).first { !$0.isEmpty } ?? "Beat \(beat.order)"
    }

    // MARK: - DB Helpers

    private func storyVersionExists(_ storyVersionId: String, connection: OpaquePointer) throws -> Bool {
        try optionalString(
            connection,
            sql: "SELECT story_version_id FROM story_versions WHERE story_version_id = ? LIMIT 1;",
            bindings: [storyVersionId]
        ) != nil
    }

    private func nextVersionNumber(projectStoryId: String, connection: OpaquePointer) throws -> Int {
        let sql = "SELECT COALESCE(MAX(version_number), 0) + 1 FROM story_versions WHERE project_story_id = ?;"
        return try scalarInt(connection, sql: sql, bindings: [projectStoryId])
    }

    private func withProjectConnection<T>(
        _ project: ProjectRecord,
        readOnly: Bool = false,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        let url = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        return try LitScenesDesktopDatabase.withConnection(url: url, flags: flags, context: "Project Story DB", body)
    }

    private func writeTransaction(project: ProjectRecord, _ body: @escaping (OpaquePointer) throws -> Void) throws {
        try Self.queue.sync {
            try withProjectConnection(project, readOnly: false) { connection in
                try beginImmediate(connection)
                do {
                    try body(connection)
                    try projectIntegrityChecks(connection)
                    try litScenesSQLiteExecute(connection, "COMMIT;", context: "Project Story DB")
                } catch {
                    try? litScenesSQLiteExecute(connection, "ROLLBACK;", context: "Project Story DB")
                    throw error
                }
            }
        }
    }

    private func beginImmediate(_ connection: OpaquePointer) throws {
        let delays: [TimeInterval] = [0, 0.1, 0.25, 0.5, 1.0, 2.0]
        var lastMessage = ""
        for delay in delays {
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            let result = sqlite3_exec(connection, "BEGIN IMMEDIATE;", nil, nil, nil)
            if result == SQLITE_OK {
                return
            }
            lastMessage = litScenesSQLiteMessage(connection)
            guard result == SQLITE_BUSY || result == SQLITE_LOCKED else {
                throw ScreenGraphError.capture("Project Story DB begin failed: \(lastMessage)")
            }
        }
        throw ScreenGraphError.capture("Project Story DB begin failed after busy retries: \(lastMessage)")
    }

    private func projectIntegrityChecks(_ connection: OpaquePointer) throws {
        let quickCheck = try optionalString(connection, sql: "PRAGMA quick_check;", bindings: []) ?? ""
        guard quickCheck == "ok" else {
            throw ScreenGraphError.capture("Project Story DB quick_check failed: \(quickCheck)")
        }
        let failureCount = try foreignKeyViolationCount(connection)
        guard failureCount == 0 else {
            throw ScreenGraphError.capture("Project Story DB foreign_key_check failed: \(failureCount) violation(s)")
        }
    }

    private func foreignKeyViolationCount(_ connection: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA foreign_key_check;", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project Story DB foreign_key_check prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        var count = 0
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                count += 1
            } else if result == SQLITE_DONE {
                return count
            } else {
                throw ScreenGraphError.capture("Project Story DB foreign_key_check failed: \(litScenesSQLiteMessage(connection))")
            }
        }
    }

    private func execute(_ sql: String, connection: OpaquePointer, bindings: [Any?]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project Story DB prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenGraphError.capture("Project Story DB step failed: \(litScenesSQLiteMessage(connection))")
        }
    }

    private func optionalString(_ connection: OpaquePointer, sql: String, bindings: [Any?]) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project Story DB query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return litScenesSQLiteColumnText(statement, 0)
    }

    private func queryStrings(_ connection: OpaquePointer, sql: String, bindings: [Any?]) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project Story DB query prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var output: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            output.append(litScenesSQLiteColumnText(statement, 0))
        }
        return output
    }

    private func scalarInt(_ connection: OpaquePointer, sql: String, bindings: [Any?]) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ScreenGraphError.capture("Project Story DB scalar prepare failed: \(litScenesSQLiteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func bind(_ bindings: [Any?], to statement: OpaquePointer) throws {
        for (index, value) in bindings.enumerated() {
            let sqliteIndex = Int32(index + 1)
            switch value {
            case nil:
                sqlite3_bind_null(statement, sqliteIndex)
            case let value as String:
                litScenesSQLiteBindText(value, to: sqliteIndex, in: statement)
            case let value as Int:
                sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, sqliteIndex, value)
            case let value as Double:
                sqlite3_bind_double(statement, sqliteIndex, value)
            case let value as Bool:
                sqlite3_bind_int(statement, sqliteIndex, value ? 1 : 0)
            default:
                throw ScreenGraphError.capture("Unsupported SQLite binding type at index \(index + 1).")
            }
        }
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONCoding.encoder.encode(value), as: UTF8.self)
    }

    private func deterministicId(kind: String, components: [String], collisionIndex: Int = 0) -> String {
        let packet = StorySQLiteIDPacket(
            namespace: "litscenes.desktop.storydb.v1",
            kind: kind,
            components: components.map { $0.precomposedStringWithCanonicalMapping },
            collisionIndex: collisionIndex
        )
        let data = (try? JSONCoding.encoder.encode(packet)) ?? Data("\(kind):\(components.joined(separator: "|")):\(collisionIndex)".utf8)
        return "\(safeIdentifier(kind))_\(sha256Hex(data).prefix(32))"
    }

    private func recordRecovery(project: ProjectRecord, message: String) throws {
        let document = StoryPersistenceRecoveryDocument(projectId: project.projectId, message: message)
        try ProjectSQLiteDocumentStore(projectLibrary: projectLibrary)
            .saveDocument(document, for: project, documentType: "story_persistence_recovery")
    }

    private func clearRecovery(project: ProjectRecord) throws {
        try ProjectSQLiteDocumentStore(projectLibrary: projectLibrary)
            .deleteDocument(for: project, documentType: "story_persistence_recovery")
    }
}
