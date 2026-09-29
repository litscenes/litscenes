import Foundation

struct ImagePromptRewriteSection: Codable, Hashable, Sendable {
    var id: String
    var field: String
    var text: String
    var locked: Bool
    var referenceId: String?
}

struct ImagePromptRewriteOutput: Codable, Sendable {
    struct Section: Codable, Sendable {
        var id: String
        var text: String
    }
    var sections: [Section]
    var summary: String
}

struct ImagePromptRewriteResult: Sendable {
    var rawText: String
    var traceId: String
    var model: String
}

struct ImagePromptRewriteRequest: Sendable {
    var preparation: PreparedImagePrompt
    var sections: [ImagePromptRewriteSection]
    var budgets: [String: Int]
    var attempt: Int
    var feedback: String
    var previousOutput: String
}

struct ImagePromptRewriteValidationError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum ImagePromptShortening {
    /// Split only at exact application-owned fragments, never inferred subject keywords.
    static func sections(for value: PreparedImagePrompt) -> [ImagePromptRewriteSection] {
        let fields = Set(value.violations.map(\.field))
        let fragments = value.protectedText.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        var result: [ImagePromptRewriteSection] = []
        for field in fields.sorted() {
            let text = value.assembledFields[field] ?? ""
            var cursor = text.startIndex
            var ordinal = 0
            var referenceId: String?
            func append(_ content: Substring, locked: Bool) {
                guard !content.isEmpty else { return }
                ordinal += 1
                result.append(.init(id: "\(field)_\(ordinal)", field: field, text: String(content), locked: locked, referenceId: referenceId))
            }
            while cursor < text.endIndex {
                let next = fragments.compactMap { fragment -> Range<String.Index>? in
                    text.range(of: fragment, range: cursor..<text.endIndex)
                }.min { lhs, rhs in
                    lhs.lowerBound == rhs.lowerBound ? lhs.upperBound > rhs.upperBound : lhs.lowerBound < rhs.lowerBound
                }
                guard let next else { append(text[cursor...], locked: false); break }
                append(text[cursor..<next.lowerBound], locked: false)
                let fragment = String(text[next])
                if let reference = value.references.first(where: { $0.binding == fragment }) { referenceId = reference.id }
                append(text[next], locked: true)
                cursor = next.upperBound
            }
        }
        return result
    }

    static func budgets(for value: PreparedImagePrompt, sections: [ImagePromptRewriteSection]) throws -> [String: Int] {
        var budgets: [String: Int] = [:]
        for constraint in value.violations {
            let lockedCount = sections.filter { $0.field == constraint.field && $0.locked }.reduce(0) { $0 + $1.text.unicodeScalars.count }
            let available = constraint.maximum - lockedCount
            guard available > 0 else {
                throw ImagePromptRewriteValidationError(message: "Required reference bindings or layout instructions exceed this route's limit. Your full prompt is saved. Choose another model or reduce the references/layout.")
            }
            budgets[constraint.field] = min(budgets[constraint.field] ?? available, available)
        }
        return budgets
    }

    static func apply(_ output: ImagePromptRewriteOutput, to original: PreparedImagePrompt,
                      sections: [ImagePromptRewriteSection]) throws -> PreparedImagePrompt {
        let editable = sections.filter { !$0.locked }
        let expected = Set(editable.map(\.id))
        let actual = Set(output.sections.map(\.id))
        guard actual == expected, output.sections.count == expected.count else {
            throw ImagePromptRewriteValidationError(message: "Return each editable section ID exactly once, with no extra or missing IDs.")
        }
        let replacements = Dictionary(uniqueKeysWithValues: output.sections.map { ($0.id, $0.text) })
        var result = original
        for field in Set(sections.map(\.field)) {
            result.providerFields[field] = sections.filter { $0.field == field }
                .map { $0.locked ? $0.text : replacements[$0.id]! }.joined()
            if !(original.assembledFields[field] ?? "").trimmed.isEmpty, (result.providerFields[field] ?? "").trimmed.isEmpty {
                throw ImagePromptRewriteValidationError(message: "The \(field) must retain the original creative direction; it cannot become empty.")
            }
        }
        guard result.violations.isEmpty else {
            throw ImagePromptRewriteValidationError(message: result.violations.map {
                "\($0.field) is \($0.count(result.providerFields[$0.field] ?? "")) characters including fixed sections; maximum \($0.maximum). Shorten the editable sections further."
            }.joined(separator: " "))
        }
        result.changeSummary = output.summary
        result.state = "prepared"
        result.errorMessage = ""
        return result
    }

    /// Two semantic attempts; transport retry and spend policies remain with shared HTTP.
    static func shorten(_ original: PreparedImagePrompt,
                        rewrite: @Sendable (ImagePromptRewriteRequest) async throws -> ImagePromptRewriteResult,
                        record: @Sendable (PreparedImagePrompt) async throws -> Void = { _ in }) async throws -> PreparedImagePrompt {
        guard !original.violations.isEmpty else { return original }
        let sections = sections(for: original)
        let budgets = try budgets(for: original, sections: sections)
        var value = original
        var feedback = ""
        var previousOutput = ""
        for attempt in 1...2 {
            try Task.checkCancellation()
            let response = try await rewrite(.init(preparation: value, sections: sections, budgets: budgets,
                attempt: attempt, feedback: feedback, previousOutput: previousOutput))
            if !response.traceId.isEmpty { value.rewriteTraceIds.append(response.traceId) }
            value.rewriteModel = response.model
            do {
                let output: ImagePromptRewriteOutput
                do { output = try JSONDecoder().decode(ImagePromptRewriteOutput.self, from: Data(response.rawText.utf8)) }
                catch { throw ImagePromptRewriteValidationError(message: "Return valid JSON with sections (id and text) and summary, matching the supplied schema.") }
                let result = try apply(output, to: value, sections: sections)
                try await record(result)
                try Task.checkCancellation()
                return result
            } catch let error as ImagePromptRewriteValidationError {
                feedback = error.message
                previousOutput = response.rawText
                value.state = "shortening"
                value.errorMessage = feedback
                try await record(value)
            }
        }
        throw ImagePromptRewriteValidationError(message: "The shortened prompt still could not be validated after one correction. No image request was sent. Your original is saved. Edit it or choose another model. " + feedback)
    }
}
