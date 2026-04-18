import Foundation
import Observation
import SwiftData

struct SiteRecommendations {
    let avoid: [Location]
    let recommended: [Location]
    let allSorted: [Location]
}

enum PreviousNoteUpdate {
    case leaveUnchanged
    case replace(String?)
}

@MainActor
@Observable
final class SiteChangeViewModel {
    private let modelContext: ModelContext

    private(set) var recommendations = SiteRecommendations(avoid: [], recommended: [], allSorted: [])
    private(set) var activeSiteEntry: SiteChangeEntry?

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
        activeSiteEntry = SiteChangeEntry.fetchActive(in: modelContext)
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

        // All locations sorted by sortOrder, with left before right within same zone
        let allSorted = locations.sorted { loc1, loc2 in
            if loc1.displayName == loc2.displayName {
                return Self.sideOrder(loc1.side) < Self.sideOrder(loc2.side)
            }
            return loc1.sortOrder < loc2.sortOrder
        }

        return SiteRecommendations(avoid: avoid, recommended: recommended, allSorted: allSorted)
    }

    private static func sideOrder(_ side: String?) -> Int {
        switch side {
        case "left": return 0
        case "right": return 1
        default: return 2
        }
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

    func logSiteChange(
        location: Location,
        note: String?,
        previousNote: PreviousNoteUpdate = .leaveUnchanged
    ) {
        let now = Date()

        // Close the previous active entry
        if let activeEntry = SiteChangeEntry.fetchActive(in: modelContext) {
            activeEntry.endTime = now
            if case .replace(let value) = previousNote {
                activeEntry.note = (value?.isEmpty ?? true) ? nil : value
            }
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
