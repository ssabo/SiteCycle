import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72
    @AppStorage("absorptionAlertThreshold") private var absorptionAlertThreshold: Int = 20
    @State private var csvFileURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        Form {
            Section("Site Management") {
                NavigationLink {
                    LocationConfigView()
                } label: {
                    Label("Manage Locations", systemImage: "mappin.and.ellipse")
                }
            }

            Section("Preferences") {
                Stepper(value: $targetDurationHours, in: 12...168, step: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target Duration")
                        Text("\(targetDurationHours) hours")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $absorptionAlertThreshold, in: 5...50, step: 5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Absorption Alert Threshold")
                        Text("\(absorptionAlertThreshold)% below average")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Data") {
                Button {
                    exportCSV()
                } label: {
                    Label("Export Data as CSV", systemImage: "square.and.arrow.up")
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
        .navigationTitle("Settings")
        .sheet(isPresented: $showingShareSheet) {
            if let csvFileURL {
                ShareSheetView(activityItems: [csvFileURL])
            }
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

// MARK: - Share Sheet

private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
