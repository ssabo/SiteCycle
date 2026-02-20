import Foundation
import Observation
import SwiftData

struct LocationStats {
    let location: Location
    let totalUses: Int
    let averageDuration: Double?
    let medianDuration: Double?
    let minDuration: Double?
    let maxDuration: Double?
    let lastUsed: Date?
    let daysSinceLastUse: Int?
    let absorptionFlag: String?
    let anomalyCount: Int
}

struct UsageDistributionItem {
    let locationName: String
    let count: Int
}

@MainActor
@Observable
final class StatisticsViewModel {
    private let modelContext: ModelContext
    let absorptionThreshold: Int

    private(set) var locationStats: [LocationStats] = []
    private(set) var overallMedianDuration: Double?
    private(set) var usageDistribution: [UsageDistributionItem] = []

    init(modelContext: ModelContext, absorptionThreshold: Int = 20) {
        self.modelContext = modelContext
        self.absorptionThreshold = absorptionThreshold
    }

    func refresh() {
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate<Location> { $0.isEnabled == true },
            sortBy: [SortDescriptor(\Location.sortOrder)]
        )
        let locations = (try? modelContext.fetch(descriptor)) ?? []

        let allEntries = locations.flatMap(\.entries)
        let completedDurations = allEntries.compactMap(\.durationHours)
        let overallResult = Self.filterAnomalies(completedDurations)
        overallMedianDuration = Self.computeMedian(overallResult.filtered)

        locationStats = locations.map { location in
            buildStats(
                for: location,
                overallMedian: overallMedianDuration
            )
        }

        usageDistribution = locations
            .filter { !$0.entries.isEmpty }
            .map { UsageDistributionItem(locationName: $0.fullDisplayName, count: $0.entries.count) }
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

    private func buildStats(
        for location: Location,
        overallMedian: Double?
    ) -> LocationStats {
        let entries = location.entries
        let completedDurations = entries.compactMap(\.durationHours)
        let totalUses = entries.count
        let anomalyResult = Self.filterAnomalies(completedDurations)
        let filteredDurations = anomalyResult.filtered
        let avg = Self.computeMean(filteredDurations)
        let median = Self.computeMedian(filteredDurations)
        let minDur = filteredDurations.min()
        let maxDur = filteredDurations.max()
        let lastUsed = entries.map(\.startTime).max()

        var daysSince: Int?
        if let lastUsed {
            let calendar = Calendar.current
            daysSince = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastUsed),
                to: calendar.startOfDay(for: Date())
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
            minDuration: minDur,
            maxDuration: maxDur,
            lastUsed: lastUsed,
            daysSinceLastUse: daysSince,
            absorptionFlag: flag,
            anomalyCount: anomalyResult.anomalyCount
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
}
