import Foundation
import SwiftData
import Testing
@testable import SiteCycle

/// Pins "one active site" (review §2.7, T11). Several open entries can come
/// from History, CSV import or two devices logging offline. Every open entry
/// but the newest is closed at the start of the next entry after it.
@MainActor
struct ActiveEntryRepairTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func hour(_ offset: Double) -> Date {
        reference.addingTimeInterval(offset * 3600)
    }

    private func openEntryIDs(_ container: ModelContainer) throws -> [UUID] {
        let descriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.endTime == nil },
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime)]
        )
        return try ModelContext(container).fetch(descriptor).map(\.id)
    }

    // MARK: - The repair

    @Test func closesEachOlderOpenEntryAtTheNextEntrysStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = SiteChangeEntry(startTime: hour(0))
        let closed = SiteChangeEntry(startTime: hour(10), endTime: hour(20))
        let middle = SiteChangeEntry(startTime: hour(30))
        let newest = SiteChangeEntry(startTime: hour(50))
        // Inserted out of order, so the result doesn't depend on insertion.
        for entry in [middle, newest, first, closed] { context.insert(entry) }

        let changed = SiteChangeEntry.closeSupersededActiveEntries(in: context)

        #expect(changed)
        #expect(first.endTime == hour(10))
        #expect(closed.endTime == hour(20))
        #expect(middle.endTime == hour(50))
        #expect(newest.endTime == nil)
    }

    @Test func closesALoneOpenEntryWithANewerClosedOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let stray = SiteChangeEntry(startTime: hour(0))
        context.insert(stray)
        context.insert(SiteChangeEntry(startTime: hour(24), endTime: hour(48)))

        #expect(SiteChangeEntry.closeSupersededActiveEntries(in: context))
        #expect(stray.endTime == hour(24))
    }

    @Test func reportsNoChangeWhenOnlyTheNewestIsOpen() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(SiteChangeEntry(startTime: hour(0), endTime: hour(10)))
        context.insert(SiteChangeEntry(startTime: hour(10)))

        #expect(!SiteChangeEntry.closeSupersededActiveEntries(in: context))
    }

    /// Two copies of one entry (as CSV import on two devices makes) must stay
    /// identical, so entry dedup can still merge them. Neither closes the other.
    @Test func copiesSharingAStartTimeCloseAtTheSameLaterStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let copyA = SiteChangeEntry(startTime: hour(0))
        let copyB = SiteChangeEntry(startTime: hour(0))
        let newestA = SiteChangeEntry(startTime: hour(72))
        let newestB = SiteChangeEntry(startTime: hour(72))
        for entry in [copyA, newestA, copyB, newestB] { context.insert(entry) }

        SiteChangeEntry.closeSupersededActiveEntries(in: context)

        #expect(copyA.endTime == hour(72))
        #expect(copyB.endTime == hour(72))
        #expect(newestA.endTime == nil)
        #expect(newestB.endTime == nil)
    }

    // MARK: - Logging a change

    @Test func logSiteChangeLeavesOnlyTheNewEntryActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", sortOrder: 0)
        context.insert(location)
        let older = SiteChangeEntry(startTime: hour(0), location: location)
        let active = SiteChangeEntry(startTime: hour(24), location: location)
        context.insert(older)
        context.insert(active)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: nil, changeTime: hour(72))

        #expect(!context.hasChanges)
        #expect(older.endTime == hour(24))
        #expect(active.endTime == hour(72))
        let newEntry = try #require(SiteChangeEntry.fetchActive(in: context))
        #expect(try openEntryIDs(container) == [newEntry.id])
    }

    /// Without a shown entry (no confirmation sheet), a change backdated to
    /// before the active site started doesn't close it; the backdated entry
    /// runs until the active one began.
    @Test func aBackdatedChangeBeforeTheActiveEntryDoesNotCloseIt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", sortOrder: 0)
        context.insert(location)
        let previous = SiteChangeEntry(startTime: hour(0), endTime: hour(48), location: location)
        let fromWatch = SiteChangeEntry(startTime: hour(48), location: location)
        context.insert(previous)
        context.insert(fromWatch)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: nil, changeTime: hour(40))

        #expect(fromWatch.endTime == nil)
        #expect(previous.endTime == hour(48))
        #expect(try openEntryIDs(container) == [fromWatch.id])
        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        let backdated = try #require(entries.first { $0.startTime == hour(40) })
        #expect(backdated.endTime == hour(48))
    }

    /// The sheet showed `shown`; while it was open a watch command logged a
    /// change at hour 48, and the user backdated the change to hour 40. The
    /// phone's change wins, with no overlap: the watch's entry is the same
    /// change logged twice, so it goes, and `shown` closes at hour 40.
    @Test func aBackdatedChangeFromTheSheetReplacesOneTheWatchLoggedMeanwhile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", sortOrder: 0)
        context.insert(location)
        let shown = SiteChangeEntry(startTime: hour(0), location: location)
        context.insert(shown)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: nil, changeTime: hour(48))  // The watch.
        let fromWatch = try #require(SiteChangeEntry.fetchActive(in: context))

        viewModel.logSiteChange(location: location, note: "phone", previousEntry: shown, changeTime: hour(40))

        let fresh = ModelContext(container)
        let entries = try fresh.fetch(FetchDescriptor<SiteChangeEntry>(sortBy: [SortDescriptor(\.startTime)]))
        #expect(!entries.contains { $0.id == fromWatch.id })
        #expect(entries.map(\.startTime) == [hour(0), hour(40)])
        #expect(entries.map(\.endTime) == [hour(40), nil])
        #expect(entries.last?.note == "phone")
    }

    // MARK: - History

    /// Correcting the active site's start to before the previous one began
    /// would make it older than that entry, and the repair would close it.
    /// The edit is refused instead, changing nothing.
    @Test func movingTheActiveSiteBeforeAnotherEntryIsRefused() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let previous = SiteChangeEntry(startTime: hour(24), endTime: hour(72))
        let active = SiteChangeEntry(startTime: hour(72))
        context.insert(previous)
        context.insert(active)
        try context.save()
        let viewModel = HistoryViewModel(modelContext: context)

        #expect(!viewModel.keepsActiveSiteNewest(active, startTime: hour(10), isActive: true))
        #expect(viewModel.keepsActiveSiteNewest(active, startTime: hour(60), isActive: true))
        let saved = viewModel.updateEntry(active, location: nil, startTime: hour(10), endTime: nil, note: "x")

        #expect(!saved)
        #expect(active.startTime == hour(72))
        #expect(active.note == nil)
        #expect(!context.hasChanges)
        #expect(try openEntryIDs(container) == [active.id])
    }

    /// A typo that moves an old entry's start past the active site's start is
    /// refused, so the active site isn't closed by the repair.
    @Test func movingAClosedEntryAfterTheActiveSiteIsRefused() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let old = SiteChangeEntry(startTime: hour(0), endTime: hour(72))
        let active = SiteChangeEntry(startTime: hour(72))
        context.insert(old)
        context.insert(active)
        try context.save()
        let viewModel = HistoryViewModel(modelContext: context)

        let saved = viewModel.updateEntry(old, location: nil, startTime: hour(9000), endTime: nil, note: nil)

        #expect(!saved)
        #expect(old.startTime == hour(0))
        #expect(try openEntryIDs(container) == [active.id])
    }

    /// The check uses the edited start time, so an older entry moved past
    /// every other one can be made active in the same edit, in one save.
    @Test func reopenWithANewStartChecksTheNewStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let older = SiteChangeEntry(startTime: hour(0), endTime: hour(10))
        let newest = SiteChangeEntry(startTime: hour(72), endTime: hour(100))
        context.insert(older)
        context.insert(newest)
        try context.save()
        let viewModel = HistoryViewModel(modelContext: context)

        #expect(!viewModel.canClearEndTime(older))
        #expect(viewModel.reopen(older, startTime: hour(120), note: "moved"))

        #expect(!context.hasChanges)
        #expect(older.startTime == hour(120))
        #expect(older.note == "moved")
        #expect(try openEntryIDs(container) == [older.id])
    }

    /// Reopening the newest entry while moving its start before another entry
    /// would leave it closed by the repair; it is refused instead.
    @Test func reopenWithAStartBeforeAnotherEntryIsRefused() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let older = SiteChangeEntry(startTime: hour(24), endTime: hour(72))
        let newest = SiteChangeEntry(startTime: hour(72), endTime: hour(100))
        context.insert(older)
        context.insert(newest)
        try context.save()

        let reopened = HistoryViewModel(modelContext: context).reopen(newest, startTime: hour(0))

        #expect(!reopened)
        #expect(newest.startTime == hour(72))
        #expect(newest.endTime == hour(100))
        #expect(try openEntryIDs(container).isEmpty)
    }

    @Test func onlyTheNewestEntryCanBeMadeActiveAgain() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let older = SiteChangeEntry(startTime: hour(0), endTime: hour(72))
        let newest = SiteChangeEntry(startTime: hour(72), endTime: hour(100))
        context.insert(older)
        context.insert(newest)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        #expect(!viewModel.canClearEndTime(older))
        #expect(viewModel.canClearEndTime(newest))

        viewModel.clearEndTime(older)
        #expect(older.endTime == hour(72))
        #expect(try openEntryIDs(container).isEmpty)

        viewModel.clearEndTime(newest)
        #expect(!context.hasChanges)
        #expect(try openEntryIDs(container) == [newest.id])
    }

    @Test func reopeningTheNewestEntryClosesAnOlderOpenOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let strayOpen = SiteChangeEntry(startTime: hour(0))
        let newest = SiteChangeEntry(startTime: hour(72), endTime: hour(100))
        context.insert(strayOpen)
        context.insert(newest)
        try context.save()

        HistoryViewModel(modelContext: context).clearEndTime(newest)

        #expect(strayOpen.endTime == hour(72))
        #expect(try openEntryIDs(container) == [newest.id])
    }

    // MARK: - CSV import

    @Test func aBackupWithSeveralActiveRowsImportsOneActiveEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let csv = """
        date,location,duration_hours,note
        2024-01-15T10:30:00Z,L Abdomen (Front),,
        2024-01-18T10:30:00Z,R Abdomen (Front),,
        """
        let plan = try CSVImporter.makePlan(csv: csv, now: reference)

        _ = try CSVImporter.apply(plan, context: context)

        let fresh = ModelContext(container)
        let entries = try fresh.fetch(FetchDescriptor<SiteChangeEntry>(sortBy: [SortDescriptor(\.startTime)]))
        let laterStart = try #require(entries.last?.startTime)
        #expect(entries.map(\.endTime) == [laterStart, nil])
    }

    // MARK: - Store maintenance

    @Test func launchMaintenanceClosesSupersededEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let older = SiteChangeEntry(startTime: hour(0))
        let newest = SiteChangeEntry(startTime: hour(72))
        context.insert(older)
        context.insert(newest)
        try context.save()

        let coordinator = StoreMaintenanceCoordinator(
            fallbackDelay: nil, observesCloudKit: false, notificationCenter: NotificationCenter()
        )
        coordinator.start(context: context, isCloudKitEnabled: true)

        #expect(older.endTime == hour(72))
        #expect(try openEntryIDs(container) == [newest.id])
    }

    /// Another device logged a change offline; the download brings its entry
    /// while this device's entry is still open.
    @Test func aDownloadThatBringsANewerActiveEntryClosesTheOlderOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let local = SiteChangeEntry(startTime: hour(0))
        context.insert(local)
        try context.save()

        let center = NotificationCenter()
        let posts = PostCounter()
        let observer = center.addObserver(forName: .storeMaintenanceDidChangeData, object: nil, queue: nil) { _ in
            posts.increment()
        }
        defer { center.removeObserver(observer) }
        let coordinator = StoreMaintenanceCoordinator(
            fallbackDelay: nil, observesCloudKit: false, notificationCenter: center
        )
        coordinator.start(context: context, isCloudKitEnabled: true)
        coordinator.importDidSucceed()  // The first download seeds the defaults.
        #expect(posts.count == 1)

        // What a later download brought.
        let downloaded = SiteChangeEntry(startTime: hour(30))
        let other = ModelContext(container)
        other.insert(downloaded)
        try other.save()
        coordinator.importDidSucceed()

        #expect(try openEntryIDs(container) == [downloaded.id])
        #expect(local.endTime == hour(30))
        #expect(posts.count == 2)

        // A download that changes nothing posts nothing.
        coordinator.importDidSucceed()
        #expect(posts.count == 2)
    }
}

/// Counts notifications, which are posted synchronously on the test's thread.
private final class PostCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}
