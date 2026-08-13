import WidgetKit
import SwiftUI

struct SiteCycleEntry: TimelineEntry {
    let date: Date
    let locationName: String?
    let startTime: Date?
    let targetHours: Double
}

struct SiteCycleTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SiteCycleEntry {
        SiteCycleEntry(
            date: .now,
            locationName: "L Abdomen (Front)",
            startTime: .now.addingTimeInterval(-7200),
            targetHours: 72
        )
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SiteCycleEntry) -> Void) {
        completion(fetchCurrentEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<SiteCycleEntry>) -> Void
    ) {
        let current = fetchCurrentEntry()
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

    private func fetchCurrentEntry() -> SiteCycleEntry {
        guard let defaults = UserDefaults(suiteName: WatchConnectivityConstants.appGroupIdentifier),
              let data = defaults.data(forKey: WatchConnectivityConstants.stateKey),
              let state = WatchAppState.decode(from: data) else {
            return SiteCycleEntry(
                date: .now,
                locationName: nil,
                startTime: nil,
                targetHours: 72
            )
        }

        return SiteCycleEntry(
            date: .now,
            locationName: state.activeSite?.locationName,
            startTime: state.activeSite?.startTime,
            targetHours: state.targetDurationHours
        )
    }
}

// MARK: - Helpers

private func progressColor(for fraction: Double) -> Color {
    if fraction < 0.8 { return .green }
    if fraction <= 1.0 { return .yellow }
    return .red
}

private func formattedHours(_ hours: Double) -> String {
    String(format: "%.1f", hours)
}

private func abbreviatedHours(_ hours: Double) -> String {
    if hours < 1 {
        return "\(Int(hours * 60))m"
    }
    return String(format: "%.0fh", hours)
}

// MARK: - Widget Views

struct SystemSmallRingView: View {
    let entry: SiteCycleEntry

    var body: some View {
        if let startTime = entry.startTime {
            let hours = entry.date.timeIntervalSince(startTime) / 3600
            let fraction = hours / entry.targetHours
            let trimmed = min(fraction, 1.0)
            let color = progressColor(for: fraction)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(trimmed))
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(formattedHours(hours))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("hours")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "cross.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No Active Site")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AccessoryCircularRingView: View {
    let entry: SiteCycleEntry

    var body: some View {
        if let startTime = entry.startTime {
            let hours = entry.date.timeIntervalSince(startTime) / 3600
            let fraction = hours / entry.targetHours
            let trimmed = min(fraction, 1.0)
            let color = progressColor(for: fraction)

            ZStack {
                AccessoryWidgetBackground()
                Circle()
                    .trim(from: 0, to: CGFloat(trimmed))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                Text(abbreviatedHours(hours))
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
}

// MARK: - Widget

struct SiteCycleRingWidget: Widget {
    let kind = "SiteCycleRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SiteCycleTimelineProvider()
        ) { entry in
            SiteCycleRingEntryView(entry: entry)
        }
        .configurationDisplayName("Site Status")
        .description("Shows the current infusion site duration ring.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct SiteCycleRingEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SiteCycleEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularRingView(entry: entry)
                .containerBackground(.clear, for: .widget)
        default:
            SystemSmallRingView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

@main
struct SiteCycleWidgets: WidgetBundle {
    var body: some Widget {
        SiteCycleRingWidget()
    }
}
