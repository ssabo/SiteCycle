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
        // The line breaks across the gap instead of joining week 3 to week 5.
        #expect(points.map(\.trendSegment) == [0, 0, 0, 0, nil, 1])
    }

    @Test func windowTrimsWeeksAndDotsButTheRollingAverageSeesEarlierSites() throws {
        let entries = [
            site(from: try date(1, 5), hours: 40),
            // Ends in the window's week but started before the window: line only.
            site(from: try date(1, 12), hours: 35),
            site(from: try date(1, 14), hours: 30),
        ]

        let points = DurationTrend.weeklyPoints(
            entries: entries, since: try date(1, 14), now: try date(1, 16), calendar: calendar
        )

        #expect(points.map(\.weekStart) == [try date(1, 12, 0)])
        #expect(points[0].siteCount == 1)
        #expect(approx(points[0].averageDuration, 30))
        #expect(approx(points[0].rollingAverage, 35))
    }

    @Test func siteEndingAfterNowCountsInTheCurrentWeek() throws {
        // Sat 17 Jan → Mon 19 Jan, but "now" is Sun 18 Jan (e.g. another device's fast clock).
        let entries = [site(from: try date(1, 17), hours: 48)]

        let points = DurationTrend.weeklyPoints(
            entries: entries, since: nil, now: try date(1, 18), calendar: calendar
        )

        #expect(points.map(\.weekStart) == [try date(1, 12, 0)])
        #expect(points.map(\.siteCount) == [1])
        #expect(approx(points[0].averageDuration, 48))
    }

    @Test func weeksLineUpAfterAMidnightDSTStart() throws {
        // Chile starts DST at midnight on Sun 6 Sep 2026, so that week starts at 01:00
        // while the following weeks start at 00:00 again.
        var santiago = Calendar(identifier: .gregorian)
        santiago.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        santiago.firstWeekday = 1
        func day(_ day: Int) throws -> Date {
            try #require(santiago.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12)))
        }
        let entries = [
            site(from: try day(7), hours: 48),
            site(from: try day(13), hours: 60),
            site(from: try day(20), hours: 72),
        ]

        let points = DurationTrend.weeklyPoints(entries: entries, since: nil, now: try day(23), calendar: santiago)

        #expect(points.map(\.siteCount) == [1, 1, 1])
        #expect(approx(points[2].averageDuration, 72))
        #expect(approx(points[2].rollingAverage, 60))
    }

    @Test func noCompletedSitesGivesNoPoints() throws {
        let points = DurationTrend.weeklyPoints(
            entries: [SiteChangeEntry(startTime: try date(1, 5))],
            since: nil, now: try date(1, 6), calendar: calendar
        )
        #expect(points.isEmpty)
    }
}
