import Foundation
import Observation
import SwiftData

struct LocationStats {
    let location: Location
    let totalUses: Int
    let averageDuration: Double?
    let medianDuration: Double?
    let percentileDuration: Double?
    let minDuration: Double?
    let maxDuration: Double?
    let lastUsed: Date?
    let daysSinceLastUse: Int?
    let absorptionFlag: String?
    let anomalyCount: Int
    /// Entries in the window with a problem recorded.
    let problemCount: Int
}

struct UsageDistributionItem {
    let locationName: String
    let count: Int
}

/// Time range the duration statistics are computed over. Entries are included
/// when their `startTime` falls inside the window.
enum StatsTimeWindow: String, CaseIterable, Identifiable {
    case allTime
    case nineMonths
    case threeMonths
    case oneMonth
    case fourteenDays

    static let statisticsStorageKey = "statisticsTimeWindow"
    static let homeStatStorageKey = "homeStatTimeWindow"
    static let defaultHomeStatWindow: StatsTimeWindow = .oneMonth

    var id: String { rawValue }

    /// Compact label for segmented pickers and the Home badge.
    var shortName: String {
        switch self {
        case .allTime: return "All"
        case .nineMonths: return "9mo"
        case .threeMonths: return "3mo"
        case .oneMonth: return "1mo"
        case .fourteenDays: return "14d"
        }
    }

    var displayName: String {
        switch self {
        case .allTime: return "All Time"
        case .nineMonths: return "Last 9 Months"
        case .threeMonths: return "Last 3 Months"
        case .oneMonth: return "Last Month"
        case .fourteenDays: return "Last 14 Days"
        }
    }

    /// Earliest `startTime` included in the window, or nil for all time.
    func startDate(relativeTo now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .allTime: return nil
        case .nineMonths: return calendar.date(byAdding: .month, value: -9, to: now)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now)
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: now)
        case .fourteenDays: return calendar.date(byAdding: .day, value: -14, to: now)
        }
    }
}

/// Which duration statistic the Home screen badge shows.
enum HomeStatMetric: String, CaseIterable, Identifiable {
    case median
    case percentile

    static let storageKey = "homeStatMetric"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .median: return "Median"
        case .percentile: return StatisticsViewModel.percentileDisplayName
        }
    }

    var shortName: String {
        switch self {
        case .median: return "Med"
        case .percentile: return StatisticsViewModel.percentileShortName
        }
    }
}

struct DurationSummary: Equatable {
    let median: Double?
    let percentile: Double?
    let sampleCount: Int
    let anomalyCount: Int

    func value(for metric: HomeStatMetric) -> Double? {
        switch metric {
        case .median: return median
        case .percentile: return percentile
        }
    }
}

@MainActor
@Observable
final class StatisticsViewModel {
    private let modelContext: ModelContext
    let absorptionThreshold: Int
    var timeWindow: StatsTimeWindow

    private(set) var locationStats: [LocationStats] = []
    private(set) var overallMedianDuration: Double?
    private(set) var overallPercentileDuration: Double?
    private(set) var usageDistribution: [UsageDistributionItem] = []
    private(set) var problemSummary = ProblemSummary(siteCount: 0, problemSiteCount: 0, items: [])

    init(
        modelContext: ModelContext,
        absorptionThreshold: Int = 20,
        timeWindow: StatsTimeWindow = .allTime
    ) {
        self.modelContext = modelContext
        self.absorptionThreshold = absorptionThreshold
        self.timeWindow = timeWindow
    }

    func refresh(now: Date = Date()) {
        let locations = Self.fetchEnabledLocations(in: modelContext)
        let windowStart = timeWindow.startDate(relativeTo: now)

        let allEntries = locations.flatMap(\.safeEntries)
        let overall = Self.summarize(Self.completedDurations(of: allEntries, since: windowStart))
        overallMedianDuration = overall.median
        overallPercentileDuration = overall.percentile
        problemSummary = Self.summarizeProblems(Self.entries(allEntries, since: windowStart))

        locationStats = locations.map { location in
            buildStats(
                for: location,
                windowStart: windowStart,
                overallMedian: overallMedianDuration,
                now: now
            )
        }

        usageDistribution = locations.compactMap { location in
            let count = Self.entries(location.safeEntries, since: windowStart).count
            guard count > 0 else { return nil }
            return UsageDistributionItem(locationName: location.fullDisplayName, count: count)
        }
    }

