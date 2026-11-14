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

    var filteredEntries: [SiteChangeEntry] {
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

    func deleteEntry(_ entry: SiteChangeEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    func updateEntry(
        _ entry: SiteChangeEntry,
        location: Location?,
        startTime: Date?,
        endTime: Date?,
        note: String?
    ) {
        if let location = location {
            entry.location = location
        }
        if let startTime = startTime {
            entry.startTime = startTime
        }
        if let endTime = endTime {
            entry.endTime = endTime
        }
        if let note = note {
            entry.note = note
        }
        // A new start time can put an open entry behind another one.
        SiteChangeEntry.closeSupersededActiveEntries(in: modelContext)
        try? modelContext.save()
    }

    /// Replaces why the site was changed early; an empty array clears it.
    func setProblems(_ entry: SiteChangeEntry, problems: [SiteProblem]) {
        let current = Set(entry.safeProblems.map(\.id))
        guard current != Set(problems.map(\.id)) else { return }
        entry.problems = problems
        try? modelContext.save()
    }

    /// Only the newest entry can be made active again: reopening an older one
    /// would leave two active sites (review §2.7).
    func canClearEndTime(_ entry: SiteChangeEntry) -> Bool {
        let start = entry.startTime
        let descriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.startTime > start }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) == 0
    }

    /// Makes the newest entry active again, and closes any older open entry.
    /// Does nothing for an entry that isn't the newest.
    func clearEndTime(_ entry: SiteChangeEntry) {
        guard canClearEndTime(entry) else { return }
        entry.endTime = nil
        SiteChangeEntry.closeSupersededActiveEntries(in: modelContext)
        try? modelContext.save()
    }
}
