import SwiftUI
import SwiftData

struct HistoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneConnectivityManager.self) private var connectivityManager

    let entry: SiteChangeEntry
    let viewModel: HistoryViewModel
    let allLocations: [Location]
    let allProblems: [SiteProblem]

    @State private var selectedLocation: Location?
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var hasEndTime: Bool
    @State private var note: String
    @State private var problems: [SiteProblem]

    init(
        entry: SiteChangeEntry,
        viewModel: HistoryViewModel,
        allLocations: [Location],
        allProblems: [SiteProblem]
    ) {
        self.entry = entry
        self.viewModel = viewModel
        self.allLocations = allLocations
        self.allProblems = allProblems
        _selectedLocation = State(initialValue: entry.location)
        _startTime = State(initialValue: entry.startTime)
        _endTime = State(initialValue: entry.endTime ?? Date())
        _hasEndTime = State(initialValue: entry.endTime != nil)
        _note = State(initialValue: entry.note ?? "")
        _problems = State(initialValue: entry.safeProblems)
    }

    var body: some View {
        Form {
            Section("Location") {
                Picker("Location", selection: $selectedLocation) {
                    Text("None").tag(Location?.none)
                    ForEach(allLocations) { location in
                        Text(location.fullDisplayName).tag(Location?.some(location))
                    }
                }
                .accessibilityIdentifier("historyEdit.locationPicker")
            }

            Section {
                DatePicker(
                    "Start Time",
                    selection: $startTime
                )
                .accessibilityIdentifier("historyEdit.startTime")

                Toggle("Has End Time", isOn: $hasEndTime)
                    .accessibilityIdentifier("historyEdit.hasEndTime")

                if hasEndTime {
                    DatePicker(
                        "End Time",
                        selection: $endTime,
                        in: startTime...
                    )
                    .accessibilityIdentifier("historyEdit.endTime")
                }
            } header: {
                Text("Timing")
            } footer: {
                if !keepsActiveSiteNewest {
                    Text(hasEndTime
                        ? "Only the most recent site can be active, so this can't start after the active site."
                        : "Only the most recent site can be active, so this can't start before another entry.")
                }
            }

            problemSection

            Section("Note") {
                TextField("Add a note...", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("historyEdit.note")
            }
        }
        .navigationTitle("Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("historyEdit.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                    connectivityManager.pushCurrentState()
                    dismiss()
                }
                .disabled(!keepsActiveSiteNewest)
                .accessibilityIdentifier("historyEdit.save")
            }
        }
    }

    private var problemSection: some View {
        Section {
            ProblemChips(selection: $problems, problems: allProblems, original: entry.safeProblems)
                .accessibilityIdentifier("historyEdit.problems")
        } header: {
            Text("Problems")
        } footer: {
            Text("Why this site was changed early, if it was. Tap to select any that apply.")
        }
    }

    /// Re-checked as the form changes, so moving the start time or toggling
    /// the end time updates it (review §2.7).
    private var keepsActiveSiteNewest: Bool {
        viewModel.keepsActiveSiteNewest(entry, startTime: startTime, isActive: !hasEndTime)
    }

    private func saveChanges() {
        viewModel.setProblems(entry, problems: problems)

        let newLocation = selectedLocation?.id != entry.location?.id ? selectedLocation : nil
        let newStart = abs(startTime.timeIntervalSince(entry.startTime)) > 1 ? startTime : nil
        let newNote = note != (entry.note ?? "") ? note : nil

        if hasEndTime {
            let newEnd = entry.endTime == nil || abs(endTime.timeIntervalSince(entry.endTime ?? Date())) > 1
                ? endTime : nil
            viewModel.updateEntry(
                entry,
                location: newLocation,
                startTime: newStart,
                endTime: newEnd,
                note: newNote
            )
        } else if entry.endTime != nil {
            viewModel.reopen(entry, location: newLocation, startTime: newStart, note: newNote)
        } else {
            viewModel.updateEntry(
                entry,
                location: newLocation,
                startTime: newStart,
                endTime: nil,
                note: newNote
            )
        }
    }
}
