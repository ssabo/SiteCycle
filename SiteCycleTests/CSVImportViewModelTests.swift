import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct CSVImportViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let validCSV = """
    date,location,duration_hours,note
    2024-01-15T10:30:00Z,L Abdomen (Front),72.0,
    2024-01-18T10:30:00Z,R Abdomen (Front),,
    """

    /// Saves one entry, standing in for history the user already has (or that
    /// iCloud has just downloaded).
    @discardableResult
    private func insertExistingEntry(in context: ModelContext) throws -> SiteChangeEntry {
        let location = Location(bodyPart: "Thigh", side: "left", isEnabled: true, sortOrder: 0)
        context.insert(location)
        let entry = try SiteChangeEntry(startTime: fixedDate("2023-06-01T08:00:00Z"), location: location)
        context.insert(entry)
        try context.save()
        return entry
    }

    // MARK: - Starting

    @Test func onboardingRefusesToRestoreOverExistingHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try insertExistingEntry(in: context)
        let flow = CSVImportViewModel(origin: .onboarding)

        flow.start(context: context)

        #expect(!flow.showingPicker)
        #expect(flow.alert?.title == "History Already on This Device")
        #expect(flow.alert?.message.hasPrefix("This device already has 1 site change, probably from iCloud") == true)
    }

    @Test func onboardingOpensPickerOnEmptyDevice() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let flow = CSVImportViewModel(origin: .onboarding)

        flow.start(context: context)

        #expect(flow.showingPicker)
        #expect(flow.alert == nil)
    }

    @Test func settingsOpensPickerEvenWithExistingHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try insertExistingEntry(in: context)
        let flow = CSVImportViewModel(origin: .settings)

        flow.start(context: context)

        #expect(flow.showingPicker)
        #expect(flow.alert == nil)
    }

    // MARK: - Preparing

    @Test func preparingChangesNothingAndAsksForConfirmation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = try insertExistingEntry(in: context)
        let flow = CSVImportViewModel(origin: .settings)

        flow.prepare(fileAt: try writeTemp(validCSV), context: context)

        let confirmation = try #require(flow.pendingConfirmation)
        #expect(confirmation.plan.entries.count == 2)
        #expect(confirmation.title == "Replace All Data?")
        #expect(confirmation.confirmButtonTitle == "Replace")
        #expect(confirmation.message == """
        This file has 2 site changes to import.

        Importing permanently deletes your 1 site change and all locations, \
        including on your other devices that sync with iCloud. This cannot be undone.
        """)
        #expect(flow.alert == nil)
        #expect(!context.hasChanges)
        let entries = try ModelContext(container).fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.map(\.id) == [existing.id])
    }

    @Test func confirmationListsRowsThatWillBeSkipped() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let flow = CSVImportViewModel(origin: .onboarding)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,L Abdomen (Front),72.0,
        not-a-date,L Abdomen (Front),72.0,
        """

        flow.prepare(fileAt: try writeTemp(csv), context: context)

        let confirmation = try #require(flow.pendingConfirmation)
        #expect(confirmation.title == "Restore from Backup?")
        #expect(confirmation.confirmButtonTitle == "Restore")
        #expect(confirmation.message.hasPrefix("""
        This file has 1 site change to import.

        1 row can't be read and will be skipped:
        • Row 3: unrecognized date 'not-a-date'

        Restoring replaces the default locations with the ones in the backup.
        """))
    }

    @Test func invalidFileExplainsFailureAndChangesNothing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = try insertExistingEntry(in: context)
        let flow = CSVImportViewModel(origin: .settings)
        let csv = """
        date,location,duration_hours,note
        1/15/2024 10:30,L Abdomen (Front),72.0,
        """

        flow.prepare(fileAt: try writeTemp(csv), context: context)

        #expect(flow.pendingConfirmation == nil)
        let alert = try #require(flow.alert)
        #expect(alert.title == "Import Failed")
        #expect(alert.message.contains("• Row 2: unrecognized date '1/15/2024 10:30'"))
        #expect(alert.message.contains("Your existing data has not been changed."))
        #expect(alert.message.contains("\n\nError: SiteCycle.CSVImporter.ImportError "))
        let entries = try ModelContext(container).fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.map(\.id) == [existing.id])
    }

    // MARK: - Confirming

    @Test func confirmingInSettingsReplacesDataAndReportsSuccess() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try insertExistingEntry(in: context)
        let flow = CSVImportViewModel(origin: .settings)
        flow.prepare(fileAt: try writeTemp(validCSV), context: context)
        let confirmation = try #require(flow.pendingConfirmation)

        #expect(flow.confirm(confirmation, context: context))

        #expect(flow.pendingConfirmation == nil)
        #expect(flow.alert == CSVImportViewModel.Alert(title: "Import Successful", message: "Imported 2 site changes."))
        let entries = try ModelContext(container).fetch(
            FetchDescriptor<SiteChangeEntry>(sortBy: [SortDescriptor(\.startTime)])
        )
        #expect(entries.map { $0.location?.fullDisplayName } == ["L Abdomen (Front)", "R Abdomen (Front)"])
    }

    @Test func confirmingInOnboardingRestoresWithoutAnAlert() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let flow = CSVImportViewModel(origin: .onboarding)
        flow.prepare(fileAt: try writeTemp(validCSV), context: context)
        let confirmation = try #require(flow.pendingConfirmation)

        #expect(flow.confirm(confirmation, context: context))

        #expect(flow.alert == nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<SiteChangeEntry>()) == 2)
    }

    /// iCloud can deliver the user's history while the confirmation is showing.
    @Test func onboardingRefusesIfHistoryArrivesBeforeConfirming() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let flow = CSVImportViewModel(origin: .onboarding)
        flow.prepare(fileAt: try writeTemp(validCSV), context: context)
        let confirmation = try #require(flow.pendingConfirmation)
        let synced = try insertExistingEntry(in: context)

        #expect(!flow.confirm(confirmation, context: context))

        #expect(flow.alert?.title == "History Already on This Device")
        let entries = try ModelContext(container).fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.map(\.id) == [synced.id])
    }

    @Test func cancellingClearsTheConfirmation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let flow = CSVImportViewModel(origin: .settings)
        flow.prepare(fileAt: try writeTemp(validCSV), context: context)

        flow.cancel()

        #expect(flow.pendingConfirmation == nil)
        #expect(try context.fetchCount(FetchDescriptor<SiteChangeEntry>()) == 0)
    }

    @Test func successAlertCountsSkippedRows() {
        let result = CSVImporter.ImportResult(
            importedCount: 1,
            skippedRows: [
                CSVImporter.SkippedRow(rowNumber: 3, reason: "bad"),
                CSVImporter.SkippedRow(rowNumber: 4, reason: "bad"),
            ]
        )
        #expect(CSVImportViewModel.successAlert(for: result).message == "Imported 1 site change. Skipped 2 rows.")
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
