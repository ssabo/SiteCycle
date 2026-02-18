import Testing
import Foundation
import SwiftData
@testable import SiteCycle

struct DefaultLocationsTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func seedsCorrectNumberOfLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        #expect(locations.count == 14)
    }

    @Test func seedIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)
        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        #expect(locations.count == 14)
    }

    @Test func allSeededLocationsAreEnabled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        for location in locations {
            #expect(location.isEnabled == true)
        }
    }

    @Test func allSeededLocationsAreNotCustom() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        for location in locations {
            #expect(location.isCustom == false)
        }
    }

    @Test func seededLocationsHaveLeftAndRightSides() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        let leftLocations = locations.filter { $0.side == "left" }
        let rightLocations = locations.filter { $0.side == "right" }
        #expect(leftLocations.count == 7)
        #expect(rightLocations.count == 7)
    }

    @Test func seededLocationsContainExpectedBodyParts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        let bodyParts = Set(locations.map(\.bodyPart))
        let expectedBodyParts: Set<String> = [
            "Abdomen", "Thigh", "Arm", "Buttock"
        ]
        #expect(bodyParts == expectedBodyParts)
    }

    @Test func seededLocationsContainExpectedZones() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        let zones = Set(locations.map(\.zone))
        let expectedZones: Set<String> = [
            "Front Abdomen", "Side Abdomen", "Back Abdomen",
            "Front Thigh", "Side Thigh", "Back Arm", "Buttock"
        ]
        #expect(zones == expectedZones)
    }

    @Test func seededLocationsHaveUniqueSortOrders() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        let sortOrders = locations.map(\.sortOrder)
        #expect(Set(sortOrders).count == 14)
    }

    @Test func sortOrdersAreSequential() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>(sortBy: [SortDescriptor(\.sortOrder)])
        let locations = try context.fetch(descriptor)
        for (index, location) in locations.enumerated() {
            #expect(location.sortOrder == index)
        }
    }

    @Test func doesNotSeedWhenLocationsExist() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Insert one location manually
        let existing = Location(bodyPart: "Custom Zone", sortOrder: 99)
        context.insert(existing)
        try context.save()

        seedDefaultLocations(context: context)

        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        // Should still be just 1 -- the manually inserted one
        #expect(locations.count == 1)
        #expect(locations.first?.bodyPart == "Custom Zone")
    }
}
