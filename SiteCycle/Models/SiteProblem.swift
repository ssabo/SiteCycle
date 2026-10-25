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

    /// Reduces typed text to a single emoji: the last emoji typed, so typing a
    /// new emoji after the old one replaces it. Anything that isn't an emoji
    /// (letters, digits, whitespace) is dropped.
    static func sanitizeEmoji(_ text: String) -> String {
        guard let last = text.last(where: isEmoji) else { return "" }
        return String(last)
    }

    /// Emoji-presentation characters (😀, 🩹), or emoji sequences such as
    /// "❤️" (text-style base + variation selector), keycaps and skin tones.
    /// Plain "1" or "#" have the Emoji property but render as text, so a lone
    /// scalar only counts when it has emoji presentation by default.
    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation || scalars.count > 1
    }

    /// Whether `name` (trimmed, case-insensitive) is already used by another
    /// problem. Names identify problems in CSV import/export, so they must be unique.
    static func isNameTaken(_ name: String, among problems: [SiteProblem], excluding: SiteProblem? = nil) -> Bool {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return problems.contains { problem in
            problem.id != excluding?.id
                && problem.name.trimmingCharacters(in: .whitespaces).lowercased() == key
        }
    }

    /// Enabled problems in display order, plus any `retained` problems even when
    /// disabled — an entry's original problem must stay pickable after the user
    /// moves the selection away from it.
    static func pickerOptions(from problems: [SiteProblem], including retained: SiteProblem?...) -> [SiteProblem] {
        var options = problems.filter(\.isEnabled)
        for problem in retained.compactMap({ $0 }) where !options.contains(where: { $0.id == problem.id }) {
            options.append(problem)
        }
        return options.sorted { $0.sortOrder < $1.sortOrder }
    }
}
