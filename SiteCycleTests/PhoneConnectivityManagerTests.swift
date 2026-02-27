import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct PhoneConnectivityManagerTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func buildWatchAppStateWithNoData() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let state = PhoneConnectivityManager.buildWatchAppState(context: context)

        #expect(state.activeSite == nil)
        #expect(state.allLocations.isEmpty)
        #expect(state.recommendedIds.isEmpty)
        #expect(state.avoidIds.isEmpty)
        #expect(state.targetDurationHours == 72)
    }

    @Test func buildWatchAppStateWithLocations() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Front", side: "right", sortOrder: 1)
        context.insert(loc1)
        context.insert(loc2)
        try context.save()

        let state = PhoneConnectivityManager.buildWatchAppState(context: context)

        #expect(state.allLocations.count == 2)
        #expect(state.activeSite == nil)
        #expect(state.recommendedIds.count == 2)
        #expect(state.avoidIds.isEmpty)
    }

    @Test func buildWatchAppStateWithActiveSite() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let loc = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        context.insert(loc)

        let entry = SiteChangeEntry(startTime: Date(), location: loc)
        context.insert(entry)
        try context.save()

        let state = PhoneConnectivityManager.buildWatchAppState(context: context)

        let activeSite = try #require(state.activeSite)
        #expect(activeSite.locationName == "L Abdomen (Front)")
    }

    @Test func buildWatchAppStateExcludesDisabledLocations() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let enabled = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let disabled = Location(
            bodyPart: "Back",
            subArea: nil,
            side: nil,
            isEnabled: false,
            sortOrder: 1
        )
        context.insert(enabled)
        context.insert(disabled)
        try context.save()

        let state = PhoneConnectivityManager.buildWatchAppState(context: context)

        #expect(state.allLocations.count == 1)
        #expect(state.allLocations.first?.bodyPart == "Abdomen")
    }
}
