import SwiftUI
import SwiftData

struct WatchSiteSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SiteChangeViewModel?
    @State private var confirmingLocation: Location?

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
                        viewModel?.logSiteChange(location: location, note: nil)
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
            viewModel = SiteChangeViewModel(modelContext: modelContext)
        } else {
            viewModel?.refresh()
        }
    }

    private func siteList(viewModel: SiteChangeViewModel) -> some View {
        List {
            if !viewModel.recommendations.recommended.isEmpty {
                Section("Recommended") {
                    ForEach(viewModel.recommendations.recommended) { location in
                        WatchLocationRow(
                            location: location,
                            category: .recommended
                        )
                        .onTapGesture { confirmingLocation = location }
                    }
                }
            }

            Section("All Locations") {
                ForEach(viewModel.recommendations.allSorted) { location in
                    WatchLocationRow(
                        location: location,
                        category: viewModel.category(for: location)
                    )
                    .onTapGesture { confirmingLocation = location }
                }
            }
        }
    }
}
