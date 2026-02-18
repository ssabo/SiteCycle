import Foundation
import SwiftData

/// Seeds the default body locations into the SwiftData context on first launch.
/// Each of the 7 default zones has left/right laterality, producing 14 locations total.
func seedDefaultLocations(context: ModelContext) {
    let descriptor = FetchDescriptor<Location>()
    let existingCount = (try? context.fetchCount(descriptor)) ?? 0

    guard existingCount == 0 else { return }

    let defaultZones: [(bodyPart: String, subArea: String?, hasLaterality: Bool)] = [
        ("Abdomen", "Front", true),
        ("Abdomen", "Side", true),
        ("Abdomen", "Back", true),
        ("Thigh", "Front", true),
        ("Thigh", "Side", true),
        ("Arm", "Back", true),
        ("Buttock", nil, true),
    ]

    var sortOrder = 0

    for zoneInfo in defaultZones {
        if zoneInfo.hasLaterality {
            let leftLocation = Location(
                bodyPart: zoneInfo.bodyPart,
                subArea: zoneInfo.subArea,
                side: "left",
                isEnabled: true,
                isCustom: false,
                sortOrder: sortOrder
            )
            context.insert(leftLocation)
            sortOrder += 1

            let rightLocation = Location(
                bodyPart: zoneInfo.bodyPart,
                subArea: zoneInfo.subArea,
                side: "right",
                isEnabled: true,
                isCustom: false,
                sortOrder: sortOrder
            )
            context.insert(rightLocation)
            sortOrder += 1
        } else {
            let location = Location(
                bodyPart: zoneInfo.bodyPart,
                subArea: zoneInfo.subArea,
                side: nil,
                isEnabled: true,
                isCustom: false,
                sortOrder: sortOrder
            )
            context.insert(location)
            sortOrder += 1
        }
    }

    try? context.save()
}

/// Migrates existing locations that have a `zone` but empty `bodyPart`.
/// Parses zone string: last word → bodyPart, remaining words → subArea.
func migrateLocationBodyParts(context: ModelContext) {
    let descriptor = FetchDescriptor<Location>()
    guard let locations = try? context.fetch(descriptor) else { return }

    var migrated = false
    for location in locations where location.bodyPart.isEmpty {
        let words = location.zone.split(separator: " ").map(String.init)
        if let lastWord = words.last {
            location.bodyPart = lastWord
            if words.count >= 2 {
                location.subArea = words.dropLast().joined(separator: " ")
            }
            migrated = true
        }
    }

    if migrated {
        try? context.save()
    }
}
