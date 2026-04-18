import SwiftUI

struct SiteChangeConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let targetLocation: Location
    let previousEntry: SiteChangeEntry?
    let onConfirm: (_ newNote: String, _ previousNoteUpdate: PreviousNoteUpdate) -> Void

    @State private var newNote: String = ""
    @State private var previousNote: String
    @State private var isSubmitting = false

    init(
        targetLocation: Location,
        previousEntry: SiteChangeEntry?,
        onConfirm: @escaping (_ newNote: String, _ previousNoteUpdate: PreviousNoteUpdate) -> Void
    ) {
        self.targetLocation = targetLocation
        self.previousEntry = previousEntry
        self.onConfirm = onConfirm
        _previousNote = State(initialValue: previousEntry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Changing To") {
                    LocationLabelView(location: targetLocation)
                        .fontWeight(.medium)
                }

                Section("New Site Note") {
                    TextField("Add a note (optional)", text: $newNote, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let previousEntry, let previousLocation = previousEntry.location {
                    Section {
                        TextField(
                            "Add or edit a note (optional)",
                            text: $previousNote,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    } header: {
                        Text("Previous Site Note")
                    } footer: {
                        Text("Closing: \(previousLocation.fullDisplayName)")
                    }
                }
            }
            .navigationTitle("Confirm Site Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        guard !isSubmitting else { return }
                        isSubmitting = true
                        let update: PreviousNoteUpdate = previousEntry == nil
                            ? .leaveUnchanged
                            : .replace(previousNote)
                        onConfirm(newNote, update)
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}
