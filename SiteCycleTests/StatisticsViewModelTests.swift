import Testing
import Foundation
import SwiftData
@testable import SiteCycle

struct StatisticsViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Per-Location: Total Uses

    @Test func totalUsesCountsAllEntriesForLocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        for i in 0..<3 {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(i) * 86400),
                endTime: now.addingTimeInterval(Double(i) * 86400 + 72 * 3600),
                location: location
            )
            context.insert(entry)
        }
        let active = SiteChangeEntry(
            startTime: now.addingTimeInterval(3 * 86400),
            location: location
        )
        context.insert(active)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.totalUses == 4)
    }

    @Test func totalUsesIsZeroForNeverUsedLocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.totalUses == 0)
    }

    // MARK: - Per-Location: Average Duration

    @Test func averageDurationComputesMeanOfCompletedEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        let durations: [Double] = [48, 72, 96]
        for (i, hours) in durations.enumerated() {
            let entry = SiteChangeEntry(
                startTime: now.addingTimeInterval(Double(i) * 200 * 3600),
                endTime: now.addingTimeInterval(Double(i) * 200 * 3600 + hours * 3600),
                location: location
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        let avg = try #require(stats.averageDuration)
        #expect(abs(avg - 72.0) < 0.01)
    }

    @Test func averageDurationExcludesActiveEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        for hours in [48.0, 72.0] {
            let entry = SiteChangeEntry(
                startTime: now,
                endTime: now.addingTimeInterval(hours * 3600),
                location: location
            )
            context.insert(entry)
        }
        let active = SiteChangeEntry(startTime: now, location: location)
        context.insert(active)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        let avg = try #require(stats.averageDuration)
        #expect(abs(avg - 60.0) < 0.01)
    }

    @Test func averageDurationIsNilWhenNoCompletedEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let active = SiteChangeEntry(startTime: Date(), location: location)
        context.insert(active)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.averageDuration == nil)
    }

    // MARK: - Per-Location: Median Duration

    @Test func medianDurationReturnsMiddleValueForOddCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        for hours in [48.0, 72.0, 96.0] {
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
        let median = try #require(stats.medianDuration)
        #expect(abs(median - 72.0) < 0.01)
    }

    @Test func medianDurationReturnsAverageOfMiddleTwoForEvenCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        for hours in [48.0, 60.0, 72.0, 96.0] {
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
        let median = try #require(stats.medianDuration)
        #expect(abs(median - 66.0) < 0.01)
    }

    @Test func medianDurationIsNilWhenNoCompletedEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let active = SiteChangeEntry(startTime: Date(), location: location)
        context.insert(active)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.medianDuration == nil)
    }

    @Test func medianDurationWithSingleEntry() throws {
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
        let median = try #require(stats.medianDuration)
        #expect(abs(median - 72.0) < 0.01)
    }
}
