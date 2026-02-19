import SwiftUI
import Network

struct ContentView: View {
    @State private var isConnected = true

    private let monitor = NWPathMonitor()

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .toolbar {
                        toolbarItems
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                HistoryView()
                    .toolbar {
                        toolbarItems
                    }
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }

            NavigationStack {
                StatisticsView()
                    .toolbar {
                        toolbarItems
                    }
            }
            .tabItem {
                Label("Statistics", systemImage: "chart.bar")
            }
        }
        .onAppear { startMonitoring() }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Image(systemName: syncIconName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(syncAccessibilityLabel)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gear")
            }
        }
    }

    private var syncIconName: String {
        isConnected ? "checkmark.icloud" : "icloud.slash"
    }

    private var syncAccessibilityLabel: String {
        isConnected ? "iCloud synced" : "Offline"
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                isConnected = connected
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
