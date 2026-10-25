import Foundation

struct CSVExporter {

    /// The trailing `problems` column (names joined by `SiteProblem.csvSeparator`)
    /// is only written when some entry has a problem, so exports without
    /// problems still import into app versions that predate the column.
    static func generate(from entries: [SiteChangeEntry]) -> String {
        let includeProblems = entries.contains(where: \.hasProblems)
        let header = includeProblems
            ? "date,location,duration_hours,note,problems\n"
            : "date,location,duration_hours,note\n"
        let sorted = entries.sorted { $0.startTime < $1.startTime }

        let rows = sorted.map { entry -> String in
            let date = formatISO8601(entry.startTime)
            let location = escapeField(
                entry.location?.fullDisplayName ?? ""
            )
            let duration = formatDuration(entry.durationHours)
            let note = escapeField(entry.note ?? "")
            let row = "\(date),\(location),\(duration),\(note)"
            guard includeProblems else { return row }
            let problems = entry.safeProblems.map(\.name).joined(separator: String(SiteProblem.csvSeparator))
            return row + "," + escapeField(problems)
        }

        return header + rows.joined(separator: "\n")
            + (rows.isEmpty ? "" : "\n")
    }

    static func fileName(
        for date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return "sitecycle-export-\(dateString).csv"
    }

    // MARK: - Private Helpers

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime
        ]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func formatDuration(
        _ hours: Double?
    ) -> String {
        guard let hours else { return "" }
        return String(format: "%.1f", hours)
    }

    private static func escapeField(_ value: String) -> String {
        if value.isEmpty { return value }
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        if needsQuoting {
            let escaped = value.replacingOccurrences(
                of: "\"",
                with: "\"\""
            )
            return "\"\(escaped)\""
        }
        return value
    }
}
