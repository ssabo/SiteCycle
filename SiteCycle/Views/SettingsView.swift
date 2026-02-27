import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PhoneConnectivityManager.self) private var connectivityManager
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72
    @AppStorage("absorptionAlertThreshold") private var absorptionAlertThreshold: Int = 20
    @State private var csvFileURL: URL?
    @State private var showingShareSheet = false
    @State private var showingImportWarning = false
    @State private var showingImportPicker = false
    @State private var importResult: ImportResultAlert?

    var body: some View {
        Form { formSections }
            .navigationTitle("Settings")
            .onChange(of: targetDurationHours) {
                connectivityManager.pushCurrentState()
            }
            .background(
                Group {
                    if showingShareSheet, let csvFileURL {
                        ActivityPresenter(url: csvFileURL, isPresented: $showingShareSheet)
                    }
                    if showingImportPicker {
                        DocumentPickerView(
                            onPickURL: { url in importCSV(from: url) },
                            isPresented: $showingImportPicker
                        )
                    }
                }
            )
            .alert("Replace All Data?", isPresented: $showingImportWarning) {
                Button("Import", role: .destructive) { showingImportPicker = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Importing a CSV file will permanently delete all existing site history and locations. This cannot be undone.")
            }
            .alert(item: $importResult) { result in
                Alert(
                    title: Text(result.title),
                    message: Text(result.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }

    @ViewBuilder private var formSections: some View {
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

            Button(role: .destructive) {
                showingImportWarning = true
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

    private func importCSV(from url: URL) {
        do {
            let result = try CSVImporter.importCSV(from: url, context: modelContext)
            let count = result.importedCount
            let noun = count == 1 ? "entry" : "entries"
            var message = "Imported \(count) site change \(noun)."
            if !result.skippedRows.isEmpty {
                let lines = result.skippedRows.map { "• Row \($0.rowNumber): \($0.reason)" }.joined(separator: "\n")
                message += "\n\n\(result.skippedRows.count) rows were skipped:\n\(lines)"
            }
            connectivityManager.pushCurrentState()
            importResult = ImportResultAlert(
                title: "Import Successful",
                message: message
            )
        } catch {
            importResult = ImportResultAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Import Result Alert

private struct ImportResultAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
    .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
