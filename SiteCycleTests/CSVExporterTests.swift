import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct CSVExporterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - CSV Format & Headers

    @Test func csvHeaderRowIsCorrect() {
        let result = CSVExporter.generate(from: [])
        #expect(result.hasPrefix("date,location,duration_hours,note\n"))
    }

    @Test func csvEmptyDataProducesHeaderOnly() {
        let result = CSVExporter.generate(from: [])
        #expect(result == "date,location,duration_hours,note\n")
    }

    // MARK: - Field Formatting

    @Test func csvDateIsISO8601Formatted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 7
        components.hour = 15
        components.minute = 30
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = try #require(Calendar.current.date(from: components))

        let entry = SiteChangeEntry(
            startTime: date,
            endTime: date.addingTimeInterval(72 * 3600),
            location: location
        )
        context.insert(entry)
        try context.save()

        let result = CSVExporter.generate(from: [entry])
        let lines = result.components(separatedBy: "\n")
        let dataLine = try #require(lines.dropFirst().first)
        #expect(dataLine.hasPrefix("2026-02-07T15:30:00Z"))
    }

    @Test func csvLocationUsesDisplayName() throws {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        let lines = result.components(separatedBy: "\n")
        let dataLine = lines[1]
        let fields = parseCSVLine(dataLine)
        #expect(fields[1] == "L Abdomen (Front)")
    }

    @Test func csvDurationRoundedToOneDecimal() throws {
        let now = Date()
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let entry = SiteChangeEntry(
            startTime: now,
            endTime: now.addingTimeInterval(68.4667 * 3600),
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        let lines = result.components(separatedBy: "\n")
        let dataLine = lines[1]
        let fields = parseCSVLine(dataLine)
        #expect(fields[2] == "68.5")
    }

    @Test func csvActiveEntryHasEmptyDuration() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let entry = SiteChangeEntry(
            startTime: Date(),
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        let lines = result.components(separatedBy: "\n")
        let dataLine = lines[1]
        let fields = parseCSVLine(dataLine)
        #expect(fields[2].isEmpty)
    }

    @Test func csvNilNoteProducesEmptyField() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            note: nil,
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        let lines = result.components(separatedBy: "\n")
        let dataLine = lines[1]
        let fields = parseCSVLine(dataLine)
        #expect(fields[3].isEmpty)
    }

    // MARK: - CSV Escaping (RFC 4180)

    @Test func csvNoteWithCommasIsQuotedCorrectly() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            note: "sore, red area",
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        let lines = result.components(separatedBy: "\n")
        let dataLine = lines[1]
        #expect(dataLine.contains("\"sore, red area\""))
    }

    @Test func csvNoteWithDoubleQuotesIsEscaped() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            note: "said \"ouch\"",
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        let lines = result.components(separatedBy: "\n")
        let dataLine = lines[1]
        #expect(dataLine.contains("\"said \"\"ouch\"\"\""))
    }

    @Test func csvNoteWithNewlinesIsQuoted() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            note: "line one\nline two",
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        #expect(result.contains("\"line one\nline two\""))
    }

    @Test func csvLocationNameWithCommaIsQuoted() {
        let location = Location(bodyPart: "Hip, Left")
        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            location: location
        )

        let result = CSVExporter.generate(from: [entry])
        #expect(result.contains("\"Hip, Left\""))
    }

    // MARK: - Ordering & Multiple Entries

    @Test func csvEntriesInChronologicalOrder() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let now = Date()
        let entries = [
            SiteChangeEntry(
                startTime: now.addingTimeInterval(-3 * 86400),
                endTime: now.addingTimeInterval(-2 * 86400),
                location: location
            ),
            SiteChangeEntry(
                startTime: now.addingTimeInterval(-1 * 86400),
                endTime: now,
                location: location
            ),
            SiteChangeEntry(
                startTime: now.addingTimeInterval(-5 * 86400),
                endTime: now.addingTimeInterval(-4 * 86400),
                location: location
            )
        ]

        let result = CSVExporter.generate(from: entries)
        let lines = result.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        let dataLines = Array(lines.dropFirst())
        #expect(dataLines.count == 3)

        let dates = dataLines.map { parseCSVLine($0)[0] }
        #expect(dates[0] < dates[1])
        #expect(dates[1] < dates[2])
    }

    @Test func csvMultipleEntriesProduceCorrectRowCount() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let now = Date()
        var entries: [SiteChangeEntry] = []
        for i in 0..<5 {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(i) * 86400),
                endTime: now.addingTimeInterval(Double(i) * 86400 + 3600),
                location: location
            )
            entries.append(entry)
        }

        let result = CSVExporter.generate(from: entries)
        let lines = result.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        #expect(lines.count == 6)
    }

    // MARK: - File Naming

    @Test func csvFileNameIncludesTodaysDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let fileName = CSVExporter.fileName()
        #expect(fileName == "sitecycle-export-\(today).csv")
    }

    // MARK: - CSV Parsing Helper

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = line.makeIterator()

        while let char = chars.next() {
            if inQuotes {
                if char == "\"" {
                    if let next = chars.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                fields.append(current)
                                current = ""
                            } else {
                                current.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            }
        }
        fields.append(current)
        return fields
    }
}
