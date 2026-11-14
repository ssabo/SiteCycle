import Foundation
import SwiftData

@Model
final class SiteChangeEntry {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date?
    var note: String?

    var location: Location?
    /// Why the site was changed early, if it was (several can apply, e.g.
    /// painful and leaking). Usually set on the entry being closed. Empty or
    /// nil means no problem was recorded.
    var problems: [SiteProblem]?

    /// Recorded problems in display order.
    var safeProblems: [SiteProblem] {
        (problems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var hasProblems: Bool {
        !(problems ?? []).isEmpty
    }

    var durationHours: Double? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime) / 3600.0
    }

    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        note: String? = nil,
        location: Location? = nil,
        problems: [SiteProblem] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.note = note
        self.location = location
        self.problems = problems
    }

    /// Fetches the most recent entry with no `endTime`, i.e. the currently active site.
    @MainActor
    static func fetchActive(in modelContext: ModelContext) -> SiteChangeEntry? {
        var descriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.endTime == nil },
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Enforces "one active site": closes every open entry that isn't the
    /// newest, at the start of the next entry that started after it. Open
    /// entries can pile up from History edits, CSV import and two devices
    /// logging changes offline (review §2.7).
    ///
    /// The result depends only on synced fields, so every device repairs the
    /// same way. Entries that share a start time close at the same later
    /// start, so identical copies stay identical and entry dedup can still
    /// merge them. Several open entries that share the newest start time are
    /// all left open.
    ///
    /// Reads only the open entries, plus one lookup each, so it stays cheap
    /// on a long history. Doesn't save. Returns whether it changed anything.
    @MainActor
    @discardableResult
    static func closeSupersededActiveEntries(in modelContext: ModelContext) -> Bool {
        let openEntries = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.endTime == nil }
        )
        guard let entries = try? modelContext.fetch(openEntries) else { return false }

        var didChange = false
        for entry in entries where !entry.isDeleted {
            if let laterStart = nextStart(after: entry.startTime, in: modelContext) {
                entry.endTime = laterStart
                didChange = true
            }
        }
        return didChange
    }

    /// The start of the earliest entry that started strictly after `date`.
    @MainActor
    private static func nextStart(after date: Date, in modelContext: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.startTime > date },
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.startTime
    }
}
