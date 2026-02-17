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
}

struct UsageDistributionItem {
    let locationName: String
    let count: Int
}

@Observable
final class StatisticsViewModel {
    private let modelContext: ModelContext
    let absorptionThreshold: Int

    private(set) var locationStats: [LocationStats] = []
    private(set) var overallAverageDuration: Double?
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

        overallAverageDuration = Self.computeMean(completedDurations)

        locationStats = locations.map { location in
            buildStats(
                for: location,
                overallAverage: overallAverageDuration
            )
        }

        usageDistribution = locations
            .filter { !$0.entries.isEmpty }
            .map { UsageDistributionItem(locationName: $0.fullDisplayName, count: $0.entries.count) }
    }

    private func buildStats(
        for location: Location,
        overallAverage: Double?
    ) -> LocationStats {
        let entries = location.entries
        let completedDurations = entries.compactMap(\.durationHours)
        let totalUses = entries.count
        let avg = Self.computeMean(completedDurations)
        let median = Self.computeMedian(completedDurations)
        let minDur = completedDurations.min()
        let maxDur = completedDurations.max()
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
            locationAvg: avg,
            overallAvg: overallAverage
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
            absorptionFlag: flag
        )
    }

    private func computeAbsorptionFlag(
        locationAvg: Double?,
        overallAvg: Double?
    ) -> String? {
        guard let locAvg = locationAvg,
              let overall = overallAvg,
              overall > 0 else {
            return nil
        }

        let cutoff = overall * (1.0 - Double(absorptionThreshold) / 100.0)
        guard locAvg < cutoff else { return nil }

        let percentBelow = Int(round((overall - locAvg) / overall * 100))
        return "\(percentBelow)% below your overall average"
    }

    func timelineEntries(days: Int) -> [(entry: SiteChangeEntry, locationName: String)] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let descriptor = FetchDescriptor<SiteChangeEntry>(
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime)]
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries
            .filter { $0.startTime >= cutoff }
            .map { ($0, $0.location?.fullDisplayName ?? "Unknown") }
    }

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