    // MARK: - Duration Summary

    /// The lower quartile. Site changes happen roughly every 1.5–3 days, so a
    /// 14-day window holds only ~5–9 completed sites and a month ~10–20. A tail
    /// percentile like P10 would just be the single shortest site at that size,
    /// while P25 stays stable and answers the useful question: "1 in 4 of my
    /// sites ended before this" — i.e. how often sites fail early.
    nonisolated static let durationPercentile: Double = 25
    nonisolated static let percentileDisplayName = "25th Percentile"
    nonisolated static let percentileShortName = "P25"
    /// Below this many durations the percentile is just the minimum, so it is omitted.
    nonisolated static let minimumPercentileSampleCount = 4

    static func fetchEnabledLocations(in modelContext: ModelContext) -> [Location] {
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate<Location> { $0.isEnabled == true },
            sortBy: [SortDescriptor(\Location.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Entries whose `startTime` is on or after `start` (all entries when nil).
    static func entries(_ entries: [SiteChangeEntry], since start: Date?) -> [SiteChangeEntry] {
        guard let start else { return entries }
        return entries.filter { $0.startTime >= start }
    }

    /// Durations of completed entries in the window. The active site (no
    /// `endTime`) is always skipped — a freshly placed site would drag the
    /// numbers down.
    static func completedDurations(of entries: [SiteChangeEntry], since start: Date?) -> [Double] {
        Self.entries(entries, since: start)
            .filter { $0.endTime != nil }
            .compactMap(\.durationHours)
    }

    /// Median and percentile after anomaly filtering.
    static func summarize(_ durations: [Double]) -> DurationSummary {
        let result = filterAnomalies(durations)
        let percentile = result.filtered.count >= minimumPercentileSampleCount
            ? computePercentile(result.filtered, durationPercentile)
            : nil
        return DurationSummary(
            median: computeMedian(result.filtered),
            percentile: percentile,
            sampleCount: result.filtered.count,
            anomalyCount: result.anomalyCount
        )
    }

    // MARK: - Anomaly Filtering

    struct AnomalyFilterResult {
        let filtered: [Double]
        let anomalyCount: Int
    }

    static let anomalyHardFloor: Double = 12.0

    static func filterAnomalies(_ durations: [Double]) -> AnomalyFilterResult {
        guard durations.count >= 4 else {
            let filtered = durations.filter { $0 >= anomalyHardFloor }
            return AnomalyFilterResult(
                filtered: filtered,
                anomalyCount: durations.count - filtered.count
            )
        }
        let afterFloor = durations.filter { $0 >= anomalyHardFloor }
        guard afterFloor.count >= 4 else {
            return AnomalyFilterResult(
                filtered: afterFloor,
                anomalyCount: durations.count - afterFloor.count
            )
        }
        let sorted = afterFloor.sorted()
        let count = sorted.count
        let q1 = sorted[count / 4]
        let q3 = sorted[(3 * count) / 4]
        let iqr = q3 - q1
        let lowerBound = q1 - 1.5 * iqr
        let filtered = afterFloor.filter { $0 >= lowerBound }
        return AnomalyFilterResult(
            filtered: filtered,
            anomalyCount: durations.count - filtered.count
        )
    }

    // MARK: - Build Per-Location Stats

    /// Counts and durations respect the time window; last-used and rest time
    /// always look at the full history so long-rested sites aren't hidden.
    private func buildStats(
        for location: Location,
        windowStart: Date?,
        overallMedian: Double?,
        now: Date
    ) -> LocationStats {
        let entries = location.safeEntries
        let totalUses = Self.entries(entries, since: windowStart).count
        let anomalyResult = Self.filterAnomalies(
            Self.completedDurations(of: entries, since: windowStart)
        )
        let filteredDurations = anomalyResult.filtered
        let avg = Self.computeMean(filteredDurations)
        let median = Self.computeMedian(filteredDurations)
        let percentile = filteredDurations.count >= Self.minimumPercentileSampleCount
            ? Self.computePercentile(filteredDurations, Self.durationPercentile)
            : nil
        let minDur = filteredDurations.min()
        let maxDur = filteredDurations.max()
        let lastUsed = entries.map(\.startTime).max()
        let problemCount = Self.entries(entries, since: windowStart).filter { $0.problem != nil }.count

        var daysSince: Int?
        if let lastUsed {
            let calendar = Calendar.current
            daysSince = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastUsed),
                to: calendar.startOfDay(for: now)
            ).day
        }

        let flag = computeAbsorptionFlag(
            locationMedian: median,
            overallMedian: overallMedian
        )

        return LocationStats(
            location: location,
            totalUses: totalUses,
            averageDuration: avg,
            medianDuration: median,
            percentileDuration: percentile,
            minDuration: minDur,
            maxDuration: maxDur,
            lastUsed: lastUsed,
            daysSinceLastUse: daysSince,
            absorptionFlag: flag,
            anomalyCount: anomalyResult.anomalyCount,
            problemCount: problemCount
        )
    }

    private func computeAbsorptionFlag(
        locationMedian: Double?,
        overallMedian: Double?
    ) -> String? {
        guard let locMedian = locationMedian,
              let overall = overallMedian,
              overall > 0 else {
            return nil
        }

        let cutoff = overall * (1.0 - Double(absorptionThreshold) / 100.0)
        guard locMedian < cutoff else { return nil }

        let percentBelow = Int(round((overall - locMedian) / overall * 100))
        return "\(percentBelow)% below your overall median"
    }

    // MARK: - Statistics Helpers

    static func computeMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func computeMedian(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    }

    /// Linearly interpolated percentile (`percentile` in 0...100), matching
    /// `computeMedian` at 50.
    static func computePercentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = min(max(percentile, 0), 100) / 100 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}

// MARK: - Problems

struct ProblemStatItem: Identifiable {
    let problem: SiteProblem
    let count: Int
    /// Share of the summary's `siteCount` that ended with this problem (0...1).
    let rate: Double

