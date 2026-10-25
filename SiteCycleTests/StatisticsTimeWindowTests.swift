import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct StatisticsTimeWindowTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func approx(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.001
    }

    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    /// Inserts a completed entry that started `daysAgo` days before `now`.
    private func insertEntry(
        _ context: ModelContext,
        location: Location,
        daysAgo: Double,
        hours: Double,
        now: Date
    ) {
        let start = now.addingTimeInterval(-daysAgo * day)
        context.insert(SiteChangeEntry(
            startTime: start,
            endTime: start.addingTimeInterval(hours * hour),
            location: location
        ))
    }

    // MARK: - Percentile

    @Test func percentileInterpolatesLinearly() throws {
        let p25 = try #require(StatisticsViewModel.computePercentile([10, 20, 30, 40, 50], 25))
        #expect(abs(p25 - 20) < 0.001)
        let p10 = try #require(StatisticsViewModel.computePercentile([10, 20, 30, 40], 10))
        #expect(abs(p10 - 13) < 0.001)
    }

    @Test func percentileAt50MatchesMedian() throws {
        let values = [48.0, 60, 72, 80]
        let p50 = try #require(StatisticsViewModel.computePercentile(values, 50))
        let median = try #require(StatisticsViewModel.computeMedian(values))
        #expect(abs(p50 - median) < 0.001)
    }

    @Test func percentileOfEmptyIsNil() {
        #expect(StatisticsViewModel.computePercentile([], 25) == nil)
    }

    @Test func summaryOmitsPercentileBelowMinimumSamples() {
        let summary = StatisticsViewModel.summarize([48, 60, 72])
        #expect(approx(summary.median, 60))
        #expect(summary.percentile == nil)
    }

    @Test func summaryIncludesPercentileAtMinimumSamples() throws {
        let summary = StatisticsViewModel.summarize([48, 60, 72, 84])
        let p25 = try #require(summary.percentile)
        #expect(abs(p25 - 57) < 0.001)
    }

    // MARK: - Time Window

    @Test func windowStartDates() throws {
        let now = Date()
        #expect(StatsTimeWindow.allTime.startDate(relativeTo: now) == nil)
        let fourteen = try #require(StatsTimeWindow.fourteenDays.startDate(relativeTo: now))
        #expect(abs(now.timeIntervalSince(fourteen) - 14 * day) < 2 * hour)
        let oneMonth = try #require(StatsTimeWindow.oneMonth.startDate(relativeTo: now))
        let nineMonths = try #require(StatsTimeWindow.nineMonths.startDate(relativeTo: now))
        #expect(nineMonths < oneMonth)
        #expect(oneMonth < fourteen)
    }

    @Test func refreshFiltersDurationsAndCountsByWindow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        insertEntry(context, location: location, daysAgo: 100, hours: 24, now: now)
        insertEntry(context, location: location, daysAgo: 5, hours: 72, now: now)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, timeWindow: .fourteenDays)
        vm.refresh(now: now)
        #expect(approx(vm.overallMedianDuration, 72))
        let stats = try #require(vm.locationStats.first)
        #expect(stats.totalUses == 1)
        #expect(vm.usageDistribution.first?.count == 1)

        vm.timeWindow = .allTime
        vm.refresh(now: now)
        #expect(approx(vm.overallMedianDuration, 48))
        #expect(vm.locationStats.first?.totalUses == 2)
    }

    @Test func lastUsedIgnoresWindow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Thigh", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        insertEntry(context, location: location, daysAgo: 60, hours: 72, now: now)
        try context.save()

        let vm = StatisticsViewModel(modelContext: context, timeWindow: .fourteenDays)
        vm.refresh(now: now)
        let stats = try #require(vm.locationStats.first)
        #expect(stats.totalUses == 0)
        #expect(stats.lastUsed != nil)
        #expect(vm.usageDistribution.isEmpty)
    }

    @Test func activeSiteIsExcludedFromDurations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        for daysAgo in [12.0, 9, 6, 3] {
            insertEntry(context, location: location, daysAgo: daysAgo, hours: 72, now: now)
        }
        context.insert(SiteChangeEntry(startTime: now.addingTimeInterval(-hour), location: location))
        try context.save()

        let entries = location.safeEntries
        #expect(StatisticsViewModel.completedDurations(of: entries, since: nil).count == 4)
        let summary = StatisticsViewModel.summarize(
            StatisticsViewModel.completedDurations(of: entries, since: nil)
        )
        #expect(approx(summary.median, 72))
        #expect(approx(summary.percentile, 72))
    }

    // MARK: - Home Quick Stat

    @Test func homeQuickStatUsesWindowAndSkipsActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let now = Date()
        insertEntry(context, location: location, daysAgo: 200, hours: 30, now: now)
        for (daysAgo, hours) in [(12.0, 48.0), (9, 60), (6, 72), (3, 84)] {
            insertEntry(context, location: location, daysAgo: daysAgo, hours: hours, now: now)
        }
        context.insert(SiteChangeEntry(startTime: now.addingTimeInterval(-hour), location: location))
        try context.save()

        let viewModel = HomeViewModel(modelContext: context, quickStatWindow: .oneMonth)
        let stat = try #require(viewModel.quickStat)
        #expect(stat.sampleCount == 4)
        #expect(approx(stat.value(for: .median), 66))
        let p25 = try #require(stat.value(for: .percentile))
        #expect(abs(p25 - 57) < 0.001)

        viewModel.quickStatWindow = .allTime
        viewModel.refreshQuickStat()
        #expect(viewModel.quickStat?.sampleCount == 5)
    }
}
