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
    /// Which unbroken run of rolling averages this week belongs to, so the
    /// line breaks across gaps instead of joining the weeks either side of
    /// them; nil when `rollingAverage` is nil.
    let trendSegment: Int?

    var id: Date { weekStart }
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
    /// including weeks without sites.
    ///
    /// - Dots and problem counts use only sites that started in the window,
    ///   like the rest of Statistics. The rolling average also pools earlier
    ///   sites, so the line starts warmed up.
    /// - A site whose `endTime` is after `now` (a fast clock on another
    ///   device, or a History edit) counts in the current week.
    static func weeklyPoints(
        entries: [SiteChangeEntry],
        since windowStart: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> [WeeklyDurationPoint] {
        var allSites: [Date: WeekBucket] = [:]
        var windowSites: [Date: WeekBucket] = [:]
        for entry in entries {
            guard let endTime = entry.endTime,
                  let hours = entry.durationHours, hours >= 0,
                  let week = weekStart(of: min(endTime, now), calendar: calendar) else { continue }
            allSites[week, default: WeekBucket()].add(hours: hours, hasProblem: entry.hasProblems)
            if windowStart.map({ entry.startTime >= $0 }) ?? true {
                windowSites[week, default: WeekBucket()].add(hours: hours, hasProblem: entry.hasProblems)
            }
        }

        let weeks = consecutiveWeeks(from: allSites.keys.min(), to: now, calendar: calendar)
        let windowWeek = windowStart.flatMap { weekStart(of: $0, calendar: calendar) }

        var points: [WeeklyDurationPoint] = []
        var segment = 0
        for (index, week) in weeks.enumerated() {
            let trailing = weeks[max(0, index - rollingWeeks + 1)...index]
                .reduce(into: WeekBucket()) { $0.merge(allSites[$1]) }
            if trailing.mean == nil { segment += 1 }
            if let windowWeek, week < windowWeek { continue }
            let bucket = windowSites[week] ?? WeekBucket()
            points.append(WeeklyDurationPoint(
                weekStart: week,
                siteCount: bucket.sites,
                averageDuration: bucket.mean,
                rollingAverage: trailing.mean,
                problemSiteCount: bucket.problemCount,
                trendSegment: trailing.mean == nil ? nil : segment
            ))
        }
        return points
    }

    private static func weekStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    /// Week starts from the week containing `first` through the week
    /// containing `now`. Each step is the previous week's interval end, not
    /// "add one week": where DST starts at midnight that week starts at 01:00,
    /// and adding weeks would keep 01:00 while later weeks start at 00:00.
    private static func consecutiveWeeks(from first: Date?, to now: Date, calendar: Calendar) -> [Date] {
        guard let first, let last = weekStart(of: now, calendar: calendar) else { return [] }
        var weeks: [Date] = []
        var cursor = first
        while cursor <= last {
            weeks.append(cursor)
            guard let next = calendar.dateInterval(of: .weekOfYear, for: cursor)?.end, next > cursor else { break }
            cursor = next
        }
        return weeks
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
