import Foundation
import Observation
import SwiftData

struct SiteRecommendations {
    let avoid: [Location]
    let recommended: [Location]
    let allSorted: [Location]
}

/// How the "Recommended" list is computed. Stored in UserDefaults as a raw string.
enum RecommendationStrategy: String, CaseIterable, Identifiable {
    /// 3 least recently used individual sites.
    case bySite
    /// 3 least recently used body-part groups (bodyPart + side); the least
    /// recently used site within each group is recommended.
    case byBodyPart

    static let storageKey = "recommendationStrategy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bySite: return "By Site"
        case .byBodyPart: return "By Body Part"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> RecommendationStrategy {
        guard let raw = defaults.string(forKey: storageKey),
              let strategy = RecommendationStrategy(rawValue: raw) else {
            return .bySite
        }
        return strategy
    }
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
        recommendations = Self.computeRecommendations(
            locations: locations,
            strategy: RecommendationStrategy.load()
        )
        activeSiteEntry = SiteChangeEntry.fetchActive(in: modelContext)
    }

    /// Sorts locations by most-recent-use descending, then splits into avoid/recommended lists.
    static func computeRecommendations(
        locations: [Location],
        strategy: RecommendationStrategy = .bySite
    ) -> SiteRecommendations {
        let sorted = sortedByRecencyDescending(locations)

        // Avoid: up to 3 most recently used (only those with history) — site-based in both modes
        let usedLocations = sorted.filter { !$0.safeEntries.isEmpty }
        let avoid = Array(usedLocations.prefix(3))
        let avoidIds = Set(avoid.map(\.id))

        let recommended: [Location]
        switch strategy {
        case .bySite:
            // Up to 3 least recently used / never-used sites, excluding avoid
            let candidates = sorted.filter { !avoidIds.contains($0.id) }
            recommended = Array(candidates.suffix(3).reversed())
        case .byBodyPart:
            recommended = byBodyPartRecommended(locations: locations, avoidIds: avoidIds)
        }

        // All locations sorted by sortOrder, with left before right within same zone
        let allSorted = locations.sorted { loc1, loc2 in
            if loc1.displayName == loc2.displayName {
                return Self.sideOrder(loc1.side) < Self.sideOrder(loc2.side)
            }
            return loc1.sortOrder < loc2.sortOrder
        }

        return SiteRecommendations(avoid: avoid, recommended: recommended, allSorted: allSorted)
    }

    private static func sortedByRecencyDescending(_ locations: [Location]) -> [Location] {
        locations.sorted { loc1, loc2 in
            switch (lastUsed(loc1), lastUsed(loc2)) {
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
    }

    private struct BodyPartGroupKey: Hashable {
        let bodyPart: String
        let side: String?
    }

    private static func lastUsed(_ location: Location) -> Date? {
        location.safeEntries.map(\.startTime).max()
    }

    /// Groups by (bodyPart, side), ranks groups least-recently-used first (group recency =
    /// most recent use across its sites; never-used groups sort oldest), then recommends the
    /// least recently used site within each of the stalest groups.
    private static func byBodyPartRecommended(
        locations: [Location],
        avoidIds: Set<UUID>
    ) -> [Location] {
        let groups = Dictionary(grouping: locations) {
            BodyPartGroupKey(bodyPart: $0.bodyPart, side: $0.side)
        }
        let ranked = groups.values.sorted { lhs, rhs in
            let lhsDate = lhs.compactMap(Self.lastUsed).max()
            let rhsDate = rhs.compactMap(Self.lastUsed).max()
            switch (lhsDate, rhsDate) {
            case (.some(let d1), .some(let d2)) where d1 != d2:
                return d1 < d2
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            default:
                return (lhs.map(\.sortOrder).min() ?? 0) < (rhs.map(\.sortOrder).min() ?? 0)
            }
        }

        var result: [Location] = []
        for group in ranked where result.count < 3 {
            if let pick = leastRecentlyUsedSite(in: group, excluding: avoidIds) {
                result.append(pick)
            }
        }
        return result
    }

    /// The least recently used site in a group: never-used first, then oldest last use;
    /// ties broken by lowest sortOrder. Avoid-listed sites are never picked.
    private static func leastRecentlyUsedSite(
        in group: [Location],
        excluding avoidIds: Set<UUID>
    ) -> Location? {
        group.filter { !avoidIds.contains($0.id) }
            .min { lhs, rhs in
                switch (lastUsed(lhs), lastUsed(rhs)) {
                case (.some(let d1), .some(let d2)) where d1 != d2:
                    return d1 < d2
                case (.none, .some):
                    return true
                case (.some, .none):
                    return false
                default:
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
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
