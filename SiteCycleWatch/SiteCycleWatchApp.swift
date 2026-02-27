import SwiftUI
import WidgetKit

@main
struct SiteCycleWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var connectivityManager = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(connectivityManager)
                .onAppear {
                    connectivityManager.activate()
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
