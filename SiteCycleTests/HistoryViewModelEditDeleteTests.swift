import Testing
import Foundation
import SwiftData
@testable import SiteCycle

struct HistoryViewModelEditDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Editing

    @Test func editEntryUpdatesLocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "right")
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

        let updated = try #require(viewModel.filteredEntries.first)
        #expect(updated.location?.id == loc2.id)
    }

    @Test func editEntryUpdatesStartTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
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

        let updated = try #require(viewModel.filteredEntries.first)
        #expect(abs(updated.startTime.timeIntervalSince(newStart)) < 1)
    }

    @Test func editEntryUpdatesEndTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(startTime: Date(), location: location)
        context.insert(entry)
        try context.save()

        #expect(entry.endTime == nil)

        let newEnd = Date().addingTimeInterval(3600)
        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.updateEntry(entry, location: nil, startTime: nil, endTime: newEnd, note: nil)

        let updated = try #require(viewModel.filteredEntries.first)
        let updatedEnd = try #require(updated.endTime)
        #expect(abs(updatedEnd.timeIntervalSince(newEnd)) < 1)
        #expect(updated.durationHours != nil)
    }

    @Test func editEntryClearsEndTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
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

        let updated = try #require(viewModel.filteredEntries.first)
        #expect(updated.endTime == nil)
    }

    @Test func editEntryUpdatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
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

        let updated = try #require(viewModel.filteredEntries.first)
        #expect(updated.note == "updated note")
    }

    // MARK: - Deleting

    @Test func deleteEntryRemovesFromPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
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

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let activeEntry = SiteChangeEntry(startTime: Date(), location: location)
        context.insert(activeEntry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        #expect(viewModel.filteredEntries.count == 1)

        viewModel.deleteEntry(activeEntry)

        #expect(viewModel.filteredEntries.isEmpty)
    }

    @Test func deleteOnlyEntryLeavesEmptyHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
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
