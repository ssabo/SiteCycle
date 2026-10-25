import SwiftUI
import SwiftData

/// What the user chose on the confirmation sheet.
struct SiteChangeConfirmation {
    let newNote: String
    let previousNote: PreviousNoteUpdate
    let previousProblems: PreviousProblemsUpdate
    /// The entry shown as "Closing" — the note and problem updates apply to it.
    let previousEntry: SiteChangeEntry?
    /// nil when the user kept the default ("now").
    let changeTime: Date?
}

struct SiteChangeConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SiteProblem.sortOrder) private var allProblems: [SiteProblem]
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72

    let targetLocation: Location
    let previousEntry: SiteChangeEntry?
    typealias ConfirmHandler = (SiteChangeConfirmation) -> Void

    let onConfirm: ConfirmHandler

    @State private var newNote: String = ""
    @State private var previousNote: String
    @State private var previousProblems: [SiteProblem]
    /// Set when the user taps "Record a Problem" on a site that wasn't early,
    /// or up front when the site already has problems — so deselecting the
    /// last chip doesn't collapse the grid mid-edit.
    @State private var isProblemsExpanded: Bool
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
        _previousProblems = State(initialValue: previousEntry?.safeProblems ?? [])
        _isProblemsExpanded = State(initialValue: previousEntry?.hasProblems ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Changing To") {
                    LocationLabelView(location: targetLocation)
                        .fontWeight(.medium)
                }

                changeTimeSection

                // The closing site comes before the new site's note: when a
                // site is changed early, what went wrong is what's on the
                // user's mind.
                if let previousEntry, let previousLocation = previousEntry.location {
                    closingSiteSection(previousEntry: previousEntry, previousLocation: previousLocation)
                }

                Section("New Site Note") {
                    TextField("Add a note (optional)", text: $newNote, axis: .vertical)
                        .lineLimit(3...6)
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
                            previousProblems: hasPrevious ? .replace(previousProblems) : .leaveUnchanged,
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

    private func closingSiteSection(previousEntry: SiteChangeEntry, previousLocation: Location) -> some View {
        let hours = closingDurationHours(previousEntry)
        let isEarly = EarlyChange.isEarly(durationHours: hours, targetHours: Double(targetDurationHours))
        // Expanded when a problem is likely (early) or already recorded, so
        // routine changes stay one tap while early ones prompt for a reason.
        let showsProblems = isEarly || isProblemsExpanded || !previousProblems.isEmpty

        return Section {
            HStack {
                LocationLabelView(location: previousLocation)
                Spacer()
                Text("\(Self.formatHours(hours)) of \(targetDurationHours)h")
                    .foregroundStyle(isEarly ? Color.orange : Color.secondary)
            }
            .accessibilityElement(children: .combine)

            if showsProblems {
                ProblemChips(
                    selection: $previousProblems,
                    problems: allProblems,
                    original: previousEntry.safeProblems
                )
                .accessibilityIdentifier("siteChangeConfirmation.previousProblems")
            } else {
                Button {
                    isProblemsExpanded = true
                } label: {
                    Label("Record a Problem", systemImage: "bandage")
                }
                .accessibilityIdentifier("siteChangeConfirmation.recordProblem")
            }

            TextField("Note on this site (optional)", text: $previousNote, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text(isEarly ? "Closing · Changed Early?" : "Closing")
        } footer: {
            if isEarly {
                Text("This site ended well short of your \(targetDurationHours)h target. Tap what went wrong, if anything.")
            } else {
                Text("Problems you record show up in History and Statistics.")
            }
        }
    }

    /// How long the closing site will have lasted at the chosen change time.
    private func closingDurationHours(_ previousEntry: SiteChangeEntry) -> Double {
        let end = isCustomTime ? changeTime : Date()
        return max(0, end.timeIntervalSince(previousEntry.startTime) / 3600)
    }

    private static func formatHours(_ hours: Double) -> String {
        hours < 1 ? "\(Int(hours * 60))m" : "\(Int(hours))h"
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
