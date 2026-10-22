import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HomeViewModel {
    private let modelContext: ModelContext

    private(set) var activeSiteEntry: SiteChangeEntry?

    var targetDurationHours: Double
    var quickStatWindow: StatsTimeWindow

    /// Duration summary for the Home badge, over `quickStatWindow`.
    private(set) var quickStat: DurationSummary?

    var currentLocation: Location? { activeSiteEntry?.location }
    var startTime: Date? { activeSiteEntry?.startTime }
    var hasActiveSite: Bool { activeSiteEntry != nil }

    init(
        modelContext: ModelContext,
        targetDurationHours: Double = 72,
        quickStatWindow: StatsTimeWindow = StatsTimeWindow.defaultHomeStatWindow
    ) {
        self.modelContext = modelContext
        self.targetDurationHours = targetDurationHours
        self.quickStatWindow = quickStatWindow
        refreshActiveSite()
    }

    /// Reloads the active site and the quick stat, since both change whenever
    /// a site change is logged or history is edited.
    func refreshActiveSite() {
        activeSiteEntry = SiteChangeEntry.fetchActive(in: modelContext)
        refreshQuickStat()
    }

    /// Uses the same inputs as the Statistics tab (enabled locations, anomaly
    /// filtering, active site skipped) so the numbers match.
    func refreshQuickStat(now: Date = Date()) {
        let entries = StatisticsViewModel.fetchEnabledLocations(in: modelContext).flatMap(\.safeEntries)
        let windowStart = quickStatWindow.startDate(relativeTo: now)
        quickStat = StatisticsViewModel.summarize(
            StatisticsViewModel.completedDurations(of: entries, since: windowStart)
        )
    }

    func elapsedHours(at now: Date = Date()) -> Double {
        guard let startTime = startTime else { return 0 }
        return now.timeIntervalSince(startTime) / 3600.0
    }

    func progressFraction(at now: Date = Date()) -> Double {
        guard hasActiveSite else { return 0 }
        return elapsedHours(at: now) / targetDurationHours
    }
}
