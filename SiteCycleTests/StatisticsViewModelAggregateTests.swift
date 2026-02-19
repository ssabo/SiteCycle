import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct StatisticsViewModelAggregateTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Overall Average

    @Test func overallAverageDurationAcrossAllLocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        let loc3 = Location(bodyPart: "Abdomen", subArea: "Back", side: "left")
        context.insert(loc1)
        context.insert(loc2)
        context.insert(loc3)

        let now = Date()
        let pairs: [(Location, Double)] = [(loc1, 48), (loc2, 72), (loc3, 96)]
        for (loc, hours) in pairs {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let avg = try #require(vm.overallAverageDuration)
        #expect(abs(avg - 72.0) < 0.01)
    }

    @Test func overallAverageIsNilWhenNoCompletedEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let active = SiteChangeEntry(startTime: Date(), location: location)
        context.insert(active)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        #expect(vm.overallAverageDuration == nil)
    }

    // MARK: - Absorption Insight

    @Test func absorptionFlagTriggeredWhenBelowThreshold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        for hours in [50.0, 55.0, 60.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc1
            )
            context.insert(entry)
        }
        for hours in [84.0, 89.0, 94.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc2
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, absorptionThreshold: 20)
        vm.refresh()
        let s1 = try #require(vm.locationStats.first { $0.location.id == loc1.id })
        #expect(s1.absorptionFlag != nil)
        let s2 = try #require(vm.locationStats.first { $0.location.id == loc2.id })
        #expect(s2.absorptionFlag == nil)
    }

    @Test func absorptionFlagNotTriggeredWhenAboveThreshold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        for hours in [60.0, 65.0, 70.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc1
            )
            context.insert(entry)
        }
        for hours in [74.0, 79.0, 84.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc2
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, absorptionThreshold: 20)
        vm.refresh()
        let s1 = try #require(vm.locationStats.first { $0.location.id == loc1.id })
        #expect(s1.absorptionFlag == nil)
    }

    @Test func absorptionFlagNotTriggeredAtExactThreshold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        let entry1 = SiteChangeEntry(
            startTime: now,
            endTime: now.addingTimeInterval(80.0 * 3600),
            location: loc1
        )
        context.insert(entry1)
        let entry2 = SiteChangeEntry(
            startTime: now,
            endTime: now.addingTimeInterval(120.0 * 3600),
            location: loc2
        )
        context.insert(entry2)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, absorptionThreshold: 20)
        vm.refresh()
        let s1 = try #require(vm.locationStats.first { $0.location.id == loc1.id })
        #expect(s1.absorptionFlag == nil)
    }

    @Test func absorptionFlagCustomThreshold() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        for hours in [60.0, 63.0, 66.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc1
            )
            context.insert(entry)
        }
        for hours in [78.0, 81.0, 84.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc2
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, absorptionThreshold: 10)
        vm.refresh()
        let s1 = try #require(vm.locationStats.first { $0.location.id == loc1.id })
        #expect(s1.absorptionFlag != nil)
    }

    @Test func absorptionFlagMessageIncludesPercentage() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        for hours in [50.0, 55.0, 60.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc1
            )
            context.insert(entry)
        }
        for hours in [84.0, 89.0, 94.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc2
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, absorptionThreshold: 20)
        vm.refresh()
        let s1 = try #require(vm.locationStats.first { $0.location.id == loc1.id })
        let flag = try #require(s1.absorptionFlag)
        #expect(flag.contains("% below"))
    }

    @Test func absorptionFlagSkipsLocationsWithNoCompletedEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        let active = SiteChangeEntry(startTime: now, location: loc1)
        context.insert(active)
        let completed = SiteChangeEntry(
            startTime: now,
            endTime: now.addingTimeInterval(72 * 3600),
            location: loc2
        )
        context.insert(completed)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, absorptionThreshold: 20)
        vm.refresh()
        let s1 = try #require(vm.locationStats.first { $0.location.id == loc1.id })
        #expect(s1.absorptionFlag == nil)
    }
}
