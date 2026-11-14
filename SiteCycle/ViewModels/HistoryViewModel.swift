import Foundation
import Observation
import SwiftData

/// History's problem filter: every entry, entries with any problem, or
/// entries with one specific problem.
enum HistoryProblemFilter: Hashable {
    case all
    case anyProblem
    case problem(SiteProblem)

    func matches(_ entry: SiteChangeEntry) -> Bool {
        switch self {
        case .all: return true
        case .anyProblem: return entry.hasProblems
        case .problem(let problem): return (entry.problems ?? []).contains { $0.id == problem.id }
        }
    }

    /// False once the filtered problem no longer exists (e.g. hard-deleted in
    /// Manage Problems), so History can fall back to `.all`.
    func isValid(among problems: [SiteProblem]) -> Bool {
        guard case .problem(let filtered) = self else { return true }
        return !filtered.isDeleted && problems.contains { $0.id == filtered.id }
    }
}

@MainActor
@Observable
final class HistoryViewModel {
    private let modelContext: ModelContext

    var locationFilter: Location?
    var startDate: Date?
    var endDate: Date?
    var problemFilter: HistoryProblemFilter = .all
    /// Bumped when the store changes outside this screen, such as store
    /// maintenance closing an entry after a CloudKit download, so the list
    /// re-fetches.
    private(set) var storeRevision = 0

    var filteredEntries: [SiteChangeEntry] {
        _ = storeRevision
        let descriptor = FetchDescriptor<SiteChangeEntry>(
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
        )

        let entries = (try? modelContext.fetch(descriptor)) ?? []

        return entries.filter { entry in
            if let locationFilter = locationFilter {
                guard entry.location?.id == locationFilter.id else {
                    return false
                }
            }

            if let startDate = startDate {
                guard entry.startTime >= startDate else {
                    return false
                }
            }

            if let endDate = endDate {
                guard entry.startTime <= endDate else {
                    return false
                }
            }

            return problemFilter.matches(entry)
        }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func storeDidChange() {
        storeRevision += 1
    }

    func deleteEntry(_ entry: SiteChangeEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    /// Applies the edits in one save. Returns false, changing nothing, if the
    /// edit would leave the active site behind another entry (see
    /// `keepsActiveSiteNewest`).
    @discardableResult
    func updateEntry(
        _ entry: SiteChangeEntry,
        location: Location?,
        startTime: Date?,
        endTime: Date?,
        note: String?
    ) -> Bool {
        let isActive = endTime == nil && entry.endTime == nil
        guard keepsActiveSiteNewest(entry, startTime: startTime ?? entry.startTime, isActive: isActive) else {
            return false
        }
        apply(to: entry, location: location, startTime: startTime, note: note)
        if let endTime = endTime {
            entry.endTime = endTime
        }
        try? modelContext.save()
        return true
    }

    /// Replaces why the site was changed early; an empty array clears it.
    func setProblems(_ entry: SiteChangeEntry, problems: [SiteProblem]) {
        let current = Set(entry.safeProblems.map(\.id))
        guard current != Set(problems.map(\.id)) else { return }
        entry.problems = problems
        try? modelContext.save()
    }

    /// "One active site": only the newest entry may be open (review §2.7).
    /// Says whether saving `entry` with this start time, active or not, keeps
    /// that true:
    /// - an active entry may not start before any other entry;
    /// - a closed entry may not start after an open one.
    func keepsActiveSiteNewest(_ entry: SiteChangeEntry, startTime: Date, isActive: Bool) -> Bool {
        let entryID = entry.id
        let conflicts: Predicate<SiteChangeEntry>
        if isActive {
            conflicts = #Predicate<SiteChangeEntry> { $0.id != entryID && $0.startTime > startTime }
        } else {
            conflicts = #Predicate<SiteChangeEntry> {
                $0.id != entryID && $0.endTime == nil && $0.startTime < startTime
            }
        }
        let descriptor = FetchDescriptor<SiteChangeEntry>(predicate: conflicts)
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) == 0
    }

    /// Whether the entry, at its current start time, can be made active again.
    func canClearEndTime(_ entry: SiteChangeEntry) -> Bool {
        keepsActiveSiteNewest(entry, startTime: entry.startTime, isActive: true)
    }

    /// Makes the entry active again, with any other edits, in one save, and
    /// closes any older open entry. Returns false, changing nothing, if the
    /// entry wouldn't be the newest.
    @discardableResult
    func reopen(
        _ entry: SiteChangeEntry,
        location: Location? = nil,
        startTime: Date? = nil,
        note: String? = nil
    ) -> Bool {
        guard keepsActiveSiteNewest(entry, startTime: startTime ?? entry.startTime, isActive: true) else {
            return false
        }
        apply(to: entry, location: location, startTime: startTime, note: note)
        entry.endTime = nil
        SiteChangeEntry.closeSupersededActiveEntries(in: modelContext)
        try? modelContext.save()
        return true
    }

    func clearEndTime(_ entry: SiteChangeEntry) {
        reopen(entry)
    }

    /// Sets each non-nil value.
    private func apply(to entry: SiteChangeEntry, location: Location?, startTime: Date?, note: String?) {
        if let location = location {
            entry.location = location
        }
        if let startTime = startTime {
            entry.startTime = startTime
        }
        if let note = note {
            entry.note = note
        }
    }
}
