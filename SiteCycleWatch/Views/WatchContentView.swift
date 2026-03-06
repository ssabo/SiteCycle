import SwiftUI

struct WatchContentView: View {
    @Environment(WatchConnectivityManager.self) private var connectivityManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchHomeView()
                .tag(0)

            WatchSiteSelectionView(onSiteChanged: {
                selectedTab = 0
            })
            .tag(1)
        }
        .tabViewStyle(.verticalPage)
        .overlay {
            if connectivityManager.hasPendingCommand {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Sending...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 4)
            }
        }
    }
}