    var id: UUID { problem.id }
}

struct ProblemSummary {
    /// Sites that could have had a problem: completed entries, plus any active
    /// entry that already has one recorded.
    let siteCount: Int
    /// Sites with any problem recorded.
    let problemSiteCount: Int
    /// Per-problem counts, most frequent first. Problems never recorded in the window are omitted.
    let items: [ProblemStatItem]

    var anyProblemRate: Double? {
        siteCount > 0 ? Double(problemSiteCount) / Double(siteCount) : nil
    }
}

extension StatisticsViewModel {
    /// Summarizes problems over `entries` (already filtered to the time window).
    /// The active site is skipped unless it already has a problem, since it
    /// hasn't had the chance to end early yet.
    static func summarizeProblems(_ entries: [SiteChangeEntry]) -> ProblemSummary {
        let considered = entries.filter { $0.endTime != nil || $0.problem != nil }
        let withProblem = considered.compactMap(\.problem)

        var counts: [UUID: Int] = [:]
        var problemsByID: [UUID: SiteProblem] = [:]
        for problem in withProblem {
            counts[problem.id, default: 0] += 1
            problemsByID[problem.id] = problem
        }

        let total = considered.count
        let items = problemsByID.values
            .map { problem in
                let count = counts[problem.id] ?? 0
                return ProblemStatItem(
                    problem: problem,
                    count: count,
                    rate: total > 0 ? Double(count) / Double(total) : 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.problem.sortOrder < rhs.problem.sortOrder
            }

        return ProblemSummary(siteCount: total, problemSiteCount: withProblem.count, items: items)
    }
}
