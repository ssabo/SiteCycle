import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct StatisticsViewModelDistributionTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Usage Distribution

    @Test func usageDistributionReturnsCorrectCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        let loc3 = Location(bodyPart: "Abdomen", subArea: "Back", side: "left")
        context.insert(loc1)
        context.insert(loc2)
        context.insert(loc3)

        let now = Date()
        for _ in 0..<5 {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(72 * 3600),
                location: loc1
            )
            context.insert(entry)
        }
        for _ in 0..<3 {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(72 * 3600),
                location: loc2
            )
            context.insert(entry)
        }
        let entry = SiteChangeEntry(
            startTime: now,
            endTime: now.addingTimeInterval(72 * 3600),
            location: loc3
        )
        context.insert(entry)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let dist = vm.usageDistribution
        let c1 = try #require(dist.first { $0.locationName == loc1.fullDisplayName })
        let c2 = try #require(dist.first { $0.locationName == loc2.fullDisplayName })
        let c3 = try #require(dist.first { $0.locationName == loc3.fullDisplayName })
        #expect(c1.count == 5)
        #expect(c2.count == 3)
        #expect(c3.count == 1)
    }

    @Test func usageDistributionExcludesLocationsWithZeroUses() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "left")
        context.insert(loc1)
        context.insert(loc2)

        let now = Date()
        let entry = SiteChangeEntry(
            startTime: now,
            endTime: now.addingTimeInterval(72 * 3600),
            location: loc1
        )
        context.insert(entry)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let dist = vm.usageDistribution
        #expect(dist.contains { $0.locationName == loc1.fullDisplayName })
        #expect(!dist.contains { $0.locationName == loc2.fullDisplayName })
    }

    // MARK: - Edge Cases

    @Test func statisticsWithNoDataReturnsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        #expect(vm.locationStats.isEmpty)
        #expect(vm.overallMedianDuration == nil)
        #expect(vm.usageDistribution.isEmpty)
    }

    @Test func statisticsWithSingleCompletedEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        let entry = SiteChangeEntry(
            startTime: now,
            endTime: now.addingTimeInterval(72 * 3600),
            location: location
        )
        context.insert(entry)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.totalUses == 1)
        let avg = try #require(stats.averageDuration)
        #expect(abs(avg - 72.0) < 0.01)
        let median = try #require(stats.medianDuration)
        #expect(abs(median - 72.0) < 0.01)
        let minDur = try #require(stats.minDuration)
        let maxDur = try #require(stats.maxDuration)
        #expect(abs(minDur - 72.0) < 0.01)
        #expect(abs(maxDur - 72.0) < 0.01)
    }
}
