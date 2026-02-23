import Foundation
import Observation
import SwiftData

struct SiteRecommendations {
    let avoid: [Location]
    let recommended: [Location]
    let allSorted: [Location]
}

enum LocationCategory {
    case avoid
    case recommended
    case neutral
}

@MainActor
@Observable
final class SiteChangeViewModel {
    private let modelContext: ModelContext

    private(set) var recommendations = SiteRecommendations(avoid: [], recommended: [], allSorted: [])

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    func refresh() {
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate<Location> { $0.isEnabled == true },
            sortBy: [SortDescriptor(\Location.sortOrder)]
        )
        let locations = (try? modelContext.fetch(descriptor)) ?? []
        recommendations = Self.computeRecommendations(locations: locations)
    }

    /// Sorts locations by most-recent-use descending, then splits into avoid/recommended lists.
    static func computeRecommendations(locations: [Location]) -> SiteRecommendations {
        let sorted = locations.sorted { loc1, loc2 in
            let date1 = loc1.safeEntries.map(\.startTime).max()
            let date2 = loc2.safeEntries.map(\.startTime).max()

            switch (date1, date2) {
            case (.some(let d1), .some(let d2)):
                return d1 > d2
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return false
            }
        }

        // Avoid: up to 3 most recently used (only those with history)
        let usedLocations = sorted.filter { !$0.safeEntries.isEmpty }
        let avoid = Array(usedLocations.prefix(3))

        // Recommended: up to 3 least recently used / never-used, excluding avoid
        let avoidIds = Set(avoid.map(\.id))
        let candidates = sorted.filter { !avoidIds.contains($0.id) }
        let recommended = Array(candidates.suffix(3).reversed())

        // All locations sorted by sortOrder
        let allSorted = locations.sorted { $0.sortOrder < $1.sortOrder }

        return SiteRecommendations(avoid: avoid, recommended: recommended, allSorted: allSorted)
    }

    func category(for location: Location) -> LocationCategory {
        if recommendations.avoid.contains(where: { $0.id == location.id }) {
            return .avoid
        }
        if recommendations.recommended.contains(where: { $0.id == location.id }) {
            return .recommended
        }
        return .neutral
    }

    func lastUsedDate(for location: Location) -> Date? {
        location.safeEntries.map(\.startTime).max()
    }

    func logSiteChange(location: Location, note: String?) {
        let now = Date()

        // Close the previous active entry
        var activeDescriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.endTime == nil },
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
        )
        activeDescriptor.fetchLimit = 1
        if let activeEntry = try? modelContext.fetch(activeDescriptor).first {
            activeEntry.endTime = now
        }

        // Create the new entry
        let newEntry = SiteChangeEntry(
            startTime: now,
            note: (note?.isEmpty ?? true) ? nil : note,
            location: location
        )
        modelContext.insert(newEntry)

        try? modelContext.save()
    }
}
