import WidgetKit
import SwiftUI
import SwiftData

struct SiteCycleEntry: TimelineEntry {
    let date: Date
    let locationName: String?
    let startTime: Date?
    let targetHours: Double
}

struct SiteCycleTimelineProvider: TimelineProvider {
    let modelContainer: ModelContainer?

    init() {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.sitecycle.app"
        )
        let storeURL = appGroupURL?.appendingPathComponent("SiteCycle.store")

        if let storeURL {
            let config = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            modelContainer = try? ModelContainer(
                for: schema,
                configurations: [config]
            )
        } else {
            modelContainer = nil
        }
    }

    func placeholder(in context: Context) -> SiteCycleEntry {
        SiteCycleEntry(
            date: .now,
            locationName: "L Abdomen (Front)",
            startTime: .now.addingTimeInterval(-7200),
            targetHours: 72
        )
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SiteCycleEntry) -> Void) {
        let entry = MainActor.assumeIsolated { fetchCurrentEntry() }
        completion(entry)
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<SiteCycleEntry>) -> Void
    ) {
        let current = MainActor.assumeIsolated { fetchCurrentEntry() }
        var entries = [current]

        for offset in stride(from: 15, through: 120, by: 15) {
            let futureDate = Date.now.addingTimeInterval(Double(offset) * 60)
            entries.append(SiteCycleEntry(
                date: futureDate,
                locationName: current.locationName,
                startTime: current.startTime,
                targetHours: current.targetHours
            ))
        }

        let refreshDate = Date.now.addingTimeInterval(2 * 3600)
        completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }

    @MainActor
    private func fetchCurrentEntry() -> SiteCycleEntry {
        guard let container = modelContainer else {
            return SiteCycleEntry(
                date: .now,
                locationName: nil,
                startTime: nil,
                targetHours: 72
            )
        }
        let context = container.mainContext
        var descriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.endTime == nil },
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let active = try? context.fetch(descriptor).first
        let targetHours = Double(
            UserDefaults.standard.integer(forKey: "targetDurationHours")
        )

        return SiteCycleEntry(
            date: .now,
            locationName: active?.location?.fullDisplayName,
            startTime: active?.startTime,
            targetHours: targetHours > 0 ? targetHours : 72
        )
    }
}

// MARK: - Widget Views

struct AccessoryRectangularView: View {
    let entry: SiteCycleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.locationName ?? "No Active Site")
                .font(.headline)
                .lineLimit(1)
            if let startTime = entry.startTime {
                Text(elapsedText(from: startTime, to: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func elapsedText(from start: Date, to now: Date) -> String {
        let hours = now.timeIntervalSince(start) / 3600
        return String(format: "%.1fh elapsed", hours)
    }
}

struct AccessoryCircularView: View {
    let entry: SiteCycleEntry

    var body: some View {
        if let startTime = entry.startTime {
            let hours = entry.date.timeIntervalSince(startTime) / 3600
            let fraction = min(hours / entry.targetHours, 1.0)
            let color = progressColor(for: fraction)

            ZStack {
                AccessoryWidgetBackground()
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                Text(abbreviatedTime(hours))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "cross.circle")
                    .font(.title3)
            }
        }
    }

    private func abbreviatedTime(_ hours: Double) -> String {
        if hours < 1 {
            return "\(Int(hours * 60))m"
        }
        return String(format: "%.0fh", hours)
    }

    private func progressColor(for fraction: Double) -> Color {
        if fraction < 0.8 { return .green }
        if fraction <= 1.0 { return .yellow }
        return .red
    }
}

struct AccessoryInlineView: View {
    let entry: SiteCycleEntry

    var body: some View {
        if let locationName = entry.locationName, let startTime = entry.startTime {
            let hours = entry.date.timeIntervalSince(startTime) / 3600
            Text("\(locationName) \u{00B7} \(formattedTime(hours))")
        } else {
            Text("No Active Site")
        }
    }

    private func formattedTime(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60
        return "\(hrs)h \(mins)m"
    }
}

// MARK: - Widget

@main
struct SiteCycleWatchWidgets: WidgetBundle {
    var body: some Widget {
        SiteCycleComplication()
    }
}

struct SiteCycleComplication: Widget {
    let kind = "SiteCycleComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SiteCycleTimelineProvider()
        ) { entry in
            AccessoryRectangularView(entry: entry)
        }
        .configurationDisplayName("Site Status")
        .description("Shows your current infusion site and elapsed time.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
    }
}
