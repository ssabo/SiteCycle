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

    var displayName: String {
        if let side = side {
            let sidePrefix = side == "left" ? "Left" : "Right"
            return "\(sidePrefix) \(zone)"
        }
        return zone
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
