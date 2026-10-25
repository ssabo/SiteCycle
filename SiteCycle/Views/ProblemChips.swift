import SwiftUI

/// One-tap, multi-select grid of problem chips ("💧 Leaking"), shared by the
/// site change confirmation sheet and the history editor.
struct ProblemChips: View {
    @Binding var selection: [SiteProblem]
    let problems: [SiteProblem]
    /// The entry's problems before editing; offered even if since disabled.
    let original: [SiteProblem]

    private var options: [SiteProblem] {
        SiteProblem.pickerOptions(from: problems, including: original + selection)
    }

    var body: some View {
        if options.isEmpty {
            Text("No problems are enabled. Add or enable them in Settings → Manage Problems.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(options) { problem in
                    chip(problem)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func isSelected(_ problem: SiteProblem) -> Bool {
        selection.contains { $0.id == problem.id }
    }

    private func chip(_ problem: SiteProblem) -> some View {
        let selected = isSelected(problem)
        return Button {
            toggle(problem)
        } label: {
            HStack(spacing: 6) {
                Text(problem.displayEmoji)
                Text(problem.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        // Borderless so each chip is its own tap target inside a Form row,
        // instead of the whole row acting as one button.
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("problemChips.\(problem.name)")
    }

    private func toggle(_ problem: SiteProblem) {
        if let index = selection.firstIndex(where: { $0.id == problem.id }) {
            selection.remove(at: index)
        } else {
            selection.append(problem)
        }
    }
}
