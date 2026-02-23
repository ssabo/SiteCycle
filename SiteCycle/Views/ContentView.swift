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
            syncViewModel.state.alertTitle,
            isPresented: $syncViewModel.showingStatusAlert,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(syncViewModel.statusAlertMessage ?? "")
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

    private var syncIconView: some View {
        Button(action: { syncViewModel.handleTap() }, label: {
            Image(systemName: syncViewModel.state.iconName)
                .font(.subheadline)
                .foregroundStyle(syncViewModel.state.foregroundColor)
        })
        .accessibilityLabel(syncViewModel.state.accessibilityLabel)
    }
}

#Preview {
    ContentView(isCloudKitEnabled: false)
        .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
