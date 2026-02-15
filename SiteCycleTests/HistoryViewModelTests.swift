import Testing
import Foundation
import SwiftData
@testable import SiteCycle

struct HistoryViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Fetching & Ordering

    @Test func fetchEntriesReturnsReverseChronologicalOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let now = Date()
        for i in 0..<5 {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(i) * 3600),
                endTime: now.addingTimeInterval(Double(i + 1) * 3600),
                location: location
            )
            context.insert(entry)
        }
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        let entries = viewModel.filteredEntries

        #expect(entries.count == 5)
        for i in 0..<(entries.count - 1) {
            #expect(entries[i].startTime >= entries[i + 1].startTime)
        }
    }

    @Test func fetchEntriesIncludesActiveEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let activeEntry = SiteChangeEntry(
            startTime: Date(),
            location: location
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        let entries = viewModel.filteredEntries

        #expect(entries.count == 1)
        #expect(entries[0].endTime == nil)
    }

    @Test func fetchEntriesEmptyHistoryReturnsEmptyArray() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = HistoryViewModel(modelContext: context)
        let entries = viewModel.filteredEntries

        #expect(entries.isEmpty)
    }

    // MARK: - Filtering by Location

    @Test func filterByLocationReturnsOnlyMatchingEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(zone: "Front Abdomen", side: "left")
        let loc2 = Location(zone: "Side Abdomen", side: "right")
        let loc3 = Location(zone: "Back Abdomen", side: "left")
        context.insert(loc1)
        context.insert(loc2)
        context.insert(loc3)

        let now = Date()
        for (i, loc) in [loc1, loc1, loc2, loc2, loc3].enumerated() {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(i) * 3600),
                endTime: now.addingTimeInterval(Double(i + 1) * 3600),
                location: loc
            )
            context.insert(entry)
        }
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.locationFilter = loc1

        let entries = viewModel.filteredEntries
        #expect(entries.count == 2)
        for entry in entries {
            #expect(entry.location?.id == loc1.id)
        }
    }

    @Test func filterByLocationNilReturnsAllEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(zone: "Front Abdomen", side: "left")
        let loc2 = Location(zone: "Side Abdomen", side: "right")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        for (i, loc) in [loc1, loc2, loc1].enumerated() {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(i) * 3600),
                endTime: now.addingTimeInterval(Double(i + 1) * 3600),
                location: loc
            )
            context.insert(entry)
        }
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.locationFilter = nil

        #expect(viewModel.filteredEntries.count == 3)
    }

    @Test func filterByDisabledLocationStillShowsHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left", isEnabled: false)
        context.insert(location)

        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            location: location
        )
        context.insert(entry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.locationFilter = location

        let entries = viewModel.filteredEntries
        #expect(entries.count == 1)
    }

    // MARK: - Filtering by Date Range

    @Test func filterByDateRangeReturnsOnlyEntriesInRange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let now = Date()
        // Create entries spanning 60 days
        for i in 0..<60 {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(-Double(i) * 86400),
                endTime: now.addingTimeInterval(-Double(i) * 86400 + 3600),
                location: location
            )
            context.insert(entry)
        }
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.startDate = now.addingTimeInterval(-7 * 86400)
        viewModel.endDate = now

        let entries = viewModel.filteredEntries
        // Entries from day 0 through day 7 = 8 entries
        #expect(entries.count == 8)
    }

    @Test func filterByDateRangeIncludesEdgeDates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let start = Date()
        let end = start.addingTimeInterval(86400)

        // Entry exactly on start boundary
        let entryAtStart = SiteChangeEntry(
            startTime: start,
            endTime: start.addingTimeInterval(3600),
            location: location
        )
        context.insert(entryAtStart)

        // Entry exactly on end boundary
        let entryAtEnd = SiteChangeEntry(
            startTime: end,
            endTime: end.addingTimeInterval(3600),
            location: location
        )
        context.insert(entryAtEnd)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.startDate = start
        viewModel.endDate = end

        let entries = viewModel.filteredEntries
        #expect(entries.count == 2)
    }

    @Test func filterByDateRangeNilReturnsAllEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        for i in 0..<5 {
            let entry = SiteChangeEntry(
                startTime: Date().addingTimeInterval(Double(i) * 3600),
                endTime: Date().addingTimeInterval(Double(i + 1) * 3600),
                location: location
            )
            context.insert(entry)
        }
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.startDate = nil
        viewModel.endDate = nil

        #expect(viewModel.filteredEntries.count == 5)
    }

    // MARK: - Combined Filters

    @Test func combinedLocationAndDateFiltersApplyTogether() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(zone: "Front Abdomen", side: "left")
        let loc2 = Location(zone: "Side Abdomen", side: "right")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()

        // loc1 entries: 2 in range, 1 out of range
        let entry1 = SiteChangeEntry(
            startTime: now.addingTimeInterval(-1 * 86400),
            endTime: now.addingTimeInterval(-1 * 86400 + 3600),
            location: loc1
        )
        context.insert(entry1)

        let entry2 = SiteChangeEntry(
            startTime: now.addingTimeInterval(-2 * 86400),
            endTime: now.addingTimeInterval(-2 * 86400 + 3600),
            location: loc1
        )
        context.insert(entry2)

        let entry3 = SiteChangeEntry(
            startTime: now.addingTimeInterval(-30 * 86400),
            endTime: now.addingTimeInterval(-30 * 86400 + 3600),
            location: loc1
        )
        context.insert(entry3)

        // loc2 entry: 1 in range
        let entry4 = SiteChangeEntry(
            startTime: now.addingTimeInterval(-1 * 86400),
            endTime: now.addingTimeInterval(-1 * 86400 + 3600),
            location: loc2
        )
        context.insert(entry4)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.locationFilter = loc1
        viewModel.startDate = now.addingTimeInterval(-7 * 86400)
        viewModel.endDate = now

        let entries = viewModel.filteredEntries
        #expect(entries.count == 2)
        for entry in entries {
            #expect(entry.location?.id == loc1.id)
        }
    }

    // MARK: - Editing

    @Test func editEntryUpdatesLocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(zone: "Front Abdomen", side: "left")
        let loc2 = Location(zone: "Side Abdomen", side: "right")
        context.insert(loc1)
        context.insert(loc2)

        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            location: loc1
        )
        context.insert(entry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.updateEntry(entry, location: loc2, startTime: nil, endTime: nil, note: nil)

        let entries = viewModel.filteredEntries
        let updated = try #require(entries.first)
        #expect(updated.location?.id == loc2.id)
    }

    @Test func editEntryUpdatesStartTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let originalStart = Date()
        let entry = SiteChangeEntry(
            startTime: originalStart,
            endTime: originalStart.addingTimeInterval(3600),
            location: location
        )
        context.insert(entry)
        try context.save()

        let newStart = originalStart.addingTimeInterval(-7200)
        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.updateEntry(entry, location: nil, startTime: newStart, endTime: nil, note: nil)

        let entries = viewModel.filteredEntries
        let updated = try #require(entries.first)
        #expect(abs(updated.startTime.timeIntervalSince(newStart)) < 1)
    }

    @Test func editEntryUpdatesEndTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(
            startTime: Date(),
            location: location
        )
        context.insert(entry)
        try context.save()

        #expect(entry.endTime == nil)

        let newEnd = Date().addingTimeInterval(3600)
        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.updateEntry(entry, location: nil, startTime: nil, endTime: newEnd, note: nil)

        let entries = viewModel.filteredEntries
        let updated = try #require(entries.first)
        let updatedEnd = try #require(updated.endTime)
        #expect(abs(updatedEnd.timeIntervalSince(newEnd)) < 1)
        #expect(updated.durationHours != nil)
    }

    @Test func editEntryClearsEndTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            location: location
        )
        context.insert(entry)
        try context.save()

        #expect(entry.endTime != nil)

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.clearEndTime(entry)

        let entries = viewModel.filteredEntries
        let updated = try #require(entries.first)
        #expect(updated.endTime == nil)
    }

    @Test func editEntryUpdatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            note: "original note",
            location: location
        )
        context.insert(entry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.updateEntry(entry, location: nil, startTime: nil, endTime: nil, note: "updated note")

        let entries = viewModel.filteredEntries
        let updated = try #require(entries.first)
        #expect(updated.note == "updated note")
    }

    // MARK: - Deleting

    @Test func deleteEntryRemovesFromPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let now = Date()
        for i in 0..<3 {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(i) * 3600),
                endTime: now.addingTimeInterval(Double(i + 1) * 3600),
                location: location
            )
            context.insert(entry)
        }
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        #expect(viewModel.filteredEntries.count == 3)

        let entryToDelete = viewModel.filteredEntries[0]
        viewModel.deleteEntry(entryToDelete)

        #expect(viewModel.filteredEntries.count == 2)
    }

    @Test func deleteActiveEntrySucceeds() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let activeEntry = SiteChangeEntry(
            startTime: Date(),
            location: location
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        #expect(viewModel.filteredEntries.count == 1)

        viewModel.deleteEntry(activeEntry)

        #expect(viewModel.filteredEntries.count == 0)
    }

    @Test func deleteOnlyEntryLeavesEmptyHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            location: location
        )
        context.insert(entry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.deleteEntry(entry)

        #expect(viewModel.filteredEntries.isEmpty)
    }
}
