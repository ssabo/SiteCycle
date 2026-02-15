import Testing
import Foundation
import SwiftData
@testable import SiteCycle

struct SiteChangeViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Recommendation Engine

    @Test func allNeverUsedLocationsAreRecommended() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(zone: "Zone A", side: nil, sortOrder: 0)
        let loc2 = Location(zone: "Zone B", side: nil, sortOrder: 1)
        let loc3 = Location(zone: "Zone C", side: nil, sortOrder: 2)
        context.insert(loc1)
        context.insert(loc2)
        context.insert(loc3)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(locations: [loc1, loc2, loc3])

        #expect(recs.avoid.isEmpty)
        #expect(recs.recommended.count == 3)
    }

    @Test func avoidListContainsMostRecentlyUsed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var locations: [Location] = []
        for i in 0..<6 {
            let loc = Location(zone: "Zone \(i)", side: nil, sortOrder: i)
            context.insert(loc)
            locations.append(loc)
        }

        // Add usage: Zone 0 most recent, Zone 5 least recent
        let baseDate = Date()
        for (i, loc) in locations.enumerated() {
            let entry = SiteChangeEntry(
                startTime: baseDate.addingTimeInterval(Double(-i) * 3600),
                endTime: baseDate.addingTimeInterval(Double(-i) * 3600 + 1800),
                location: loc
            )
            context.insert(entry)
        }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(locations: locations)

        #expect(recs.avoid.count == 3)
        let avoidZones = Set(recs.avoid.map(\.zone))
        #expect(avoidZones.contains("Zone 0"))
        #expect(avoidZones.contains("Zone 1"))
        #expect(avoidZones.contains("Zone 2"))
    }

    @Test func recommendedListContainsLeastRecentlyUsed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var locations: [Location] = []
        for i in 0..<6 {
            let loc = Location(zone: "Zone \(i)", side: nil, sortOrder: i)
            context.insert(loc)
            locations.append(loc)
        }

        let baseDate = Date()
        for (i, loc) in locations.enumerated() {
            let entry = SiteChangeEntry(
                startTime: baseDate.addingTimeInterval(Double(-i) * 3600),
                endTime: baseDate.addingTimeInterval(Double(-i) * 3600 + 1800),
                location: loc
            )
            context.insert(entry)
        }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(locations: locations)

        #expect(recs.recommended.count == 3)
        let recZones = Set(recs.recommended.map(\.zone))
        #expect(recZones.contains("Zone 3"))
        #expect(recZones.contains("Zone 4"))
        #expect(recZones.contains("Zone 5"))
    }

    @Test func avoidAndRecommendedDoNotOverlap() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var locations: [Location] = []
        for i in 0..<6 {
            let loc = Location(zone: "Zone \(i)", side: nil, sortOrder: i)
            context.insert(loc)
            locations.append(loc)
        }

        let baseDate = Date()
        for (i, loc) in locations.enumerated() {
            let entry = SiteChangeEntry(
                startTime: baseDate.addingTimeInterval(Double(-i) * 3600),
                endTime: baseDate.addingTimeInterval(Double(-i) * 3600 + 1800),
                location: loc
            )
            context.insert(entry)
        }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(locations: locations)

        let avoidIds = Set(recs.avoid.map(\.id))
        let recIds = Set(recs.recommended.map(\.id))
        #expect(avoidIds.isDisjoint(with: recIds))
    }

    @Test func neverUsedLocationsAppearInRecommended() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let used = Location(zone: "Used Zone", side: nil, sortOrder: 0)
        let unused1 = Location(zone: "Unused A", side: nil, sortOrder: 1)
        let unused2 = Location(zone: "Unused B", side: nil, sortOrder: 2)
        context.insert(used)
        context.insert(unused1)
        context.insert(unused2)

        let entry = SiteChangeEntry(startTime: Date(), endTime: Date(), location: used)
        context.insert(entry)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(locations: [used, unused1, unused2])

        let recZones = Set(recs.recommended.map(\.zone))
        #expect(recZones.contains("Unused A"))
        #expect(recZones.contains("Unused B"))
    }

    @Test func fewerThanSixLocationsHandledGracefully() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(zone: "Zone A", side: nil, sortOrder: 0)
        let loc2 = Location(zone: "Zone B", side: nil, sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)

        let entry = SiteChangeEntry(startTime: Date(), endTime: Date(), location: loc1)
        context.insert(entry)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(locations: [loc1, loc2])

        #expect(recs.avoid.count == 1)
        #expect(recs.recommended.count == 1)
        #expect(recs.avoid.first?.zone == "Zone A")
        #expect(recs.recommended.first?.zone == "Zone B")
    }

    @Test func allLocationsSortedAlphabetically() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let locC = Location(zone: "Charlie", side: nil, sortOrder: 0)
        let locA = Location(zone: "Alpha", side: nil, sortOrder: 1)
        let locB = Location(zone: "Bravo", side: nil, sortOrder: 2)
        context.insert(locC)
        context.insert(locA)
        context.insert(locB)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(locations: [locC, locA, locB])

        #expect(recs.allSorted[0].zone == "Alpha")
        #expect(recs.allSorted[1].zone == "Bravo")
        #expect(recs.allSorted[2].zone == "Charlie")
    }

    @Test func emptyLocationsProducesEmptyRecommendations() {
        let recs = SiteChangeViewModel.computeRecommendations(locations: [])

        #expect(recs.avoid.isEmpty)
        #expect(recs.recommended.isEmpty)
        #expect(recs.allSorted.isEmpty)
    }

    // MARK: - Category

    @Test func categoryIdentifiesAvoidLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc = Location(zone: "Zone A", side: nil, sortOrder: 0)
        context.insert(loc)

        let entry = SiteChangeEntry(startTime: Date(), endTime: Date(), location: loc)
        context.insert(entry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)

        #expect(viewModel.category(for: loc) == .avoid)
    }

    @Test func categoryIdentifiesRecommendedLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let used = Location(zone: "Used", side: nil, sortOrder: 0)
        let unused = Location(zone: "Unused", side: nil, sortOrder: 1)
        context.insert(used)
        context.insert(unused)

        let entry = SiteChangeEntry(startTime: Date(), endTime: Date(), location: used)
        context.insert(entry)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)

        #expect(viewModel.category(for: unused) == .recommended)
    }

    @Test func categoryIdentifiesNeutralLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create 7+ locations so some fall into neutral
        var locations: [Location] = []
        for i in 0..<8 {
            let loc = Location(zone: "Zone \(i)", side: nil, sortOrder: i)
            context.insert(loc)
            locations.append(loc)
        }

        let baseDate = Date()
        for (i, loc) in locations.enumerated() {
            let entry = SiteChangeEntry(
                startTime: baseDate.addingTimeInterval(Double(-i) * 3600),
                endTime: baseDate.addingTimeInterval(Double(-i) * 3600 + 1800),
                location: loc
            )
            context.insert(entry)
        }
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)

        // Zones 3 and 4 should be neutral (not in top 3 avoid or bottom 3 recommended)
        #expect(viewModel.category(for: locations[3]) == .neutral)
        #expect(viewModel.category(for: locations[4]) == .neutral)
    }

    // MARK: - Log Site Change

    @Test func logSiteChangeCreatesNewEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Front Abdomen", side: "left", sortOrder: 0)
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

        let loc1 = Location(zone: "Zone A", side: nil, sortOrder: 0)
        let loc2 = Location(zone: "Zone B", side: nil, sortOrder: 1)
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

        let location = Location(zone: "Front Abdomen", side: "left", sortOrder: 0)
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

        let location = Location(zone: "Front Abdomen", side: "left", sortOrder: 0)
        context.insert(location)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: location, note: "")

        let descriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.first?.note == nil)
    }

    // MARK: - Last Used Date

    @Test func lastUsedDateReturnsCorrectDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Zone A", side: nil, sortOrder: 0)
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
        let diff = abs(lastUsed!.timeIntervalSince(newerDate))
        #expect(diff < 1)
    }

    @Test func lastUsedDateReturnsNilForNeverUsed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Zone A", side: nil, sortOrder: 0)
        context.insert(location)
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)

        #expect(viewModel.lastUsedDate(for: location) == nil)
    }
}
