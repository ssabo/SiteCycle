import Foundation
import SwiftData

@Model
final class Location {
    var id: UUID
    var zone: String
    var bodyPart: String = ""
    var subArea: String?
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

    var displayName: String {
        if let subArea { return "\(bodyPart) (\(subArea))" }
        return bodyPart
    }

    var fullDisplayName: String {
        if let sideLabel { return "\(sideLabel) \(displayName)" }
        return displayName
    }

    init(
        id: UUID = UUID(),
        bodyPart: String,
        subArea: String? = nil,
        side: String? = nil,
        isEnabled: Bool = true,
        isCustom: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.bodyPart = bodyPart
        self.subArea = subArea
        self.zone = [subArea, bodyPart].compactMap { $0 }.joined(separator: " ")
        self.side = side
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.sortOrder = sortOrder
    }
}
