import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
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

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
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

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let activeEntry = SiteChangeEntry(startTime: Date(), location: location)
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
        #expect(viewModel.filteredEntries.isEmpty)
    }

    // MARK: - Filtering by Location

    @Test func filterByLocationReturnsOnlyMatchingEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "right")
        let loc3 = Location(bodyPart: "Abdomen", subArea: "Back", side: "left")
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

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "right")
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

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", isEnabled: false)
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
        #expect(viewModel.filteredEntries.count == 1)
    }

    // MARK: - Filtering by Date Range

    @Test func filterByDateRangeReturnsOnlyEntriesInRange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
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

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let start = Date()
        let end = start.addingTimeInterval(86400)

        let entryAtStart = SiteChangeEntry(
            startTime: start,
            endTime: start.addingTimeInterval(3600),
            location: location
        )
        context.insert(entryAtStart)

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
        #expect(viewModel.filteredEntries.count == 2)
    }

    @Test func filterByDateRangeNilReturnsAllEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
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

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "right")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()

        for (offset, loc) in [(-1, loc1), (-2, loc1), (-30, loc1), (-1, loc2)] {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(offset) * 86400),
                endTime: now.addingTimeInterval(Double(offset) * 86400 + 3600),
                location: loc
            )
            context.insert(entry)
        }
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
}
