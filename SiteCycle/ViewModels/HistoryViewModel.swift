import Foundation
import Observation
import SwiftData

@Observable
final class HistoryViewModel {
    private let modelContext: ModelContext

    var locationFilter: Location?
    var startDate: Date?
    var endDate: Date?

    var filteredEntries: [SiteChangeEntry] {
        var descriptor = FetchDescriptor<SiteChangeEntry>(
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

            return true
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
        try? modelContext.save()
    }

    func clearEndTime(_ entry: SiteChangeEntry) {
        entry.endTime = nil
        try? modelContext.save()
    }
}
