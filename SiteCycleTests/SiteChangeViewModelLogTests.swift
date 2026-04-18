import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct SiteChangeViewModelLogTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Log Site Change

    @Test func logSiteChangeCreatesNewEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        context.insert(location)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: nil)

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.location?.zone == "Front Abdomen")
        #expect(entries.first?.endTime == nil)
    }

    @Test func logSiteChangeClosesPreviousActiveEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Zone A", sortOrder: 0)
        let loc2 = Location(bodyPart: "Zone B", sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)

        let activeEntry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-3600),
            location: loc1
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: loc2, note: nil)

        let descriptor = FetchDescriptor<SiteChangeEntry>(
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime)]
        )
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 2)

        let firstEntry = entries.first { $0.location?.zone == "Zone A" }
        let secondEntry = entries.first { $0.location?.zone == "Zone B" }
        #expect(firstEntry?.endTime != nil)
        #expect(secondEntry?.endTime == nil)
    }

    @Test func logSiteChangeSavesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        context.insert(location)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: "Test note")

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.first?.note == "Test note")
    }

    @Test func logSiteChangeIgnoresEmptyNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        context.insert(location)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: "")

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.first?.note == nil)
    }

    // MARK: - Previous Note Update

    @Test func logSiteChangeLeaveUnchangedPreservesExistingPreviousNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Zone A", sortOrder: 0)
        let loc2 = Location(bodyPart: "Zone B", sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)

        let activeEntry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-3600),
            note: "old",
            location: loc1
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: loc2, note: nil)

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        let closed = try #require(entries.first { $0.location?.zone == "Zone A" })
        #expect(closed.note == "old")
        #expect(closed.endTime != nil)
    }

    @Test func logSiteChangeReplaceUpdatesPreviousNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Zone A", sortOrder: 0)
        let loc2 = Location(bodyPart: "Zone B", sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)

        let activeEntry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-3600),
            note: "old",
            location: loc1
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: loc2, note: nil, previousNote: .replace("new"))

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        let closed = try #require(entries.first { $0.location?.zone == "Zone A" })
        #expect(closed.note == "new")
        #expect(closed.endTime != nil)
    }

    @Test func logSiteChangeReplaceEmptyStringClearsPreviousNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Zone A", sortOrder: 0)
        let loc2 = Location(bodyPart: "Zone B", sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)

        let activeEntry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-3600),
            note: "old",
            location: loc1
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: loc2, note: nil, previousNote: .replace(""))

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        let closed = try #require(entries.first { $0.location?.zone == "Zone A" })
        #expect(closed.note == nil)
    }

    @Test func logSiteChangeReplaceSetsNoteWhenPreviousHadNone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Zone A", sortOrder: 0)
        let loc2 = Location(bodyPart: "Zone B", sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)

        let activeEntry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-3600),
            location: loc1
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: loc2, note: nil, previousNote: .replace("added"))

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        let closed = try #require(entries.first { $0.location?.zone == "Zone A" })
        #expect(closed.note == "added")
    }

    @Test func logSiteChangeReplaceWithNoActiveEntryIgnoresPreviousNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Zone A", sortOrder: 0)
        context.insert(location)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: "new", previousNote: .replace("ignored"))

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.note == "new")
    }

    @Test func logSiteChangeDefaultArgumentIsLeaveUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Zone A", sortOrder: 0)
        let loc2 = Location(bodyPart: "Zone B", sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)

        let activeEntry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-3600),
            note: "kept",
            location: loc1
        )
        context.insert(activeEntry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: loc2, note: "fresh")

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        let closed = try #require(entries.first { $0.location?.zone == "Zone A" })
        #expect(closed.note == "kept")
    }

    // MARK: - Last Used Date

    @Test func lastUsedDateReturnsCorrectDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Zone A", sortOrder: 0)
        context.insert(location)

        let olderDate = Date().addingTimeInterval(-7200)
        let newerDate = Date().addingTimeInterval(-3600)

        let entry1 = SiteChangeEntry(
            startTime: olderDate,
            endTime: olderDate.addingTimeInterval(1800),
            location: location
        )
        let entry2 = SiteChangeEntry(
            startTime: newerDate,
            endTime: newerDate.addingTimeInterval(1800),
            location: location
        )
        context.insert(entry1)
        context.insert(entry2)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        let lastUsed = viewModel.lastUsedDate(for: location)

        #expect(lastUsed != nil)
        let unwrappedLastUsed = try #require(lastUsed)
        let diff = abs(unwrappedLastUsed.timeIntervalSince(newerDate))
        #expect(diff < 1)
    }

    @Test func lastUsedDateReturnsNilForNeverUsed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Zone A", sortOrder: 0)
        context.insert(location)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)

        #expect(viewModel.lastUsedDate(for: location) == nil)
    }
}
