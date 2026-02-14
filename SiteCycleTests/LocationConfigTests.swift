import Testing
import Foundation
import SwiftData
@testable import SiteCycle

struct LocationConfigTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Custom Zone Creation

    @Test func addCustomZoneWithLateralityCreatesTwoLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let left = Location(zone: "Hip", side: "left", isEnabled: true, isCustom: true, sortOrder: 0)
        let right = Location(zone: "Hip", side: "right", isEnabled: true, isCustom: true, sortOrder: 1)
        context.insert(left)
        context.insert(right)
        try context.save()

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        #expect(locations.count == 2)

        let leftLoc = locations.first { $0.side == "left" }
        let rightLoc = locations.first { $0.side == "right" }
        #expect(leftLoc != nil)
        #expect(rightLoc != nil)
        #expect(leftLoc?.zone == "Hip")
        #expect(rightLoc?.zone == "Hip")
    }

    @Test func addCustomZoneWithoutLateralityCreatesOneLocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Lower Back", side: nil, isEnabled: true, isCustom: true, sortOrder: 0)
        context.insert(location)
        try context.save()

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        #expect(locations.count == 1)
        #expect(locations.first?.zone == "Lower Back")
        #expect(locations.first?.side == nil)
        #expect(locations.first?.displayName == "Lower Back")
    }

    @Test func customZonesHaveIsCustomTrue() {
        let location = Location(zone: "Custom Zone", side: nil, isCustom: true)
        #expect(location.isCustom == true)
    }

    @Test func customZoneSortOrderAfterExistingLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Seed default locations (14 locations, sortOrder 0-13)
        seedDefaultLocations(context: context)

        // Add a custom zone after
        let custom = Location(zone: "Hip", side: nil, isEnabled: true, isCustom: true, sortOrder: 14)
        context.insert(custom)
        try context.save()

        let descriptor = FetchDescriptor<Location>(sortBy: [SortDescriptor(\.sortOrder)])
        let locations = try context.fetch(descriptor)
        #expect(locations.count == 15)
        #expect(locations.last?.zone == "Hip")
        #expect(locations.last?.sortOrder == 14)
    }

    // MARK: - Soft Delete vs Hard Delete

    @Test func deleteCustomZoneWithNoHistoryRemovesFromDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Custom", side: nil, isEnabled: true, isCustom: true, sortOrder: 0)
        context.insert(location)
        try context.save()

        // No history entries — hard delete
        #expect(location.entries.isEmpty)
        context.delete(location)
        try context.save()

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        #expect(locations.isEmpty)
    }

    @Test func deleteCustomZoneWithHistorySoftDeletes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Custom", side: nil, isEnabled: true, isCustom: true, sortOrder: 0)
        context.insert(location)

        let entry = SiteChangeEntry(startTime: Date(), location: location)
        context.insert(entry)
        try context.save()

        // Has history — soft delete (disable instead of removing)
        let hasHistory = !location.entries.isEmpty
        #expect(hasHistory == true)

        location.isEnabled = false
        try context.save()

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        #expect(locations.count == 1)
        #expect(locations.first?.isEnabled == false)
    }

    @Test func softDeletePreservesHistoryEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(zone: "Custom", side: nil, isEnabled: true, isCustom: true, sortOrder: 0)
        context.insert(location)

        let entry = SiteChangeEntry(startTime: Date(), note: "test note", location: location)
        context.insert(entry)
        try context.save()

        // Soft delete
        location.isEnabled = false
        try context.save()

        // Entry should still reference the location
        let entryDescriptor = FetchDescriptor<SiteChangeEntry>()
        let entries = try context.fetch(entryDescriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.location?.zone == "Custom")
        #expect(entries.first?.note == "test note")
    }

    // MARK: - Zone Toggle

    @Test func togglingZoneDisablesBothLeftAndRight() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let left = Location(zone: "Hip", side: "left", isEnabled: true, isCustom: true, sortOrder: 0)
        let right = Location(zone: "Hip", side: "right", isEnabled: true, isCustom: true, sortOrder: 1)
        context.insert(left)
        context.insert(right)
        try context.save()

        // Simulate zone toggle off
        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        let hipLocations = locations.filter { $0.zone == "Hip" }
        for loc in hipLocations {
            loc.isEnabled = false
        }
        try context.save()

        let updated = try context.fetch(descriptor)
        for loc in updated {
            #expect(loc.isEnabled == false)
        }
    }

    @Test func togglingZoneEnablesBothLeftAndRight() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let left = Location(zone: "Hip", side: "left", isEnabled: false, isCustom: true, sortOrder: 0)
        let right = Location(zone: "Hip", side: "right", isEnabled: false, isCustom: true, sortOrder: 1)
        context.insert(left)
        context.insert(right)
        try context.save()

        // Simulate zone toggle on
        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        let hipLocations = locations.filter { $0.zone == "Hip" }
        for loc in hipLocations {
            loc.isEnabled = true
        }
        try context.save()

        let updated = try context.fetch(descriptor)
        for loc in updated {
            #expect(loc.isEnabled == true)
        }
    }

    // MARK: - Reorder

    @Test func reorderUpdatesAllSortOrders() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(zone: "Zone A", side: nil, isCustom: false, sortOrder: 0)
        let loc2 = Location(zone: "Zone B", side: nil, isCustom: false, sortOrder: 1)
        let loc3 = Location(zone: "Zone C", side: nil, isCustom: false, sortOrder: 2)
        context.insert(loc1)
        context.insert(loc2)
        context.insert(loc3)
        try context.save()

        // Simulate moving Zone C to the top: new order is C, A, B
        let reordered = [loc3, loc1, loc2]
        for (index, loc) in reordered.enumerated() {
            loc.sortOrder = index
        }
        try context.save()

        let descriptor = FetchDescriptor<Location>(sortBy: [SortDescriptor(\.sortOrder)])
        let sorted = try context.fetch(descriptor)
        #expect(sorted[0].zone == "Zone C")
        #expect(sorted[0].sortOrder == 0)
        #expect(sorted[1].zone == "Zone A")
        #expect(sorted[1].sortOrder == 1)
        #expect(sorted[2].zone == "Zone B")
        #expect(sorted[2].sortOrder == 2)
    }

    @Test func reorderWithLateralityKeepsPairsTogether() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Zone A: left=0, right=1; Zone B: left=2, right=3
        let aLeft = Location(zone: "Zone A", side: "left", sortOrder: 0)
        let aRight = Location(zone: "Zone A", side: "right", sortOrder: 1)
        let bLeft = Location(zone: "Zone B", side: "left", sortOrder: 2)
        let bRight = Location(zone: "Zone B", side: "right", sortOrder: 3)
        context.insert(aLeft)
        context.insert(aRight)
        context.insert(bLeft)
        context.insert(bRight)
        try context.save()

        // Move Zone B before Zone A: B group gets sortOrder 0,1 and A group gets 2,3
        let groups: [[(Location)]] = [[bLeft, bRight], [aLeft, aRight]]
        var sortOrder = 0
        for group in groups {
            for loc in group {
                loc.sortOrder = sortOrder
                sortOrder += 1
            }
        }
        try context.save()

        let descriptor = FetchDescriptor<Location>(sortBy: [SortDescriptor(\.sortOrder)])
        let sorted = try context.fetch(descriptor)
        #expect(sorted[0].zone == "Zone B")
        #expect(sorted[0].side == "left")
        #expect(sorted[0].sortOrder == 0)
        #expect(sorted[1].zone == "Zone B")
        #expect(sorted[1].side == "right")
        #expect(sorted[1].sortOrder == 1)
        #expect(sorted[2].zone == "Zone A")
        #expect(sorted[2].side == "left")
        #expect(sorted[2].sortOrder == 2)
        #expect(sorted[3].zone == "Zone A")
        #expect(sorted[3].side == "right")
        #expect(sorted[3].sortOrder == 3)
    }

    // MARK: - Display Name for Custom Zones

    @Test func customZoneDisplayNameWithoutLaterality() {
        let location = Location(zone: "Lower Back", side: nil, isCustom: true)
        #expect(location.displayName == "Lower Back")
    }

    @Test func customZoneDisplayNameWithLaterality() {
        let left = Location(zone: "Hip", side: "left", isCustom: true)
        let right = Location(zone: "Hip", side: "right", isCustom: true)
        #expect(left.displayName == "Left Hip")
        #expect(right.displayName == "Right Hip")
    }
}
