import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct StatisticsViewModelProblemTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    private func completed(daysAgo: Double, now: Date, problem: SiteProblem? = nil) -> SiteChangeEntry {
        let start = now.addingTimeInterval(-daysAgo * day)
        return SiteChangeEntry(startTime: start, endTime: start.addingTimeInterval(48 * hour), problem: problem)
    }

    // MARK: - summarizeProblems

    @Test func summaryCountsEachAndAnyProblem() throws {
        let now = Date()
        let painful = SiteProblem(name: "Painful", emoji: "🤕", sortOrder: 0)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 1)
        let entries = [
            completed(daysAgo: 10, now: now, problem: leaking),
            completed(daysAgo: 8, now: now, problem: leaking),
            completed(daysAgo: 6, now: now, problem: painful),
            completed(daysAgo: 4, now: now),
        ]

        let summary = StatisticsViewModel.summarizeProblems(entries)

        #expect(summary.siteCount == 4)
        #expect(summary.problemSiteCount == 3)
        let rate = try #require(summary.anyProblemRate)
        #expect(abs(rate - 0.75) < 0.001)
        #expect(summary.items.map(\.problem.name) == ["Leaking", "Painful"])
        #expect(summary.items.map(\.count) == [2, 1])
        #expect(abs(summary.items[0].rate - 0.5) < 0.001)
    }

    @Test func summaryBreaksCountTiesBySortOrder() {
        let now = Date()
        let first = SiteProblem(name: "First", emoji: "1️⃣", sortOrder: 0)
        let second = SiteProblem(name: "Second", emoji: "2️⃣", sortOrder: 1)
        let entries = [
            completed(daysAgo: 4, now: now, problem: second),
            completed(daysAgo: 2, now: now, problem: first),
        ]

        let summary = StatisticsViewModel.summarizeProblems(entries)

        #expect(summary.items.map(\.problem.name) == ["First", "Second"])
    }

    @Test func summarySkipsActiveSiteWithoutProblem() {
        let now = Date()
        let entries = [
            completed(daysAgo: 4, now: now),
            SiteChangeEntry(startTime: now.addingTimeInterval(-hour)),
        ]

        let summary = StatisticsViewModel.summarizeProblems(entries)

        #expect(summary.siteCount == 1)
        #expect(summary.problemSiteCount == 0)
        #expect(summary.items.isEmpty)
    }

    @Test func summaryCountsActiveSiteThatAlreadyHasProblem() {
        let now = Date()
        let painful = SiteProblem(name: "Painful", emoji: "🤕")
        let entries = [
            completed(daysAgo: 4, now: now),
            SiteChangeEntry(startTime: now.addingTimeInterval(-hour), problem: painful),
        ]

        let summary = StatisticsViewModel.summarizeProblems(entries)

        #expect(summary.siteCount == 2)
        #expect(summary.problemSiteCount == 1)
    }

    @Test func summaryOfNoEntriesHasNoRate() {
        let summary = StatisticsViewModel.summarizeProblems([])
        #expect(summary.siteCount == 0)
        #expect(summary.anyProblemRate == nil)
    }

    // MARK: - refresh()

    @Test func refreshRespectsTimeWindowAndPerLocationCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date()

        let abdomen = Location(bodyPart: "Abdomen", sortOrder: 0)
        let thigh = Location(bodyPart: "Thigh", sortOrder: 1)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧")
        context.insert(abdomen)
        context.insert(thigh)
        context.insert(leaking)

        let old = completed(daysAgo: 60, now: now, problem: leaking)
        old.location = abdomen
        let recentProblem = completed(daysAgo: 6, now: now, problem: leaking)
        recentProblem.location = abdomen
        let recentClean = completed(daysAgo: 3, now: now)
        recentClean.location = thigh
        [old, recentProblem, recentClean].forEach { context.insert($0) }
        try context.save()

        let viewModel = StatisticsViewModel(modelContext: context, timeWindow: .oneMonth)
        viewModel.refresh(now: now)

        #expect(viewModel.problemSummary.siteCount == 2)
        #expect(viewModel.problemSummary.problemSiteCount == 1)
        let abdomenStats = try #require(viewModel.locationStats.first { $0.location.id == abdomen.id })
        let thighStats = try #require(viewModel.locationStats.first { $0.location.id == thigh.id })
        #expect(abdomenStats.problemCount == 1)
        #expect(thighStats.problemCount == 0)

        viewModel.timeWindow = .allTime
        viewModel.refresh(now: now)

        #expect(viewModel.problemSummary.siteCount == 3)
        #expect(viewModel.problemSummary.problemSiteCount == 2)
        #expect(viewModel.problemSummary.items.first?.count == 2)
    }
}
