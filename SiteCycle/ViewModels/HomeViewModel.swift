import Foundation
import Observation
import SwiftData

@Observable
final class HomeViewModel {
    private let modelContext: ModelContext

    private(set) var activeSiteEntry: SiteChangeEntry?

    var targetDurationHours: Double

    var currentLocation: Location? { activeSiteEntry?.location }
    var startTime: Date? { activeSiteEntry?.startTime }
    var hasActiveSite: Bool { activeSiteEntry != nil }

    init(modelContext: ModelContext, targetDurationHours: Double = 72) {
        self.modelContext = modelContext
        self.targetDurationHours = targetDurationHours
        refreshActiveSite()
    }

    func refreshActiveSite() {
        var descriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.endTime == nil },
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        activeSiteEntry = try? modelContext.fetch(descriptor).first
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
