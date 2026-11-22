import Testing
import Foundation
@testable import SiteCycle

@MainActor
struct DurationTrendTests {

    /// Gregorian, UTC, weeks start on Monday. 2026-01-05 is a Monday.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    private func site(
        from start: Date,
        hours: Double,
        problems: [SiteProblem] = []
    ) -> SiteChangeEntry {
        SiteChangeEntry(startTime: start, endTime: start.addingTimeInterval(hours * 3600), problems: problems)
    }

    private func approx(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.001
    }

    // MARK: - Weekly buckets

    @Test func sitesBelongToTheWeekTheyEnded() throws {
        let entries = [
            // Sun 4 Jan → Tue 6 Jan: straddles the boundary, counts in the week of 5 Jan.
            site(from: try date(1, 4), hours: 48),
            site(from: try date(1, 6), hours: 72),   // ends Fri 9 Jan
            site(from: try date(1, 9), hours: 72),   // ends Mon 12 Jan
            SiteChangeEntry(startTime: try date(1, 12)), // active: skipped
        ]

        let points = DurationTrend.weeklyPoints(
            entries: entries, since: nil, now: try date(1, 13), calendar: calendar
        )

        #expect(points.map(\.weekStart) == [try date(1, 5, 0), try date(1, 12, 0)])
        #expect(points.map(\.siteCount) == [2, 1])
        #expect(approx(points[0].averageDuration, 60))
        #expect(approx(points[1].averageDuration, 72))
        #expect(approx(points[0].rollingAverage, 60))
        #expect(approx(points[1].rollingAverage, 64))
    }

    @Test func countsSitesWithAnyProblemPerWeek() throws {
        let painful = SiteProblem(name: "Painful", emoji: "🤕", sortOrder: 0)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 1)
        let entries = [
            site(from: try date(1, 5), hours: 20, problems: [painful, leaking]),
            site(from: try date(1, 6, 8), hours: 30, problems: [leaking]),
            site(from: try date(1, 7, 14), hours: 72),
            site(from: try date(1, 12), hours: 72),
        ]

        let points = DurationTrend.weeklyPoints(
            entries: entries, since: nil, now: try date(1, 16), calendar: calendar
        )

        #expect(points.map(\.siteCount) == [3, 1])
        #expect(points.map(\.problemSiteCount) == [2, 0])
        // Short problem sites aren't filtered out as anomalies.
        #expect(approx(points[0].averageDuration, 122.0 / 3))
    }

    // MARK: - Rolling average

    @Test func rollingAveragePoolsSitesRatherThanAveragingWeeks() throws {
        let entries = [
            site(from: try date(1, 5), hours: 30),
            site(from: try date(1, 12), hours: 60),
            site(from: try date(1, 14, 12), hours: 60),
            site(from: try date(1, 16, 12), hours: 20), // ends Sat 17 Jan
        ]

        let points = DurationTrend.weeklyPoints(
            entries: entries, since: nil, now: try date(1, 18), calendar: calendar
        )

        #expect(points.count == 2)
        #expect(approx(points[1].averageDuration, 140.0 / 3))
        // (30 + 60 + 60 + 20) / 4, not the mean of the weekly means (38.3).
        #expect(approx(points[1].rollingAverage, 42.5))
    }

    @Test func emptyWeeksAreKeptAndOldWeeksLeaveTheRollingWindow() throws {
        let entries = [
            site(from: try date(1, 5), hours: 50),  // week of 5 Jan
            site(from: try date(2, 9), hours: 70),  // week of 9 Feb, five weeks later
        ]

        let points = DurationTrend.weeklyPoints(
            entries: entries, since: nil, now: try date(2, 12), calendar: calendar
        )

        #expect(points.count == 6)
        #expect(points.map(\.siteCount) == [1, 0, 0, 0, 0, 1])
        #expect(points.map { $0.averageDuration == nil } == [false, true, true, true, true, false])
        #expect(approx(points[3].rollingAverage, 50))
        #expect(points[4].rollingAverage == nil)
        #expect(approx(points[5].rollingAverage, 70))
    }

    @Test func windowTrimsWeeksButTheRollingAverageSeesEarlierSites() throws {
        let entries = [
            site(from: try date(1, 5), hours: 40),
            site(from: try date(1, 12), hours: 60),
        ]

        let points = DurationTrend.weeklyPoints(
            entries: entries, since: try date(1, 14), now: try date(1, 16), calendar: calendar
        )

        #expect(points.map(\.weekStart) == [try date(1, 12, 0)])
        #expect(approx(points[0].averageDuration, 60))
        #expect(approx(points[0].rollingAverage, 50))
    }

    @Test func noCompletedSitesGivesNoPoints() throws {
        let points = DurationTrend.weeklyPoints(
            entries: [SiteChangeEntry(startTime: try date(1, 5))],
            since: nil, now: try date(1, 6), calendar: calendar
        )
        #expect(points.isEmpty)
    }

    // MARK: - Recent change

    private func point(_ weekIndex: Int, rolling: Double?) throws -> WeeklyDurationPoint {
        WeeklyDurationPoint(
            weekStart: try date(1, 5 + 7 * weekIndex, 0),
            siteCount: 0,
            averageDuration: nil,
            rollingAverage: rolling,
            problemSiteCount: 0
        )
    }

    @Test func recentChangeComparesWithFourWeeksEarlier() throws {
        let points = [
            try point(0, rolling: 70), try point(1, rolling: 66), try point(2, rolling: 64),
            try point(3, rolling: 61), try point(4, rolling: 58), try point(5, rolling: 55),
        ]

        let change = try #require(DurationTrend.recentChange(in: points))

        #expect(approx(change.current, 55))
        #expect(approx(change.previous, 66))
        #expect(approx(change.delta, -11))
    }

    @Test func recentChangeNeedsBothEnds() throws {
        let tooShort = [
            try point(0, rolling: 70), try point(1, rolling: 66), try point(2, rolling: 64), try point(3, rolling: 61),
        ]
        #expect(DurationTrend.recentChange(in: tooShort) == nil)

        let missingPrevious = [
            try point(0, rolling: nil), try point(1, rolling: 66), try point(2, rolling: 64),
            try point(3, rolling: 61), try point(4, rolling: 58),
        ]
        #expect(DurationTrend.recentChange(in: missingPrevious) == nil)
    }
}
