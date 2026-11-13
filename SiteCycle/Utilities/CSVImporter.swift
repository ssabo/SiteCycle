import Foundation
import OSLog
import SwiftData

/// Restores a CSV backup written by `CSVExporter`.
///
/// Import replaces every entry and location, so it runs in two steps.
/// `makePlan` reads and validates the whole file without touching the store.
/// `apply` then replaces the data with the plan's entries in a single save.
/// Callers show the plan to the user and apply it only once they confirm.
struct CSVImporter {

    struct SkippedRow: Equatable, Sendable {
        let rowNumber: Int
        let reason: String
    }

    /// A valid row, parsed into values but not yet written to the store.
    struct ParsedEntry: Equatable, Sendable {
        let startTime: Date
        let endTime: Date?
        let note: String?
        /// Nil when the location field is blank, which the exporter writes for
        /// an entry whose location was lost.
        let locationName: String?
        let problemNames: [String]
    }

    /// Everything a file would import. Making one never touches the store.
    struct ImportPlan: Equatable, Sendable {
        let entries: [ParsedEntry]
        let skippedRows: [SkippedRow]
    }

    struct ImportResult: Equatable, Sendable {
        let importedCount: Int
        let skippedRows: [SkippedRow]
    }

    enum ImportError: LocalizedError, CustomNSError {
        /// `underlying` is the error from reading the file. Alerts show its
        /// domain and code rather than this wrapper's (CLAUDE.md rule 9).
        case unreadableFile(underlying: any Error)
        case invalidHeader
        /// The file has no data rows, or none of them is valid.
        case noValidEntries(skippedRows: [SkippedRow])

        /// Fixed codes, so the "Error: <domain> <code>" in an alert keeps its meaning.
        var errorCode: Int {
            switch self {
            case .unreadableFile: return 1
            case .invalidHeader: return 2
            case .noValidEntries: return 3
            }
        }

        var errorDescription: String? {
            switch self {
            case .unreadableFile(let underlying):
                return "The file could not be read. " + underlying.localizedDescription
            case .invalidHeader:
                return "The file does not appear to be a valid SiteCycle CSV export."
            case .noValidEntries(let skippedRows):
                let message = "No valid site change entries were found in the file."
                guard !skippedRows.isEmpty else { return message }
                return message + " None of its rows could be read:\n" + CSVImporter.describe(skippedRows)
            }
        }
    }

    /// How many skipped rows `describe` lists before summarizing the rest.
    static let maxListedSkippedRows = 5

    /// The longest duration a row may have: ten years. A site left open across
    /// a long break can last far longer than a normal one, but anything beyond
    /// this is a damaged value such as "1e300".
    static let maxDurationHours: Double = 24 * 365 * 10

    /// How far in the future a row may start, to allow for clock skew. An active
    /// site that starts in the future breaks the next site change's time picker.
    static let futureStartTolerance: TimeInterval = 5 * 60

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sitecycle.app", category: "CSVImporter")

    /// Reads, validates and applies a file without asking. The app's UI uses
    /// `makePlan(fromFileAt:)` and `apply(_:context:)` so the user can confirm in between.
    @MainActor
    static func importCSV(from url: URL, context: ModelContext) throws -> ImportResult {
        try apply(makePlan(fromFileAt: url), context: context)
    }

    /// Reads and validates a file. Never touches the store.
    static func makePlan(fromFileAt url: URL, now: Date = Date()) throws -> ImportPlan {
        try makePlan(csv: readFile(at: url), now: now)
    }

    /// Bullet lines for skipped rows, listing at most `maxListedSkippedRows`.
    static func describe(_ skippedRows: [SkippedRow]) -> String {
        var lines = skippedRows.prefix(maxListedSkippedRows).map { "• Row \($0.rowNumber): \($0.reason)" }
        let remaining = skippedRows.count - maxListedSkippedRows
        if remaining > 0 { lines.append("…and \(remaining) more") }
        return lines.joined(separator: "\n")
    }

