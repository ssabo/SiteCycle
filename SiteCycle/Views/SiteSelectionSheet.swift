import SwiftUI
import SwiftData

struct SiteSelectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneConnectivityManager.self) private var connectivityManager
    @State private var viewModel: SiteChangeViewModel?
    @State private var selectedLocation: Location?
    @State private var note = ""
    @State private var showingConfirmation = false
    @State private var isLogging = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    locationList(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Log Site Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = SiteChangeViewModel(modelContext: modelContext)
                }
            }
            .alert("Confirm Site Change", isPresented: $showingConfirmation) {
                TextField("Add a note (optional)", text: $note)
                Button("Confirm") {
                    guard !isLogging, let location = selectedLocation else { return }
                    isLogging = true
                    viewModel?.logSiteChange(location: location, note: note)
                    connectivityManager.pushCurrentState()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    selectedLocation = nil
                    note = ""
                }
            } message: {
                Text("Log site change to \(selectedLocation?.fullDisplayName ?? "")?")
            }
        }
    }

    private func locationList(viewModel: SiteChangeViewModel) -> some View {
        List {
            if !viewModel.recommendations.recommended.isEmpty {
                Section {
                    ForEach(viewModel.recommendations.recommended) { location in
                        locationRow(location: location, viewModel: viewModel, category: .recommended)
                    }
                } header: {
                    Label("Recommended", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Section("All Locations") {
                ForEach(viewModel.recommendations.allSorted) { location in
                    locationRow(
                        location: location,
                        viewModel: viewModel,
                        category: viewModel.category(for: location)
                    )
                }
            }
        }
    }

    private func locationRow(
        location: Location,
        viewModel: SiteChangeViewModel,
        category: LocationCategory
    ) -> some View {
        Button {
            selectedLocation = location
            note = ""
            showingConfirmation = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    LocationLabelView(location: location)
                        .foregroundStyle(.primary)

                    if let lastUsed = viewModel.lastUsedDate(for: location) {
                        HStack {
                            Text(daysAgoText(from: lastUsed))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastUsed, format: .dateTime.month().day())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("Never used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                categoryBadge(category)
            }
        }
    }

    @ViewBuilder
    private func categoryBadge(_ category: LocationCategory) -> some View {
        switch category {
        case .avoid:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .recommended:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .neutral:
            EmptyView()
        }
    }

    private func daysAgoText(from date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }
}

#Preview {
    SiteSelectionSheet()
        .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
