import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PhoneConnectivityManager.self) private var connectivityManager
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72
    @AppStorage(EarlyChange.thresholdPercentKey)
    private var earlyChangeThresholdPercent: Int = EarlyChange.defaultThresholdPercent
    @AppStorage("absorptionAlertThreshold") private var absorptionAlertThreshold: Int = 20
    @AppStorage(RecommendationStrategy.storageKey)
    private var recommendationStrategyRaw: String = RecommendationStrategy.bySite.rawValue
    @AppStorage(RecommendationStrategy.cooldownCountKey)
    private var bodyPartCooldownCount: Int = RecommendationStrategy.defaultCooldownCount
    @AppStorage(HomeStatMetric.storageKey)
    private var homeStatMetricRaw: String = HomeStatMetric.median.rawValue
    @AppStorage(StatsTimeWindow.homeStatStorageKey)
    private var homeStatWindowRaw: String = StatsTimeWindow.defaultHomeStatWindow.rawValue
    @AppStorage(WatchConnectivityConstants.showAllLocationsKey)
    private var watchShowAllLocations: Bool = true
    @State private var csvFileURL: URL?
    @State private var showingShareSheet = false
    @State private var importFlow = CSVImportViewModel(origin: .settings)

    var body: some View {
        Form { formSections }
            .navigationTitle("Settings")
            .onChange(of: targetDurationHours) {
                connectivityManager.pushCurrentState()
            }
            .onChange(of: recommendationStrategyRaw) {
                connectivityManager.pushCurrentState()
            }
            .onChange(of: bodyPartCooldownCount) {
                connectivityManager.pushCurrentState()
            }
            .onChange(of: watchShowAllLocations) {
                connectivityManager.pushCurrentState()
            }
            .background(
                Group {
                    if showingShareSheet, let csvFileURL {
                        ActivityPresenter(url: csvFileURL, isPresented: $showingShareSheet)
                    }
                }
            )
            .csvImportFlow(importFlow) {
                connectivityManager.pushCurrentState()
            }
    }

    @ViewBuilder private var formSections: some View {
        Section("Site Management") {
            NavigationLink {
                LocationConfigView()
            } label: {
                Label("Manage Locations", systemImage: "mappin.and.ellipse")
            }
            .accessibilityIdentifier("settings.manageLocations")

            NavigationLink {
                ProblemConfigView()
            } label: {
                Label("Manage Problems", systemImage: "bandage")
            }
            .accessibilityIdentifier("settings.manageProblems")
        }

        Section("Preferences") {
            Stepper(value: $targetDurationHours, in: 12...168, step: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Duration")
                    Text("\(targetDurationHours) hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.targetDuration.value")
                }
            }
            .accessibilityIdentifier("settings.targetDurationStepper")

            Stepper(
                value: $earlyChangeThresholdPercent,
                in: EarlyChange.thresholdPercentRange,
                step: EarlyChange.thresholdPercentStep
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Early Change Threshold")
                    Text("Under \(earlyChangeThresholdPercent)% of target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.earlyChangeThreshold.value")
                }
            }
            .accessibilityIdentifier("settings.earlyChangeThresholdStepper")

            Stepper(value: $absorptionAlertThreshold, in: 5...50, step: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Absorption Alert Threshold")
                    Text("\(absorptionAlertThreshold)% below average")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.absorptionThreshold.value")
                }
            }
            .accessibilityIdentifier("settings.absorptionThresholdStepper")

            Picker(selection: $recommendationStrategyRaw) {
                ForEach(RecommendationStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy.rawValue)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommendation Mode")
                    Text(recommendationModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.recommendationMode.value")
                }
            }
            .accessibilityIdentifier("settings.recommendationModePicker")

            if selectedStrategy == .byBodyPartCooldown {
                Stepper(value: $bodyPartCooldownCount, in: RecommendationStrategy.cooldownCountRange) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cooldown Window")
                        Text("Last \(bodyPartCooldownCount) site \(bodyPartCooldownCount == 1 ? "change" : "changes")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.cooldownWindow.value")
                    }
                }
                .accessibilityIdentifier("settings.cooldownWindowStepper")
            }
        }

        homeStatSection

        Section {
            Toggle("Show All Locations", isOn: $watchShowAllLocations)
                .accessibilityIdentifier("settings.watchShowAllLocationsToggle")
        } header: {
            Text("Watch Settings")
        } footer: {
            Text("When off, the watch site picker shows only the recommended locations.")
        }

        Section("Data") {
            Button {
                exportCSV()
            } label: {
                Label("Export Data as CSV", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                importFlow.start(context: modelContext)
            } label: {
                Label("Import Data from CSV", systemImage: "square.and.arrow.down")
            }
        }

        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var homeStatSection: some View {
        Section {
            Picker("Stat", selection: $homeStatMetricRaw) {
                ForEach(HomeStatMetric.allCases) { metric in
                    Text(metric.displayName).tag(metric.rawValue)
                }
            }
            .accessibilityIdentifier("settings.homeStatMetricPicker")

            Picker("Time Window", selection: $homeStatWindowRaw) {
                ForEach(StatsTimeWindow.allCases) { window in
                    Text(window.displayName).tag(window.rawValue)
                }
            }
            .accessibilityIdentifier("settings.homeStatWindowPicker")
        } header: {
            Text("Home Screen Stat")
        } footer: {
            Text(
                "Shown in the small circle next to the active site ring. "
                + "The 25th percentile is the duration 1 in 4 of your sites ended before, "
                + "so a low value means sites are failing early. The active site is not counted."
            )
        }
    }

    private var selectedStrategy: RecommendationStrategy {
        RecommendationStrategy(rawValue: recommendationStrategyRaw) ?? .bySite
    }

    private var recommendationModeDescription: String {
        switch selectedStrategy {
        case .bySite:
            return "Rotate among individual sites"
        case .byBodyPart:
            return "Let each body part rest between uses, even across nearby sites"
        case .byBodyPartCooldown:
            return "Deprioritize body parts used in the last \(bodyPartCooldownCount) site changes"
        }
    }

    private func exportCSV() {
        let descriptor = FetchDescriptor<SiteChangeEntry>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        let csvString = CSVExporter.generate(from: entries)
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(
            CSVExporter.fileName()
        )
        try? csvString.write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        csvFileURL = fileURL
        showingShareSheet = true
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Activity Presenter

private struct ActivityPresenter: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard uiViewController.presentedViewController == nil else { return }
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            isPresented = false
        }
        uiViewController.present(activityVC, animated: true)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Location.self, SiteChangeEntry.self, SiteProblem.self], inMemory: true)
}
