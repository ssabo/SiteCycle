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

    @Test func overallMedianDurationAcrossAllLocations() throws {
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
        let avg = try #require(vm.overallMedianDuration)
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
        #expect(vm.overallMedianDuration == nil)
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

    // MARK: - Anomaly Filtering (static)

    @Test func filterAnomaliesExcludesHardFloorOutlier() {
        let durations = [8.0, 40.0, 44.0, 46.0, 48.0, 50.0]
        let result = StatisticsViewModel.filterAnomalies(durations)
        #expect(!result.filtered.contains(8.0))
        #expect(result.anomalyCount == 1)
    }

    @Test func filterAnomaliesExcludesIQROutlier() {
        // 20h passes the hard floor but is IQR-excluded (Q1=40, Q3=48, IQR=8, lower=28)
        let durations = [20.0, 40.0, 44.0, 46.0, 48.0, 50.0]
        let result = StatisticsViewModel.filterAnomalies(durations)
        #expect(!result.filtered.contains(20.0))
        #expect(result.anomalyCount == 1)
    }

    @Test func filterAnomaliesWithFewEntriesOnlyAppliesHardFloor() {
        // < 4 entries: IQR is skipped; only hard floor (12h) applies
        let durations = [8.0, 40.0, 50.0]
        let result = StatisticsViewModel.filterAnomalies(durations)
        #expect(result.filtered == [40.0, 50.0])
        #expect(result.anomalyCount == 1)
    }

    @Test func buildStatsAnomalyCountReflectsExcludedEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        for hours in [8.0, 40.0, 44.0, 46.0, 48.0, 50.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: location
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.totalUses == 6)
        #expect(stats.anomalyCount == 1)
    }

    @Test func absorptionFlagNotTriggeredWhenOnlyLowEntriesAreAnomalies() throws {
        // loc1 has two below-hard-floor entries (4h, 6h) that are excluded,
        // leaving a healthy filtered median. The flag should not fire.
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        for hours in [4.0, 6.0, 44.0, 46.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: loc1
            )
            context.insert(entry)
        }
        for hours in [50.0, 52.0, 54.0, 56.0] {
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
        #expect(s1.anomalyCount == 2)
        #expect(s1.absorptionFlag == nil)
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
