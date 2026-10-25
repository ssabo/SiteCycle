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

/// Merges default problems that share a `defaultKey` — created when two devices
/// both seed before CloudKit syncs — moving all entries onto one keeper.
///
/// The keeper must be the same on every device, or two devices deduplicating
/// before syncing could each delete the copy the other kept. So it is chosen
/// only from record properties both devices see identically once both copies
/// have synced: a copy the user customized (renamed, new emoji, disabled) wins
/// over a pristine one, then the lowest `id`. Entry counts are not used — entry
/// relationships sync separately and can differ between devices meanwhile.
@MainActor
func deduplicateProblems(context: ModelContext) {
    guard let problems = try? context.fetch(FetchDescriptor<SiteProblem>()) else { return }

    var groups: [String: [SiteProblem]] = [:]
    for problem in problems {
        guard let key = problem.defaultKey else { continue }
        groups[key, default: []].append(problem)
    }

    var didChange = false
    for (_, group) in groups where group.count > 1 {
        let sorted = group.sorted(by: isPreferredDuplicateKeeper)
        guard let keeper = sorted.first else { continue }

        for duplicate in sorted.dropFirst() {
            for entry in duplicate.safeEntries {
                entry.problem = keeper
            }
            context.delete(duplicate)
            didChange = true
        }
    }

    if didChange {
        try? context.save()
    }
}

/// Whether the user has changed a seeded default from how it was seeded.
func isCustomizedDefault(_ problem: SiteProblem) -> Bool {
    guard let original = DefaultProblems.all.first(where: { $0.key == problem.defaultKey }) else {
        return false
    }
    return !problem.isEnabled || problem.name != original.name || problem.emoji != original.emoji
}

private func isPreferredDuplicateKeeper(_ lhs: SiteProblem, _ rhs: SiteProblem) -> Bool {
    let lhsCustomized = isCustomizedDefault(lhs)
    let rhsCustomized = isCustomizedDefault(rhs)
    if lhsCustomized != rhsCustomized { return lhsCustomized }
    return lhs.id.uuidString < rhs.id.uuidString
}
