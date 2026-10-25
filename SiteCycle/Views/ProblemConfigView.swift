import SwiftUI
import SwiftData

struct ProblemConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SiteProblem.sortOrder) private var allProblems: [SiteProblem]
    @State private var showingAddSheet = false

    var body: some View {
        List {
            Section {
                ForEach(allProblems) { problem in
                    NavigationLink {
                        EditProblemView(problem: problem)
                    } label: {
                        ProblemRow(problem: problem)
                    }
                    .accessibilityIdentifier("problemConfig.row.\(problem.name)")
                }
                .onDelete(perform: deleteProblems)
                .onMove(perform: moveProblems)
            } footer: {
                Text("Problems record why a site was changed early. Disabled problems stay on past entries "
                    + "but aren't offered when logging. Built-in problems can be renamed or disabled, but not deleted.")
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Custom Problem", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("problemConfig.addCustomProblem")
        }
        .navigationTitle("Manage Problems")
        .toolbar {
            EditButton()
                .accessibilityIdentifier("problemConfig.editMode")
        }
        .sheet(isPresented: $showingAddSheet) {
            AddProblemSheet { name, emoji in
                addCustomProblem(name: name, emoji: emoji)
            }
        }
    }

    private func addCustomProblem(name: String, emoji: String) {
        let maxSortOrder = allProblems.map(\.sortOrder).max() ?? -1
        modelContext.insert(SiteProblem(
            name: name,
            emoji: emoji,
            isCustom: true,
            sortOrder: maxSortOrder + 1
        ))
        try? modelContext.save()
    }

    /// Same rule as locations: custom problems with history are disabled
    /// rather than deleted so past entries keep their reason.
    private func deleteProblems(at offsets: IndexSet) {
        for index in offsets {
            let problem = allProblems[index]
            guard problem.isCustom else { continue }
            if problem.safeEntries.isEmpty {
                modelContext.delete(problem)
            } else {
                problem.isEnabled = false
            }
        }
        try? modelContext.save()
    }

    private func moveProblems(from source: IndexSet, to destination: Int) {
        var ordered = allProblems
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, problem) in ordered.enumerated() {
            problem.sortOrder = index
        }
        try? modelContext.save()
    }
}

// MARK: - Row

private struct ProblemRow: View {
    let problem: SiteProblem

    var body: some View {
        HStack(spacing: 12) {
            Text(problem.displayEmoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.name)
                    .foregroundStyle(problem.isEnabled ? .primary : .secondary)
                if !problem.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if problem.isCustom {
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Shared Fields

private struct ProblemFields: View {
    @Binding var name: String
    @Binding var emoji: String

    var body: some View {
        TextField("Name", text: $name)
            .accessibilityIdentifier("problemForm.name")
        HStack {
            Text("Emoji")
            Spacer()
            TextField(
                SiteProblem.fallbackEmoji,
                text: Binding(
                    get: { emoji },
                    set: { emoji = SiteProblem.sanitizeEmoji($0) }
                )
            )
            .multilineTextAlignment(.trailing)
            .font(.title2)
            .frame(maxWidth: 80)
            .accessibilityIdentifier("problemForm.emoji")
        }
    }
}

// MARK: - Edit

private struct EditProblemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let problem: SiteProblem

    @State private var name: String
    @State private var emoji: String
    @State private var isEnabled: Bool

    init(problem: SiteProblem) {
        self.problem = problem
        _name = State(initialValue: problem.name)
        _emoji = State(initialValue: problem.emoji)
        _isEnabled = State(initialValue: problem.isEnabled)
    }

    private var builtInDefault: DefaultProblem? {
        DefaultProblems.all.first { $0.key == problem.defaultKey }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section {
                ProblemFields(name: $name, emoji: $emoji)
            } footer: {
                Text("Tap the emoji field and switch to the emoji keyboard to pick a new one.")
            }

            Section {
                Toggle("Enabled", isOn: $isEnabled)
                    .accessibilityIdentifier("problemForm.enabled")
            }

            if let builtInDefault, builtInDefault.name != name || builtInDefault.emoji != emoji {
                Section {
                    Button("Restore Default Name & Emoji") {
                        name = builtInDefault.name
                        emoji = builtInDefault.emoji
                    }
                    .accessibilityIdentifier("problemForm.restoreDefault")
                }
            }
        }
        .navigationTitle("Edit Problem")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    problem.name = trimmedName
                    problem.emoji = emoji
                    problem.isEnabled = isEnabled
                    try? modelContext.save()
                    dismiss()
                }
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier("problemForm.save")
            }
        }
    }
}

// MARK: - Add

private struct AddProblemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = ""
    let onSave: (_ name: String, _ emoji: String) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProblemFields(name: $name, emoji: $emoji)
                } footer: {
                    Text("If you leave the emoji blank, \(SiteProblem.fallbackEmoji) is shown.")
                }
            }
            .navigationTitle("Add Custom Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("addProblem.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedName, emoji)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier("addProblem.save")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProblemConfigView()
    }
    .modelContainer(for: [Location.self, SiteChangeEntry.self, SiteProblem.self], inMemory: true)
}