    private static func readFile(at url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let csv: String
        do {
            csv = try String(contentsOf: url, encoding: .utf8)
        } catch {
            logger.error("Could not read the file: \(String(describing: error))")
            throw ImportError.unreadableFile(underlying: error)
        }
        return csv.hasPrefix("\u{FEFF}") ? String(csv.dropFirst()) : csv
    }
}

// MARK: - Validation (never touches the store)

extension CSVImporter {

    /// Parses and validates the whole file. Throws if the header is wrong or
    /// no row is valid; otherwise returns the rows to import and the rows to skip.
    static func makePlan(csv: String, now: Date = Date()) throws -> ImportPlan {
        let rows = parseCSV(csv)
        guard let header = rows.first else {
            throw ImportError.invalidHeader
        }

        // The `problems` column was added later; older exports without it still import.
        let expectedHeader = ["date", "location", "duration_hours", "note"]
        let normalizedHeader = header.map { $0.trimmingCharacters(in: .whitespaces) }
        let hasProblemsColumn = normalizedHeader == expectedHeader + ["problems"]
        guard normalizedHeader == expectedHeader || hasProblemsColumn else {
            let got = normalizedHeader.map { "\"\($0)\"" }.joined(separator: ", ")
            let want = expectedHeader.map { "\"\($0)\"" }.joined(separator: ", ")
            logger.error("Invalid header — got: [\(got)], want: [\(want)]")
            throw ImportError.invalidHeader
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let latestStart = now.addingTimeInterval(futureStartTolerance)
        var entries: [ParsedEntry] = []
        var skipped: [SkippedRow] = []
        for (index, row) in rows.dropFirst().enumerated() {
            let rowNumber = index + 2
            // Blank lines, such as an extra newline at the end, hold no data.
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            switch parseRow(row, hasProblemsColumn: hasProblemsColumn, dateFormatter: dateFormatter, latestStart: latestStart) {
            case .success(let entry):
                entries.append(entry)
            case .failure(let error):
                logger.warning("Row \(rowNumber): \(error.reason)")
                skipped.append(SkippedRow(rowNumber: rowNumber, reason: error.reason))
            }
        }

        guard !entries.isEmpty else {
            throw ImportError.noValidEntries(skippedRows: skipped)
        }
        return ImportPlan(entries: entries, skippedRows: skipped)
    }

    private struct RowError: Error {
        let reason: String
    }

    /// Column 5 is only read as problems when the header declares it, so a stray
    /// extra field under the legacy header can't turn into bogus problems.
    private static func parseRow(
        _ row: [String], hasProblemsColumn: Bool, dateFormatter: ISO8601DateFormatter, latestStart: Date
    ) -> Result<ParsedEntry, RowError> {
        guard row.count >= 4 else {
            return .failure(RowError(reason: "too few columns (\(row.count) found, 4 required)"))
        }
        guard let startTime = dateFormatter.date(from: row[0].trimmingCharacters(in: .whitespaces)) else {
            return .failure(RowError(reason: "unrecognized date '\(row[0])'"))
        }
        guard startTime <= latestStart else {
            return .failure(RowError(reason: "date '\(row[0])' is in the future"))
        }

        // Empty means the active site. Anything else must be a number of hours
        // in range: "72h" or "nan" is a damaged row, not a site that is still active.
        let durationField = row[2].trimmingCharacters(in: .whitespaces)
        var endTime: Date?
        if !durationField.isEmpty {
            guard let hours = Double(durationField), hours.isFinite else {
                return .failure(RowError(reason: "unrecognized duration '\(row[2])'"))
            }
            guard (0...maxDurationHours).contains(hours) else {
                let range = "0 to \(Int(maxDurationHours)) hours"
                return .failure(RowError(reason: "duration '\(row[2])' is out of range (\(range))"))
            }
            endTime = startTime.addingTimeInterval(hours * 3600)
        }

        let locationName = row[1].trimmingCharacters(in: .whitespaces)
        let note = row[3]
        let problemsField = hasProblemsColumn && row.count >= 5 ? row[4] : ""
        return .success(ParsedEntry(
            startTime: startTime,
            endTime: endTime,
            note: note.isEmpty ? nil : note,
            locationName: locationName.isEmpty ? nil : locationName,
            problemNames: problemNames(in: problemsField)
        ))
    }

    /// Splits a `;`-separated problems field into trimmed, non-empty names.
    private static func problemNames(in field: String) -> [String] {
        field.split(separator: SiteProblem.csvSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Replacing the data

extension CSVImporter {

    /// Replaces all entries and locations with the plan's entries, in one save.
    /// On any error the context is rolled back, so the store is left as it was.
    @MainActor
    static func apply(_ plan: ImportPlan, context: ModelContext) throws -> ImportResult {
        // Never wipe the store for a plan that has nothing to put back.
        guard !plan.entries.isEmpty else {
            throw ImportError.noValidEntries(skippedRows: plan.skippedRows)
        }
        // Save unrelated pending edits first, so a rollback discards only the import.
        if context.hasChanges { try context.save() }

        do {
            var problemResolver = try ProblemResolver(context: context)
            let oldEntries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
            let oldLocations = try context.fetch(FetchDescriptor<Location>())
            for entry in oldEntries { context.delete(entry) }
            for location in oldLocations { context.delete(location) }
            insert(plan.entries, problemResolver: &problemResolver, context: context)
            try context.save()
        } catch {
            context.rollback()
            logger.error("Import failed and was rolled back: \(String(describing: error))")
            throw error
        }
        return ImportResult(importedCount: plan.entries.count, skippedRows: plan.skippedRows)
    }

    @MainActor
    private static func insert(
        _ entries: [ParsedEntry], problemResolver: inout ProblemResolver, context: ModelContext
    ) {
        var locations: [String: Location] = [:]
        for parsed in entries {
            let entry = SiteChangeEntry(
                startTime: parsed.startTime,
                endTime: parsed.endTime,
                note: parsed.note,
                location: location(named: parsed.locationName, cache: &locations, context: context),
                problems: problemResolver.resolveAll(parsed.problemNames, context: context)
            )
            context.insert(entry)
        }
    }

    /// The location for a display name, created the first time the name is seen.
    @MainActor
    private static func location(
        named name: String?, cache: inout [String: Location], context: ModelContext
    ) -> Location? {
        guard let name else { return nil }
        if let cached = cache[name] { return cached }
        let location = makeLocation(from: name, sortOrder: cache.count)
        context.insert(location)
        cache[name] = location
        return location
    }

    /// Resolves CSV problem names. Problems are configuration, not history, so
    /// import keeps them and matches names against them (case-insensitively)
    /// rather than replacing them; unknown names become custom problems.
    private struct ProblemResolver {
        var byName: [String: SiteProblem] = [:]
        var nextSortOrder = 0

        @MainActor
        init(context: ModelContext) throws {
            let problems = try context.fetch(FetchDescriptor<SiteProblem>(sortBy: [SortDescriptor(\.sortOrder)]))
            // Every existing problem counts toward the max, including ones whose
            // names collide with an earlier one and so aren't in `byName`.
            nextSortOrder = (problems.map(\.sortOrder).max() ?? -1) + 1
            for problem in problems {
                let key = SiteProblem.nameKey(problem.name)
                if byName[key] == nil { byName[key] = problem }
            }
        }

        /// Resolves trimmed, non-empty names, dropping repeats.
        @MainActor
        mutating func resolveAll(_ names: [String], context: ModelContext) -> [SiteProblem] {
            var result: [SiteProblem] = []
            for name in names {
                let problem = resolve(name, context: context)
                guard !result.contains(where: { $0.id == problem.id }) else { continue }
                result.append(problem)
            }
            return result
        }

        @MainActor
        private mutating func resolve(_ name: String, context: ModelContext) -> SiteProblem {
            let key = SiteProblem.nameKey(name)
            if let existing = byName[key] { return existing }
            let problem = SiteProblem(
                name: name,
                emoji: SiteProblem.fallbackEmoji,
                isCustom: true,
                sortOrder: nextSortOrder
            )
            context.insert(problem)
            byName[key] = problem
            nextSortOrder += 1
            return problem
        }
    }
}

// MARK: - CSV parsing and location names

extension CSVImporter {

    static func parseCSV(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let char = csv[index]

            if inQuotes {
                if processQuotedChar(char, csv: csv, index: &index, field: &currentField, inQuotes: &inQuotes) {
                    continue
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == "," {
                currentRow.append(currentField)
                currentField = ""
            } else if char == "\r" {
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
                if skipFollowingNewline(csv: csv, index: &index) { continue }
            } else if char == "\n" {
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
            } else {
                currentField.append(char)
            }

            index = csv.index(after: index)
        }

        currentRow.append(currentField)
        if !currentRow.isEmpty { rows.append(currentRow) }
        if rows.last == [""] { rows.removeLast() }

        return rows
    }

    // Returns true if the caller should `continue` (index already advanced past escaped quote)
    private static func processQuotedChar(
        _ char: Character, csv: String, index: inout String.Index,
        field: inout String, inQuotes: inout Bool
    ) -> Bool {
        if char == "\"" {
            let next = csv.index(after: index)
            if next < csv.endIndex && csv[next] == "\"" {
                field.append("\"")
                index = csv.index(after: next)
                return true
            }
            inQuotes = false
        } else {
            field.append(char)
        }
        return false
    }

    // Returns true if the caller should `continue` (index advanced past \n)
    private static func skipFollowingNewline(csv: String, index: inout String.Index) -> Bool {
        let next = csv.index(after: index)
        if next < csv.endIndex && csv[next] == "\n" {
            index = csv.index(after: next)
            return true
        }
        return false
    }

    static func makeLocation(from displayName: String, sortOrder: Int) -> Location {
        let defaultBodyParts: Set<String> = [
            "Abdomen", "Thigh", "Arm", "Buttock"
        ]

        var remaining = displayName
        var side: String?

        // New format: "L ..." or "R ..."
        if remaining.hasPrefix("L ") {
            side = "left"
            remaining = String(remaining.dropFirst(2))
        } else if remaining.hasPrefix("R ") {
            side = "right"
            remaining = String(remaining.dropFirst(2))
        }
        // Old format: "Left ..." or "Right ..."
        else if remaining.hasPrefix("Left ") {
            side = "left"
            remaining = String(remaining.dropFirst(5))
        } else if remaining.hasPrefix("Right ") {
            side = "right"
            remaining = String(remaining.dropFirst(6))
        }

        var bodyPart: String
        var subArea: String?

        // New format: "Abdomen (Front)"
        if let parenStart = remaining.firstIndex(of: "("),
           let parenEnd = remaining.firstIndex(of: ")"),
           parenEnd > parenStart {
            bodyPart = String(remaining[..<parenStart]).trimmingCharacters(in: .whitespaces)
            let afterOpen = remaining.index(after: parenStart)
            subArea = String(remaining[afterOpen..<parenEnd])
        }
        // Old format: "Front Abdomen" — last word is bodyPart, rest is subArea
        else {
            let words = remaining.split(separator: " ").map(String.init)
            if let lastWord = words.last {
                bodyPart = lastWord
                if words.count >= 2 {
                    subArea = words.dropLast().joined(separator: " ")
                }
            } else {
                bodyPart = remaining
            }
        }

        let isCustom = !defaultBodyParts.contains(bodyPart)

        return Location(
            bodyPart: bodyPart,
            subArea: subArea,
            side: side,
            isEnabled: true,
            isCustom: isCustom,
            sortOrder: sortOrder
        )
    }
}
