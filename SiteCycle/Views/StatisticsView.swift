import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("absorptionAlertThreshold") private var absorptionThreshold: Int = 20
    @State private var viewModel: StatisticsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.locationStats.isEmpty {
                    emptyState
                } else {
                    statisticsContent(viewModel)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Statistics")
        .onAppear {
            if viewModel == nil {
                let vm = StatisticsViewModel(
                    modelContext: modelContext,
                    absorptionThreshold: absorptionThreshold
                )
                vm.refresh()
                viewModel = vm
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Statistics Yet",
            systemImage: "chart.bar",
            description: Text("Log site changes to see usage statistics and insights.")
        )
    }

    private func statisticsContent(_ vm: StatisticsViewModel) -> some View {
        List {
            if !vm.usageDistribution.isEmpty {
                usageChartSection(vm.usageDistribution)
            }
            overallSection(vm)
            perLocationSection(vm.locationStats)
            siteRestSection(vm.locationStats)
        }
    }
}

// MARK: - Usage Distribution Chart

private extension StatisticsView {
    func usageChartSection(_ distribution: [UsageDistributionItem]) -> some View {
        Section("Usage Distribution") {
            Chart(distribution, id: \.locationName) { item in
                BarMark(
                    x: .value("Uses", item.count),
                    y: .value("Location", item.locationName)
                )
                .foregroundStyle(.tint)
            }
            .frame(height: max(CGFloat(distribution.count) * 32, 120))
        }
    }
}

// MARK: - Overall Section

private extension StatisticsView {
    func overallSection(_ vm: StatisticsViewModel) -> some View {
        Section("Overall") {
            if let avg = vm.overallAverageDuration {
                HStack {
                    Text("Median Duration")
                    Spacer()
                    Text(formatHours(avg))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Locations Tracked")
                Spacer()
                Text("\(vm.locationStats.count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Total Site Changes")
                Spacer()
                let total = vm.locationStats.reduce(0) { $0 + $1.totalUses }
                Text("\(total)")
                    .foregroundStyle(.secondary)
            }
            let totalAnomalies = vm.locationStats.reduce(0) { $0 + $1.anomalyCount }
            if totalAnomalies > 0 {
                HStack {
                    Text("Anomalies excluded")
                    Spacer()
                    Text("\(totalAnomalies)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Per-Location Stats

private extension StatisticsView {
    func perLocationSection(_ stats: [LocationStats]) -> some View {
        Section("Per-Location Statistics") {
            ForEach(stats, id: \.location.id) { stat in
                locationStatsRow(stat)
            }
        }
    }

    func locationStatsRow(_ stat: LocationStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LocationLabelView(location: stat.location, font: .headline)
                Spacer()
                let subtitle = stat.anomalyCount > 0
                    ? "\(stat.totalUses) uses · \(stat.anomalyCount) skipped"
                    : "\(stat.totalUses) uses"
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let flag = stat.absorptionFlag {
                Label(flag, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if stat.totalUses > 0 {
                locationMetricsGrid(stat)
            }
        }
        .padding(.vertical, 4)
    }

    func locationMetricsGrid(_ stat: LocationStats) -> some View {
        let metrics = buildMetrics(stat)
        return LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(metrics, id: \.label) { metric in
                HStack(spacing: 4) {
                    Text(metric.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.caption)
                        .foregroundStyle(metric.isMuted ? .secondary : .primary)
                }
            }
        }
    }
}

// MARK: - Site Rest Time Chart

private extension StatisticsView {
    func siteRestSection(_ stats: [LocationStats]) -> some View {
        let items = stats
            .compactMap { stat -> SiteRestItem? in
                guard let days = stat.daysSinceLastUse else { return nil }
                return SiteRestItem(
                    locationName: stat.location.fullDisplayName,
                    days: days
                )
            }
            .sorted { $0.days > $1.days }

        return Section("Site Rest Time") {
            if items.isEmpty {
                Text("No location data available.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                Chart(items, id: \.locationName) { item in
                    BarMark(
                        x: .value("Days", item.days),
                        y: .value("Location", item.locationName)
                    )
                    .foregroundStyle(restColor(days: item.days))
                }
                .frame(height: max(CGFloat(items.count) * 32, 120))
            }
        }
    }

    func restColor(days: Int) -> Color {
        if days >= 14 { return .green }
        if days >= 7 { return .orange }
        return .red
    }
}

// MARK: - Helpers

private extension StatisticsView {
    struct MetricItem: Hashable {
        let label: String
        let value: String
        var isMuted: Bool = false
    }

    struct SiteRestItem {
        let locationName: String
        let days: Int
    }

    func buildMetrics(_ stat: LocationStats) -> [MetricItem] {
        var items: [MetricItem] = []
        if let median = stat.medianDuration {
            items.append(MetricItem(label: "Median:", value: formatHours(median)))
        }
        if let lastUsed = stat.lastUsed {
            items.append(MetricItem(
                label: "Last used:",
                value: lastUsed.formatted(date: .abbreviated, time: .omitted)
            ))
        }
        if let days = stat.daysSinceLastUse {
            items.append(MetricItem(label: "Days since:", value: "\(days)"))
        }
        if stat.anomalyCount > 0 {
            items.append(MetricItem(
                label: "Skipped:",
                value: "\(stat.anomalyCount)",
                isMuted: true
            ))
        }
        return items
    }

    func formatHours(_ hours: Double) -> String {
        String(format: "%.1fh", hours)
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
    }
    .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
