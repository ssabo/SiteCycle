import SwiftUI
import SwiftData

struct HistoryEditView: View {
    @Environment(\.dismiss) private var dismiss

    let entry: SiteChangeEntry
    let viewModel: HistoryViewModel
    let allLocations: [Location]

    @State private var selectedLocation: Location?
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var hasEndTime: Bool
    @State private var note: String

    init(entry: SiteChangeEntry, viewModel: HistoryViewModel, allLocations: [Location]) {
        self.entry = entry
        self.viewModel = viewModel
        self.allLocations = allLocations
        _selectedLocation = State(initialValue: entry.location)
        _startTime = State(initialValue: entry.startTime)
        _endTime = State(initialValue: entry.endTime ?? Date())
        _hasEndTime = State(initialValue: entry.endTime != nil)
        _note = State(initialValue: entry.note ?? "")
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
            }

            Section("Timing") {
                DatePicker(
                    "Start Time",
                    selection: $startTime
                )

                Toggle("Has End Time", isOn: $hasEndTime)

                if hasEndTime {
                    DatePicker(
                        "End Time",
                        selection: $endTime,
                        in: startTime...
                    )
                }
            }

            Section("Note") {
                TextField("Add a note...", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                    dismiss()
                }
            }
        }
    }

    private func saveChanges() {
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
