import SwiftUI

struct ContentView: View {
    let isCloudKitEnabled: Bool
    @State private var syncViewModel: CloudKitSyncViewModel

    init(isCloudKitEnabled: Bool) {
        self.isCloudKitEnabled = isCloudKitEnabled
        _syncViewModel = State(initialValue: CloudKitSyncViewModel(isCloudKitEnabled: isCloudKitEnabled))
    }

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
        .alert(
            "Sync Error",
            isPresented: $syncViewModel.showingErrorAlert,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(syncViewModel.errorAlertMessage ?? "")
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            syncIconView
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gear")
            }
        }
    }

    @ViewBuilder
    private var syncIconView: some View {
        if case .error = syncViewModel.state {
            Button(action: { syncViewModel.handleErrorTap() }, label: {
                Image(systemName: syncViewModel.state.iconName)
                    .foregroundStyle(Color.red)
            })
            .accessibilityLabel(syncViewModel.state.accessibilityLabel)
        } else {
            Image(systemName: syncViewModel.state.iconName)
                .font(.subheadline)
                .foregroundStyle(syncViewModel.state.foregroundColor)
                .accessibilityLabel(syncViewModel.state.accessibilityLabel)
                .help(syncViewModel.state.tooltip(lastSyncDate: syncViewModel.lastSyncDate))
        }
    }
}

#Preview {
    ContentView(isCloudKitEnabled: false)
        .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
