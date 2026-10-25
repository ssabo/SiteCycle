import Foundation
import SwiftData

/// A reason a site was changed early (e.g. painful, leaking, fell off).
/// Defaults are seeded on first launch like locations; users can rename them,
/// change their emoji, disable them, and add their own.
@Model
final class SiteProblem {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = ""
    var isEnabled: Bool = true
    var isCustom: Bool = false
    var sortOrder: Int = 0
    /// Stable identity for a seeded default, so duplicates created by seeding
    /// on two devices before CloudKit syncs can be merged even after the user
    /// renames one. Nil for custom problems.
    var defaultKey: String?

    @Relationship(deleteRule: .nullify, inverse: \SiteChangeEntry.problem)
    var entries: [SiteChangeEntry]?

    /// Non-optional convenience accessor. To modify, set `entry.problem` on the SiteChangeEntry side.
    var safeEntries: [SiteChangeEntry] {
        entries ?? []
    }

    /// Used when the user clears the emoji field or a problem arrives from CSV.
    static let fallbackEmoji = "⚠️"

    var displayEmoji: String {
        emoji.isEmpty ? Self.fallbackEmoji : emoji
    }

    var labelText: String {
        "\(displayEmoji) \(name)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        isEnabled: Bool = true,
        isCustom: Bool = false,
        sortOrder: Int = 0,
        defaultKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.sortOrder = sortOrder
        self.defaultKey = defaultKey
    }

    /// Reduces typed text to a single emoji: the last grapheme cluster, so
    /// typing a new emoji after the old one replaces it. Whitespace is ignored.
    static func sanitizeEmoji(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "" }
        return String(last)
    }

    /// Enabled problems in display order, plus `including` when it is disabled,
    /// so a picker for an entry that already uses a disabled problem still shows it.
    static func pickerOptions(from problems: [SiteProblem], including current: SiteProblem?) -> [SiteProblem] {
        var options = problems.filter(\.isEnabled)
        if let current, !options.contains(where: { $0.id == current.id }) {
            options.append(current)
        }
        return options.sorted { $0.sortOrder < $1.sortOrder }
    }
}
