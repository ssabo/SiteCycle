import SwiftUI
import WidgetKit

struct WatchSiteSelectionView: View {
    @Environment(WatchConnectivityManager.self) private var connectivityManager
    @State private var viewModel: WatchSiteChangeViewModel?
    @State private var confirmingLocation: LocationInfo?

    var onComplete: () -> Void

    var body: some View {
        Group {
            if let viewModel {
                siteList(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Change Site")
        .onAppear { setupViewModel() }
        .confirmationDialog(
            "Log site change?",
            isPresented: Binding(
                get: { confirmingLocation != nil },
                set: { if !$0 { confirmingLocation = nil } }
            ),
            titleVisibility: .visible,
            actions: {
                if let location = confirmingLocation {
                    Button("Log to \(location.fullDisplayName)") {
                        viewModel?.logSiteChange(locationId: location.id)
                        WidgetCenter.shared.reloadAllTimelines()
                        onComplete()
                    }
                    Button("Cancel", role: .cancel) {
                        confirmingLocation = nil
                    }
                }
            }
        )
    }

    private func setupViewModel() {
        if viewModel == nil {
            viewModel = WatchSiteChangeViewModel(
                connectivityManager: connectivityManager
            )
        }
    }

    private func siteList(viewModel: WatchSiteChangeViewModel) -> some View {
        List {
            if !viewModel.recommendedLocations.isEmpty {
                Section("Recommended") {
                    ForEach(viewModel.recommendedLocations) { location in
                        Button {
                            confirmingLocation = location
                        } label: {
                            WatchLocationRow(
                                location: location,
                                category: .recommended
                            )
                        }
                    }
                }
            }

            Section("All Locations") {
                ForEach(viewModel.allLocationsSorted) { location in
                    Button {
                        confirmingLocation = location
                    } label: {
                        WatchLocationRow(
                            location: location,
                            category: viewModel.category(for: location)
                        )
                    }
                }
            }
        }
    }
}
