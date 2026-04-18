import Foundation
import SwiftData

@Model
final class SiteChangeEntry {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date?
    var note: String?

    var location: Location?

    var durationHours: Double? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime) / 3600.0
    }

    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        note: String? = nil,
        location: Location? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.note = note
        self.location = location
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
}
