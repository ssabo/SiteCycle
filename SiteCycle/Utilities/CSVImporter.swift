import Foundation
import OSLog
import SwiftData

struct CSVImporter {

    struct ImportResult {
        let importedCount: Int
        let skippedRows: [(rowNumber: Int, reason: String)]
    }

    enum ImportError: LocalizedError {
        case unreadableFile
        case invalidHeader
        case noValidEntries

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "The file could not be read."
            case .invalidHeader:
                return "The file does not appear to be a valid SiteCycle CSV export."
            case .noValidEntries:
                return "No valid site change entries were found in the file."
            }
        }
    }

    private static let logger = Logger(subsystem: "com.sitecycle.app", category: "CSVImporter")

    static func importCSV(from url: URL, context: ModelContext) throws -> ImportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportError.unreadableFile
        }

        let stripped = csv.hasPrefix("\u{FEFF}") ? String(csv.dropFirst()) : csv
        return try parseAndImport(csv: stripped, context: context)
    }

    // MARK: - Internal for tests

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

    // MARK: - Private

    private static func parseAndImport(csv: String, context: ModelContext) throws -> ImportResult {
        let rows = parseCSV(csv)
        guard let header = rows.first else {
            throw ImportError.invalidHeader
        }

        let expectedHeader = ["date", "location", "duration_hours", "note"]
        let normalizedHeader = header.map { $0.trimmingCharacters(in: .whitespaces) }
        guard normalizedHeader == expectedHeader else {
            let got = normalizedHeader.map { "\"\($0)\"" }.joined(separator: ", ")
            let want = expectedHeader.map { "\"\($0)\"" }.joined(separator: ", ")
            logger.error("Invalid header — got: [\(got)], want: [\(want)]")
            throw ImportError.invalidHeader
        }

        let dataRows = Array(rows.dropFirst())
        guard !dataRows.isEmpty else {
            throw ImportError.noValidEntries
        }

        try deleteAllData(context: context)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var locationCache: [String: Location] = [:]
        var sortOrder = 0
        var count = 0
        var skipped: [(rowNumber: Int, reason: String)] = []

        for (index, row) in dataRows.enumerated() {
            let rowNumber = index + 2
            guard row.count >= 4 else {
                let reason = "too few columns (\(row.count) found, 4 required)"
                logger.warning("Row \(rowNumber): \(reason)")
                skipped.append((rowNumber: rowNumber, reason: reason))
                continue
            }
            let dateStr = row[0], locationName = row[1], durationStr = row[2], note = row[3]
            guard let startTime = dateFormatter.date(from: dateStr) else {
                let reason = "unrecognized date '\(dateStr)'"
                logger.warning("Row \(rowNumber): \(reason)")
                skipped.append((rowNumber: rowNumber, reason: reason))
                continue
            }

            let location = resolveOrCreateLocation(
                locationName, cache: &locationCache, sortOrder: &sortOrder, context: context
            )

            let endTime: Date?
            if let hours = Double(durationStr), !durationStr.isEmpty {
                endTime = startTime.addingTimeInterval(hours * 3600)
            } else {
                endTime = nil
            }

            let entry = SiteChangeEntry(
                startTime: startTime, endTime: endTime,
                note: note.isEmpty ? nil : note, location: location
            )
            context.insert(entry)
            count += 1
        }

        guard count > 0 else {
            throw ImportError.noValidEntries
        }

        try context.save()
        return ImportResult(importedCount: count, skippedRows: skipped)
    }

    private static func resolveOrCreateLocation(
        _ name: String, cache: inout [String: Location],
        sortOrder: inout Int, context: ModelContext
    ) -> Location {
        if let cached = cache[name] { return cached }
        let loc = makeLocation(from: name, sortOrder: sortOrder)
        context.insert(loc)
        cache[name] = loc
        sortOrder += 1
        return loc
    }

    private static func deleteAllData(context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        for entry in entries {
            context.delete(entry)
        }

        let locations = try context.fetch(FetchDescriptor<Location>())
        for location in locations {
            context.delete(location)
        }

        try context.save()
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
