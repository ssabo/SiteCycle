import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct CSVImporterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let validHeader = "date,location,duration_hours,note"
    private let date1 = "2024-01-15T10:30:00Z"
    private let date2 = "2024-01-18T10:30:00Z"

    // MARK: - Basic Import

    @Test func testValidImport() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,72.0,
        2024-01-18T10:30:00Z,Right Front Abdomen,48.0,good
        """
        let result = try CSVImporter.importCSV(
            from: writeTemp(csv),
            context: context
        )
        #expect(result.importedCount == 2)
        let entries = try context.fetch(
            FetchDescriptor<SiteChangeEntry>(sortBy: [SortDescriptor(\.startTime)])
        )
        #expect(entries.count == 2)
        #expect(entries[0].location?.fullDisplayName == "L Abdomen (Front)")
        #expect(entries[1].location?.fullDisplayName == "R Abdomen (Front)")
    }

    @Test func testActiveEntryHasNilEndTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        let entry = try #require(entries.first)
        #expect(entry.endTime == nil)
    }

    @Test func testNoteImported() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,72.0,felt tight
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        let entry = try #require(entries.first)
        #expect(entry.note == "felt tight")
    }

    @Test func testEmptyNoteIsNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,72.0,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        let entry = try #require(entries.first)
        #expect(entry.note == nil)
    }

    // MARK: - Error Handling

    @Test func testInvalidHeader() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = "wrong,header,row,here\n2024-01-15T10:30:00Z,loc,72.0,\n"
        do {
            _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
            Issue.record("Expected .invalidHeader to be thrown")
        } catch CSVImporter.ImportError.invalidHeader {
            // Expected
        }
    }

    @Test func testEmptyData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = "date,location,duration_hours,note\n"
        do {
            _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
            Issue.record("Expected .noValidEntries to be thrown")
        } catch CSVImporter.ImportError.noValidEntries {
            // Expected
        }
    }

    @Test func testSkippedRowsTracked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,72.0,
        not-a-date,Left Front Abdomen,72.0,
        """
        let result = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        #expect(result.importedCount == 1)
        #expect(result.skippedRows.count == 1)
        #expect(result.skippedRows[0].rowNumber == 3)
        #expect(result.skippedRows[0].reason.contains("unrecognized date"))
    }

    // MARK: - Data Replacement

    @Test func testReplacesExistingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existing = Location(bodyPart: "Old Zone", isEnabled: true, isCustom: true, sortOrder: 0)
        context.insert(existing)
        let oldEntry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-86400),
            location: existing
        )
        context.insert(oldEntry)
        try context.save()

        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,72.0,
        """
        let result = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        #expect(result.importedCount == 1)

        let locations = try context.fetch(FetchDescriptor<Location>())
        #expect(locations.count == 1)
        #expect(locations[0].fullDisplayName == "L Abdomen (Front)")

        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.count == 1)
    }

    // MARK: - Location Reconstruction

    @Test func testLocationReconstructionLeft() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,72.0,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let locations = try context.fetch(FetchDescriptor<Location>())
        let location = try #require(locations.first)
        #expect(location.side == "left")
        #expect(location.bodyPart == "Abdomen")
        #expect(location.subArea == "Front")
        #expect(location.isCustom == false)
    }

    @Test func testLocationReconstructionNoSide() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Buttock,72.0,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let locations = try context.fetch(FetchDescriptor<Location>())
        let location = try #require(locations.first)
        #expect(location.side == nil)
        #expect(location.bodyPart == "Buttock")
        #expect(location.subArea == nil)
        #expect(location.isCustom == false)
    }

    @Test func testCustomLocationDetected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Shoulder,72.0,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let locations = try context.fetch(FetchDescriptor<Location>())
        let location = try #require(locations.first)
        #expect(location.isCustom == true)
        #expect(location.bodyPart == "Shoulder")
    }

    // MARK: - New Format Import

    @Test func testNewFormatImport() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,L Abdomen (Front),72.0,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let locations = try context.fetch(FetchDescriptor<Location>())
        let location = try #require(locations.first)
        #expect(location.side == "left")
        #expect(location.bodyPart == "Abdomen")
        #expect(location.subArea == "Front")
        #expect(location.fullDisplayName == "L Abdomen (Front)")
        #expect(location.isCustom == false)
    }

    // MARK: - RFC 4180 Parsing

    @Test func testRFC4180QuotedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = "date,location,duration_hours,note\n" +
            "2024-01-15T10:30:00Z,Left Front Abdomen,72.0,\"sore, red, \"\"ouch\"\"\"\n"
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        let entry = try #require(entries.first)
        #expect(entry.note == "sore, red, \"ouch\"")
    }

    // MARK: - Location Caching

    @Test func testLocationCaching() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,Left Front Abdomen,72.0,
        2024-01-18T10:30:00Z,Left Front Abdomen,48.0,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        let locations = try context.fetch(FetchDescriptor<Location>())
        #expect(locations.count == 1)
        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.count == 2)
    }

    // MARK: - CSV Parser Unit Tests

    @Test func testParseCSV() {
        let csv = "a,b,c\n\"quoted, field\",\"say \"\"hi\"\"\",plain\n"
        let rows = CSVImporter.parseCSV(csv)
        #expect(rows.count == 2)
        #expect(rows[0] == ["a", "b", "c"])
        #expect(rows[1] == ["quoted, field", "say \"hi\"", "plain"])
    }

    @Test func testParseCSVTrailingNewline() {
        let csv = "a,b\nc,d\n"
        let rows = CSVImporter.parseCSV(csv)
        #expect(rows.count == 2)
        #expect(rows[0] == ["a", "b"])
        #expect(rows[1] == ["c", "d"])
    }

    // MARK: - Helpers

    private func writeTemp(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
