import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HistoryViewModel?
    @State private var selectedEntry: SiteChangeEntry?
    @State private var showingDeleteConfirmation = false
    @State private var entryToDelete: SiteChangeEntry?
    @State private var selectedDateRange = "All Time"
    @State private var selectedLocation: Location?

    @Query(sort: \Location.sortOrder)
    private var allLocations: [Location]

    private let dateRangeOptions = ["Last 7 days", "Last 30 days", "Last 90 days", "All Time"]

    var body: some View {
        Group {
            if let viewModel = viewModel {
                historyContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("History")
        .onAppear { setupViewModel() }
    }

    private func setupViewModel() {
        if viewModel == nil {
            viewModel = HistoryViewModel(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func historyContent(viewModel: HistoryViewModel) -> some View {
        let entries = viewModel.filteredEntries
        if entries.isEmpty && selectedDateRange == "All Time" && selectedLocation == nil {
            emptyStateContent
        } else {
            listContent(viewModel: viewModel, entries: entries)
        }
    }

    private func listContent(viewModel: HistoryViewModel, entries: [SiteChangeEntry]) -> some View {
        List {
            filterSection(viewModel: viewModel)

            if entries.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Text("No matching entries")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Try adjusting your filters.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink {
                            HistoryEditView(
                                entry: entry,
                                viewModel: viewModel,
                                allLocations: allLocations
                            )
                        } label: {
                            entryRow(entry)
                        }
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first {
                            entryToDelete = entries[index]
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Entry",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible,
            actions: {
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        viewModel.deleteEntry(entry)
                        entryToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    entryToDelete = nil
                }
            },
            message: {
                Text("Are you sure you want to delete this entry? This cannot be undone.")
            }
        )
    }

    private func filterSection(viewModel: HistoryViewModel) -> some View {
        Section {
            Picker("Location", selection: $selectedLocation) {
                Text("All Locations").tag(Location?.none)
                ForEach(allLocations) { location in
                    Text(location.displayName).tag(Location?.some(location))
                }
            }
            .onChange(of: selectedLocation) { _, newValue in
                viewModel.locationFilter = newValue
            }

            Picker("Date Range", selection: $selectedDateRange) {
                ForEach(dateRangeOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .onChange(of: selectedDateRange) { _, newValue in
                applyDateRange(newValue, to: viewModel)
            }
        }
    }

    private func applyDateRange(_ range: String, to viewModel: HistoryViewModel) {
        let now = Date()
        switch range {
        case "Last 7 days":
            viewModel.startDate = now.addingTimeInterval(-7 * 86400)
            viewModel.endDate = now
        case "Last 30 days":
            viewModel.startDate = now.addingTimeInterval(-30 * 86400)
            viewModel.endDate = now
        case "Last 90 days":
            viewModel.startDate = now.addingTimeInterval(-90 * 86400)
            viewModel.endDate = now
        default:
            viewModel.startDate = nil
            viewModel.endDate = nil
        }
    }

    private func entryRow(_ entry: SiteChangeEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.location?.displayName ?? "Unknown Location")
                    .font(.headline)
                Spacer()
                if entry.endTime == nil {
                    Text("Active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green, in: Capsule())
                } else if let hours = entry.durationHours {
                    Text(formatDuration(hours))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.startTime, style: .date)
                + Text(" at ")
                + Text(entry.startTime, style: .time)

            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int((hours - Double(wholeHours)) * 60)
        if wholeHours > 0 && minutes > 0 {
            return "\(wholeHours)h \(minutes)m"
        } else if wholeHours > 0 {
            return "\(wholeHours)h"
        } else {
            return "\(minutes)m"
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Site Changes Yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Your site change history will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
