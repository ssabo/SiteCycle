import Foundation
import SwiftData

@Model
final class Location {
    var id: UUID
    var zone: String
    var side: String?
    var isEnabled: Bool
    var isCustom: Bool
    var sortOrder: Int

    @Relationship(deleteRule: .nullify, inverse: \SiteChangeEntry.location)
    var entries: [SiteChangeEntry] = []

    var sideLabel: String? {
        guard let side else { return nil }
        return side == "left" ? "L" : "R"
    }

    private var invertedZone: String {
        let words = zone.split(separator: " ").map(String.init)
        guard words.count >= 2, let lastWord = words.last else { return zone }
        let qualifier = words.dropLast().joined(separator: " ")
        return "\(lastWord) - \(qualifier)"
    }

    var displayName: String { invertedZone }

    var fullDisplayName: String {
        if let sideLabel { return "\(sideLabel) \(displayName)" }
        return displayName
    }

    init(
        id: UUID = UUID(),
        zone: String,
        side: String? = nil,
        isEnabled: Bool = true,
        isCustom: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.zone = zone
        self.side = side
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.sortOrder = sortOrder
    }
}
