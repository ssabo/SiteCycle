import Testing
import Foundation
import SwiftData
@testable import SiteCycle

/// CSV import replaces all data, so it must validate the whole file before
/// deleting anything, and replace the data in a single save.
@MainActor
struct CSVImporterValidationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let date1 = "2024-01-15T10:30:00Z"
    private let date2 = "2024-01-18T10:30:00Z"

    // MARK: - Nothing changes until the file is valid

    /// A backup re-saved by Excel or Numbers rewrites every date, so no row
    /// parses. The import must fail without deleting anything.
    @Test func importAllInvalidRowsPreservesExistingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", isEnabled: true, sortOrder: 0)
        context.insert(existing)
        let oldEntry = try SiteChangeEntry(startTime: fixedDate(date1), location: existing)
        context.insert(oldEntry)
        try context.save()

        let csv = """
        date,location,duration_hours,note
        1/15/2024 10:30,L Abdomen (Front),72.0,
        1/18/2024 10:30,R Abdomen (Front),,
        """
        do {
            _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
            Issue.record("Expected .noValidEntries to be thrown")
        } catch CSVImporter.ImportError.noValidEntries(let skippedRows) {
            #expect(skippedRows == [
                CSVImporter.SkippedRow(rowNumber: 2, reason: "unrecognized date '1/15/2024 10:30'"),
                CSVImporter.SkippedRow(rowNumber: 3, reason: "unrecognized date '1/18/2024 10:30'"),
            ])
        }

        #expect(!context.hasChanges)
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<SiteChangeEntry>()).map(\.id) == [oldEntry.id])
        #expect(try fresh.fetch(FetchDescriptor<Location>()).map(\.id) == [existing.id])
    }

    @Test func applyingEmptyPlanPreservesExistingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = Location(bodyPart: "Thigh", isEnabled: true, sortOrder: 0)
        context.insert(existing)
        let oldEntry = try SiteChangeEntry(startTime: fixedDate(date1), location: existing)
        context.insert(oldEntry)
        try context.save()

        let plan = CSVImporter.ImportPlan(entries: [], skippedRows: [])
        do {
            _ = try CSVImporter.apply(plan, context: context)
            Issue.record("Expected .noValidEntries to be thrown")
        } catch CSVImporter.ImportError.noValidEntries(let skippedRows) {
            #expect(skippedRows.isEmpty)
        }

        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<SiteChangeEntry>()).map(\.id) == [oldEntry.id])
        #expect(try fresh.fetch(FetchDescriptor<Location>()).map(\.id) == [existing.id])
    }

    @Test func noValidEntriesMessageNamesTheBadRows() {
        let error = CSVImporter.ImportError.noValidEntries(skippedRows: [
            CSVImporter.SkippedRow(rowNumber: 2, reason: "unrecognized date '1/15/2024 10:30'"),
        ])
        #expect(error.errorDescription == """
        No valid site change entries were found in the file. None of its rows could be read:
        • Row 2: unrecognized date '1/15/2024 10:30'
        """)
    }

    // MARK: - Row validation

    @Test func makePlanParsesRowsWithoutAStore() throws {
        let csv = """
        date,location,duration_hours,note,problems
        2024-01-15T10:30:00Z,L Abdomen (Front), 48.0 ,"sore, red",Leaking; ;Painful
        2024-01-18T10:30:00Z,R Thigh,,,
        """
        let plan = try CSVImporter.makePlan(csv: csv)
        let start1 = try fixedDate(date1)
        let start2 = try fixedDate(date2)
        #expect(plan == CSVImporter.ImportPlan(
            entries: [
                CSVImporter.ParsedEntry(
                    startTime: start1,
                    endTime: start1.addingTimeInterval(48 * 3600),
                    note: "sore, red",
                    locationName: "L Abdomen (Front)",
                    problemNames: ["Leaking", "Painful"]
                ),
                CSVImporter.ParsedEntry(
                    startTime: start2, endTime: nil, note: nil, locationName: "R Thigh", problemNames: []
                ),
            ],
            skippedRows: []
        ))
    }

    /// A damaged duration used to be imported as a second "active" site.
    @Test(arguments: ["72h", "abc", "nan", "inf", "-inf", "1e308"])
    func unparseableDurationIsSkippedNotImportedAsActive(duration: String) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,L Abdomen (Front),72.0,
        2024-01-18T10:30:00Z,R Abdomen (Front),\(duration),
        """
        let result = try CSVImporter.importCSV(from: writeTemp(csv), context: context)
        #expect(result == CSVImporter.ImportResult(
            importedCount: 1,
            skippedRows: [CSVImporter.SkippedRow(rowNumber: 3, reason: "unrecognized duration '\(duration)'")]
        ))
        let entries = try ModelContext(container).fetch(FetchDescriptor<SiteChangeEntry>())
        let start1 = try fixedDate(date1)
        #expect(entries.map(\.startTime) == [start1])
        #expect(entries.allSatisfy { $0.endTime != nil })
    }

    @Test func describeListsFirstFiveSkippedRows() {
        let skipped = (2...8).map { CSVImporter.SkippedRow(rowNumber: $0, reason: "bad") }
        #expect(CSVImporter.describe(skipped) == """
        • Row 2: bad
        • Row 3: bad
        • Row 4: bad
        • Row 5: bad
        • Row 6: bad
        …and 2 more
        """)
    }

    // MARK: - Replacing

    @Test func importSavesReplacementInOneStep() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = Location(bodyPart: "Old Zone", isEnabled: true, isCustom: true, sortOrder: 0)
        context.insert(existing)
        let oldEntry = try SiteChangeEntry(startTime: fixedDate(date1), location: existing)
        context.insert(oldEntry)
        try context.save()

        let csv = """
        date,location,duration_hours,note
        2024-01-18T10:30:00Z,L Abdomen (Front),72.0,
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)

        #expect(!context.hasChanges)
        let fresh = ModelContext(container)
        let entries = try fresh.fetch(FetchDescriptor<SiteChangeEntry>())
        let start2 = try fixedDate(date2)
        #expect(entries.map(\.startTime) == [start2])
        #expect(entries.map { $0.location?.fullDisplayName } == ["L Abdomen (Front)"])
        #expect(try fresh.fetch(FetchDescriptor<Location>()).map(\.fullDisplayName) == ["L Abdomen (Front)"])
    }

    /// Problems are configuration, not history, so import keeps them.
    @Test func importKeepsProblemsAndMatchesNamesIgnoringCase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 0)
        context.insert(leaking)
        try context.save()

        let csv = """
        date,location,duration_hours,note,problems
        2024-01-15T10:30:00Z,L Abdomen (Front),24.0,,leaking;Itchy
        """
        _ = try CSVImporter.importCSV(from: writeTemp(csv), context: context)

        let fresh = ModelContext(container)
        let problems = try fresh.fetch(FetchDescriptor<SiteProblem>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(problems.map(\.name) == ["Leaking", "Itchy"])
        #expect(problems.first?.id == leaking.id)
        let entry = try #require(try fresh.fetch(FetchDescriptor<SiteChangeEntry>()).first)
        #expect(entry.safeProblems.map(\.name) == ["Leaking", "Itchy"])
    }

    // MARK: - Helpers

    private func fixedDate(_ iso8601: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso8601))
    }

    private func writeTemp(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
