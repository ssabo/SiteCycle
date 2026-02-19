import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct StatisticsViewModelDurationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Per-Location: Min/Max Duration

    @Test func minMaxDurationReturnsCorrectRange() throws {
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
        let minDur = try #require(stats.minDuration)
        let maxDur = try #require(stats.maxDuration)
        #expect(abs(minDur - 48.0) < 0.01)
        #expect(abs(maxDur - 96.0) < 0.01)
    }

    @Test func minMaxDurationWithSingleEntry() throws {
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
        let minDur = try #require(stats.minDuration)
        let maxDur = try #require(stats.maxDuration)
        #expect(abs(minDur - 72.0) < 0.01)
        #expect(abs(maxDur - 72.0) < 0.01)
    }

    @Test func minMaxDurationIsNilWhenNoCompletedEntries() throws {
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
        #expect(stats.minDuration == nil)
        #expect(stats.maxDuration == nil)
    }

    // MARK: - Per-Location: Last Used & Days Since

    @Test func lastUsedReturnsNewestStartTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        let dates = [
            now.addingTimeInterval(-10 * 86400),
            now.addingTimeInterval(-5 * 86400),
            now.addingTimeInterval(-1 * 86400)
        ]
        for date in dates {
            let entry = SiteChangeEntry(
                startTime: date,
                endTime: date.addingTimeInterval(72 * 3600),
                location: location
            )
            context.insert(entry)
        }
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        let lastUsed = try #require(stats.lastUsed)
        #expect(abs(lastUsed.timeIntervalSince(dates[2])) < 1)
    }

    @Test func lastUsedIsNilForNeverUsedLocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.lastUsed == nil)
    }

    @Test func daysSinceLastUseCalculatesCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let tenDaysAgo = Date().addingTimeInterval(-10 * 86400)
        let entry = SiteChangeEntry(
            startTime: tenDaysAgo,
            endTime: tenDaysAgo.addingTimeInterval(72 * 3600),
            location: location
        )
        context.insert(entry)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        let days = try #require(stats.daysSinceLastUse)
        #expect(days == 10)
    }

    @Test func daysSinceLastUseIsNilForNeverUsedLocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context)
        vm.refresh()
        let stats = try #require(vm.locationStats.first { $0.location.id == location.id })
        #expect(stats.daysSinceLastUse == nil)
    }
}
