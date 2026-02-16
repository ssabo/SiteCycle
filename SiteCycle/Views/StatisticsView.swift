import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("absorptionAlertThreshold") private var absorptionThreshold: Int = 20
    @State private var viewModel: StatisticsViewModel?
    @State private var timelineDays: Int = 30

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
            timelineSection(vm)
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
                    Text("Average Duration")
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
                Text(stat.location.displayName)
                    .font(.headline)
                Spacer()
                Text("\(stat.totalUses) uses")
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
                }
            }
        }
    }
}

// MARK: - Timeline Section

private extension StatisticsView {
    func timelineSection(_ vm: StatisticsViewModel) -> some View {
        Section("Rotation Timeline") {
            Picker("Period", selection: $timelineDays) {
                Text("30 Days").tag(30)
                Text("60 Days").tag(60)
                Text("90 Days").tag(90)
            }
            .pickerStyle(.segmented)

            let entries = vm.timelineEntries(days: timelineDays)
            if entries.isEmpty {
                Text("No site changes in this period.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                timelineChart(entries)
            }
        }
    }

    func timelineChart(
        _ entries: [(entry: SiteChangeEntry, locationName: String)]
    ) -> some View {
        Chart(entries, id: \.entry.id) { item in
            let end = item.entry.endTime ?? Date()
            RectangleMark(
                xStart: .value("Start", item.entry.startTime),
                xEnd: .value("End", end),
                y: .value("Location", item.locationName)
            )
            .foregroundStyle(by: .value("Location", item.locationName))
        }
        .chartLegend(.hidden)
        .frame(height: 200)
    }
}

// MARK: - Helpers

private extension StatisticsView {
    struct MetricItem: Hashable {
        let label: String
        let value: String
    }

    func buildMetrics(_ stat: LocationStats) -> [MetricItem] {
        var items: [MetricItem] = []
        if let avg = stat.averageDuration {
            items.append(MetricItem(label: "Avg:", value: formatHours(avg)))
        }
        if let median = stat.medianDuration {
            items.append(MetricItem(label: "Median:", value: formatHours(median)))
        }
        if let min = stat.minDuration {
            items.append(MetricItem(label: "Min:", value: formatHours(min)))
        }
        if let max = stat.maxDuration {
            items.append(MetricItem(label: "Max:", value: formatHours(max)))
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
