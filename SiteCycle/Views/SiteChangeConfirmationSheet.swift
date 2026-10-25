import SwiftUI
import SwiftData

/// What the user chose on the confirmation sheet.
struct SiteChangeConfirmation {
    let newNote: String
    let previousNote: PreviousNoteUpdate
    let previousProblem: PreviousProblemUpdate
    /// The entry shown as "Closing" — the note and problem updates apply to it.
    let previousEntry: SiteChangeEntry?
    /// nil when the user kept the default ("now").
    let changeTime: Date?
}

struct SiteChangeConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SiteProblem.sortOrder) private var allProblems: [SiteProblem]

    let targetLocation: Location
    let previousEntry: SiteChangeEntry?
    typealias ConfirmHandler = (SiteChangeConfirmation) -> Void

    let onConfirm: ConfirmHandler

    @State private var newNote: String = ""
    @State private var previousNote: String
    @State private var previousProblem: SiteProblem?
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
        _previousProblem = State(initialValue: previousEntry?.problem)
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

                if let previousLocation = previousEntry?.location {
                    previousSiteSections(previousLocation: previousLocation)
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
                        let hasPrevious = previousEntry != nil
                        onConfirm(SiteChangeConfirmation(
                            newNote: newNote,
                            previousNote: hasPrevious ? .replace(previousNote) : .leaveUnchanged,
                            previousProblem: hasPrevious ? .replace(previousProblem) : .leaveUnchanged,
                            previousEntry: previousEntry,
                            changeTime: isCustomTime ? changeTime : nil
                        ))
                        dismiss()
                    }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("siteChangeConfirmation.confirm")
                }
            }
        }
    }

    @ViewBuilder
    private func previousSiteSections(previousLocation: Location) -> some View {
        Section {
            ProblemPicker(selection: $previousProblem, problems: allProblems, original: previousEntry?.problem)
                .accessibilityIdentifier("siteChangeConfirmation.previousProblem")
        } header: {
            Text("Previous Site Problem")
        } footer: {
            Text("Changed early? Record why so you can spot problem sites in History and Statistics.")
        }

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
