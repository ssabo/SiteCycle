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
    /// Only the newest entry can be made active again (review §2.7).
    private let canClearEndTime: Bool

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
        canClearEndTime = entry.endTime == nil || viewModel.canClearEndTime(entry)
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
                    .disabled(!canClearEndTime)
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
                if !canClearEndTime {
                    Text("Only the most recent site can be active.")
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
            viewModel.clearEndTime(entry)
            if newLocation != nil || newStart != nil || newNote != nil {
                viewModel.updateEntry(
                    entry,
                    location: newLocation,
                    startTime: newStart,
                    endTime: nil,
                    note: newNote
                )
            }
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
