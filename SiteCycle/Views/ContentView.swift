import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gear")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                HistoryView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gear")
                            }
                        }
                    }
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }

            NavigationStack {
                StatisticsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gear")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Statistics", systemImage: "chart.bar")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
