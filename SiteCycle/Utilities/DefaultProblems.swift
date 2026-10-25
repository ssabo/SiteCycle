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
/// both seed before CloudKit syncs. Keeps the one with the most history and
/// moves the other entries onto it.
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
        let sorted = group.sorted { lhs, rhs in
            let lhsCount = lhs.safeEntries.count
            let rhsCount = rhs.safeEntries.count
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.sortOrder < rhs.sortOrder
        }
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
