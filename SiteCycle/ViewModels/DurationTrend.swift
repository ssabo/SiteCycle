import Foundation

/// One calendar week on the Statistics "Duration Trend" chart.
struct WeeklyDurationPoint: Identifiable, Equatable {
    /// Start of the calendar week (the calendar's `firstWeekday`).
    let weekStart: Date
    /// Completed sites that ended this week.
    let siteCount: Int
    /// Mean duration of the sites that ended this week; nil when none did.
    let averageDuration: Double?
    /// Pooled mean of every site that ended in this week and the
    /// `DurationTrend.rollingWeeks - 1` weeks before it; nil when none did.
    let rollingAverage: Double?
    /// Sites that ended this week with at least one problem recorded.
    let problemSiteCount: Int

    var id: Date { weekStart }
}

/// Change in the rolling average between the latest week and
/// `DurationTrend.rollingWeeks` weeks earlier (non-overlapping spans).
struct DurationTrendChange: Equatable {
    let current: Double
    let previous: Double

    var delta: Double { current - previous }
}

/// Weekly average site duration, with a trailing moving average, so the user
/// can see whether they are changing sites more or less often over time.
///
/// - Each completed site belongs to exactly one week: the week its `endTime`
///   falls in, i.e. the week the site change happened. Sites aren't split
///   across week boundaries, so every weekly value is an average of whole
///   sites, and a week full of early changes (and the problems recorded at
///   those changes) shows up as a low point in that week.
/// - The rolling average pools the sites of the trailing weeks (total hours ÷
///   site count) rather than averaging weekly means, so weeks with more sites
///   weigh more and empty weeks don't break it.
/// - No anomaly filtering: short sites are exactly what this chart is for.
///   The active site is skipped, since it hasn't ended.
enum DurationTrend {
    /// Weeks pooled into the moving average. Sites are changed every 1.5–3
    /// days, so 4 weeks pools roughly 10–20 sites: enough to smooth out one
    /// bad week without hiding a change that lasts a month.
    static let rollingWeeks = 4

    /// Points from the week containing `windowStart` (or the first completed
    /// site, if later) through the week containing `now`, one per week,
    /// including weeks without sites. The rolling average also looks at
    /// sites before `windowStart`, so the line starts warmed up.
    static func weeklyPoints(
        entries: [SiteChangeEntry],
        since windowStart: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> [WeeklyDurationPoint] {
        var buckets: [Date: WeekBucket] = [:]
        for entry in entries {
            guard let endTime = entry.endTime,
                  let hours = entry.durationHours, hours >= 0,
                  let week = calendar.dateInterval(of: .weekOfYear, for: endTime)?.start else { continue }
            buckets[week, default: WeekBucket()].add(hours: hours, hasProblem: entry.hasProblems)
        }

        guard let firstWeek = buckets.keys.min(),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              firstWeek <= lastWeek else { return [] }
        let windowWeek = windowStart.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }

        var weeks: [Date] = []
        var cursor = firstWeek
        while cursor <= lastWeek {
            weeks.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        var points: [WeeklyDurationPoint] = []
        for (index, week) in weeks.enumerated() {
            if let windowWeek, week < windowWeek { continue }
            let bucket = buckets[week] ?? WeekBucket()
            let trailing = weeks[max(0, index - rollingWeeks + 1)...index]
                .reduce(into: WeekBucket()) { $0.merge(buckets[$1]) }
            points.append(WeeklyDurationPoint(
                weekStart: week,
                siteCount: bucket.sites,
                averageDuration: bucket.mean,
                rollingAverage: trailing.mean,
                problemSiteCount: bucket.problemCount
            ))
        }
        return points
    }

    /// The latest rolling average against the one `rollingWeeks` weeks
    /// earlier, or nil if either is missing.
    static func recentChange(in points: [WeeklyDurationPoint]) -> DurationTrendChange? {
        guard points.count > rollingWeeks,
              let current = points[points.count - 1].rollingAverage,
              let previous = points[points.count - 1 - rollingWeeks].rollingAverage else { return nil }
        return DurationTrendChange(current: current, previous: previous)
    }

    private struct WeekBucket {
        var totalHours: Double = 0
        var sites = 0
        var problemCount = 0

        var mean: Double? { sites > 0 ? totalHours / Double(sites) : nil }

        mutating func add(hours: Double, hasProblem: Bool) {
            totalHours += hours
            sites += 1
            if hasProblem { problemCount += 1 }
        }

        mutating func merge(_ other: WeekBucket?) {
            guard let other else { return }
            totalHours += other.totalHours
            sites += other.sites
            problemCount += other.problemCount
        }
    }
}
