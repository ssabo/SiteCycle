import Foundation
import SwiftData

struct CSVImporter {

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

    static func importCSV(from url: URL, context: ModelContext) throws -> Int {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard let csv = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportError.unreadableFile
        }

        return try parseAndImport(csv: csv, context: context)
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

    private static func parseAndImport(csv: String, context: ModelContext) throws -> Int {
        let rows = parseCSV(csv)
        guard let header = rows.first else {
            throw ImportError.invalidHeader
        }

        let expectedHeader = ["date", "location", "duration_hours", "note"]
        guard header == expectedHeader else {
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

        for row in dataRows {
            guard row.count >= 4 else { continue }
            let dateStr = row[0], locationName = row[1], durationStr = row[2], note = row[3]
            guard let startTime = dateFormatter.date(from: dateStr) else { continue }

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
        return count
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

    private static func makeLocation(from displayName: String, sortOrder: Int) -> Location {
        let defaultZones = [
            "Front Abdomen", "Side Abdomen", "Back Abdomen",
            "Front Thigh", "Side Thigh", "Back Arm", "Buttock"
        ]

        let side: String?
        let zone: String

        if displayName.hasPrefix("Left ") {
            side = "left"
            zone = String(displayName.dropFirst(5))
        } else if displayName.hasPrefix("Right ") {
            side = "right"
            zone = String(displayName.dropFirst(6))
        } else {
            side = nil
            zone = displayName
        }

        let isCustom = !defaultZones.contains(zone)

        return Location(
            zone: zone,
            side: side,
            isEnabled: true,
            isCustom: isCustom,
            sortOrder: sortOrder
        )
    }
}
