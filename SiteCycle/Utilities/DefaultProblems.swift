import Foundation
import SwiftData

struct DefaultProblem: Sendable {
    let key: String
    let name: String
    let emoji: String
}

enum DefaultProblems {
    /// Seeded in this order. Keys are persisted (`SiteProblem.defaultKey`) — never change them.
    static let all: [DefaultProblem] = [
        DefaultProblem(key: "painful", name: "Painful", emoji: "🤕"),
        DefaultProblem(key: "leaking", name: "Leaking", emoji: "💧"),
        DefaultProblem(key: "fellOff", name: "Fell Off / Ripped Off", emoji: "🩹"),
        DefaultProblem(key: "occlusion", name: "Occlusion", emoji: "🚫"),
        DefaultProblem(key: "highs", name: "Unexplained Highs", emoji: "📈"),
        DefaultProblem(key: "bleeding", name: "Bleeding", emoji: "🩸"),
    ]
}

/// Inserts any default problem not already present (matched by `defaultKey`).
/// Defaults are never hard-deleted (only disabled), so this only adds them on
/// first launch, or when a later app version introduces a new default.
@MainActor
func seedDefaultProblems(context: ModelContext) {
    guard let existing = try? context.fetch(FetchDescriptor<SiteProblem>()) else { return }

    let existingKeys = Set(existing.compactMap(\.defaultKey))
    var sortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
    var didInsert = false

    for problem in DefaultProblems.all where !existingKeys.contains(problem.key) {
        context.insert(SiteProblem(
            name: problem.name,
            emoji: problem.emoji,
            isCustom: false,
            sortOrder: sortOrder,
            defaultKey: problem.key
        ))
        sortOrder += 1
        didInsert = true
    }

    if didInsert {
        try? context.save()
    }
}

/// Merges duplicate problems, moving all entries onto one keeper. Duplicates
/// arise when two devices both seed the defaults (same `defaultKey`) or both
/// add a custom problem with the same name (same `SiteProblem.nameKey`)
/// before CloudKit syncs.
///
/// The keeper must be the same on every device, or two devices deduplicating
/// before syncing could each delete the copy the other kept. So it is chosen
/// only from record properties both devices see identically once both copies
/// have synced: a default the user customized wins over a pristine one, then
/// the lowest `id`. Entry counts are not used — entry relationships sync
/// separately and can differ between devices meanwhile.
@MainActor
func deduplicateProblems(context: ModelContext) {
    guard let problems = try? context.fetch(FetchDescriptor<SiteProblem>()) else { return }

    var groups: [String: [SiteProblem]] = [:]
    for problem in problems {
        let key = problem.defaultKey.map { "default:\($0)" } ?? "custom:\(SiteProblem.nameKey(problem.name))"
        groups[key, default: []].append(problem)
    }

    var didChange = false
    for (_, group) in groups where group.count > 1 {
        let sorted = group.sorted(by: isPreferredDuplicateKeeper)
        guard let keeper = sorted.first else { continue }

        for duplicate in sorted.dropFirst() {
            for entry in duplicate.safeEntries {
                var problems = (entry.problems ?? []).filter { $0.id != duplicate.id }
                if !problems.contains(where: { $0.id == keeper.id }) {
                    problems.append(keeper)
                }
                entry.problems = problems
            }
            context.delete(duplicate)
            didChange = true
        }
    }

    if didChange {
        try? context.save()
    }
}

/// Whether the user has changed a seeded default from how it was seeded:
/// renamed, new emoji, disabled, or moved from its seeded position. Seeding
/// on a fresh store gives each default its index in `DefaultProblems.all`.
func isCustomizedDefault(_ problem: SiteProblem) -> Bool {
    guard let index = DefaultProblems.all.firstIndex(where: { $0.key == problem.defaultKey }) else {
        return false
    }
    let original = DefaultProblems.all[index]
    return !problem.isEnabled
        || problem.name != original.name
        || problem.emoji != original.emoji
        || problem.sortOrder != index
}

private func isPreferredDuplicateKeeper(_ lhs: SiteProblem, _ rhs: SiteProblem) -> Bool {
    let lhsCustomized = isCustomizedDefault(lhs)
    let rhsCustomized = isCustomizedDefault(rhs)
    if lhsCustomized != rhsCustomized { return lhsCustomized }
    // Same-named custom problems: keep one the user still has enabled.
    if lhs.isCustom, rhs.isCustom, lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled }
    return lhs.id.uuidString < rhs.id.uuidString
}
