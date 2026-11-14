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
    /// Doesn't save. Returns whether it changed anything.
    @MainActor
    @discardableResult
    static func closeSupersededActiveEntries(in modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<SiteChangeEntry>(
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
        )
        guard let entries = try? modelContext.fetch(descriptor) else { return false }

        var didChange = false
        // The start of the nearest entry that started strictly later.
        var laterStart: Date?
        var currentStart: Date?
        for entry in entries where !entry.isDeleted {
            if entry.startTime != currentStart {
                laterStart = currentStart
                currentStart = entry.startTime
            }
            if entry.endTime == nil, let laterStart {
                entry.endTime = laterStart
                didChange = true
            }
        }
        return didChange
    }
}
