import SwiftUI

struct WatchSiteSelectionView: View {
    @Environment(WatchConnectivityManager.self) private var connectivityManager
    @State private var viewModel: WatchSiteChangeViewModel?
    @State private var confirmingLocation: LocationInfo?
    @State private var didLogSiteChange = false

    var onSiteChanged: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    siteList(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Change Site")
        }
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
                        didLogSiteChange = true
                    }
                    Button("Cancel", role: .cancel) {
                        confirmingLocation = nil
                    }
                }
            }
        )
        .onChange(of: confirmingLocation) { oldValue, newValue in
            if let location = oldValue, newValue == nil, didLogSiteChange {
                didLogSiteChange = false
                viewModel?.logSiteChange(locationId: location.id)
                onSiteChanged()
            }
        }
    }

    private func setupViewModel() {
        if viewModel == nil {
            viewModel = WatchSiteChangeViewModel(
                connectivityManager: connectivityManager
            )
        }
    }

    private func siteList(viewModel: WatchSiteChangeViewModel) -> some View {
        // TimelineView keeps the "days ago" labels current — the watch app can
        // stay resumed for days without any state change to trigger a re-render.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            List {
                if !viewModel.recommendedLocations.isEmpty {
                    Section("Recommended") {
                        ForEach(viewModel.recommendedLocations) { location in
                            Button {
                                confirmingLocation = location
                            } label: {
                                WatchLocationRow(
                                    location: location,
                                    category: .recommended,
                                    now: timeline.date
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
                                category: viewModel.category(for: location),
                                now: timeline.date
                            )
                        }
                    }
                }
            }
        }
    }
}
