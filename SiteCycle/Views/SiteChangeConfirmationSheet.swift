import SwiftUI

struct SiteChangeConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let targetLocation: Location
    let previousEntry: SiteChangeEntry?
    /// `changeTime` is nil when the user kept the default ("now").
    typealias ConfirmHandler = (
        _ newNote: String,
        _ previousNoteUpdate: PreviousNoteUpdate,
        _ changeTime: Date?
    ) -> Void

    let onConfirm: ConfirmHandler

    @State private var newNote: String = ""
    @State private var previousNote: String
    @State private var isSubmitting = false
    /// Only meaningful once `isCustomTime` is true. Until the user touches the
    /// picker, the change is logged at the moment Confirm is tapped (not when
    /// the sheet opened), so lingering on this sheet doesn't backdate the entry.
    @State private var changeTime = Date()
    @State private var isCustomTime = false

    init(
        targetLocation: Location,
        previousEntry: SiteChangeEntry?,
        onConfirm: @escaping ConfirmHandler
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

                changeTimeSection

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
                        .accessibilityIdentifier("siteChangeConfirmation.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        guard !isSubmitting else { return }
                        isSubmitting = true
                        let update: PreviousNoteUpdate = previousEntry == nil
                            ? .leaveUnchanged
                            : .replace(previousNote)
                        onConfirm(newNote, update, isCustomTime ? changeTime : nil)
                        dismiss()
                    }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("siteChangeConfirmation.confirm")
                }
            }
        }
    }

    private var changeTimeSection: some View {
        Section {
            DatePicker(
                "Changed At",
                selection: Binding(
                    get: { isCustomTime ? changeTime : Date() },
                    set: { newValue in
                        changeTime = newValue
                        isCustomTime = true
                    }
                ),
                in: earliestChangeTime...Date()
            )
            .accessibilityIdentifier("siteChangeConfirmation.changeTime")
        } header: {
            Text("Time")
        } footer: {
            if isCustomTime {
                Button("Use Current Time") { isCustomTime = false }
                    .font(.footnote)
                    .accessibilityIdentifier("siteChangeConfirmation.useCurrentTime")
            }
        }
    }

    /// The new site can't start before the previous one did, otherwise closing
    /// the previous entry would give it a negative duration.
    private var earliestChangeTime: Date {
        previousEntry?.startTime ?? .distantPast
    }
}
