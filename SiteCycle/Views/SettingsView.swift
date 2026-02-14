import SwiftUI

struct SettingsView: View {
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72
    @AppStorage("absorptionAlertThreshold") private var absorptionAlertThreshold: Int = 20

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
                Label("Export Data", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
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
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
