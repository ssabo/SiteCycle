import Foundation
import SwiftData

/// Seeds the default body locations into the SwiftData context on first launch.
/// Each of the 7 default zones has left/right laterality, producing 14 locations total.
func seedDefaultLocations(context: ModelContext) {
    let descriptor = FetchDescriptor<Location>()
    let existingCount = (try? context.fetchCount(descriptor)) ?? 0

    guard existingCount == 0 else { return }

    let defaultZones: [(zone: String, hasLaterality: Bool)] = [
        ("Front Abdomen", true),
        ("Side Abdomen", true),
        ("Back Abdomen", true),
        ("Front Thigh", true),
        ("Side Thigh", true),
        ("Back Arm", true),
        ("Buttock", true),
    ]

    var sortOrder = 0

    for zoneInfo in defaultZones {
        if zoneInfo.hasLaterality {
            let leftLocation = Location(
                zone: zoneInfo.zone,
                side: "left",
                isEnabled: true,
                isCustom: false,
                sortOrder: sortOrder
            )
            context.insert(leftLocation)
            sortOrder += 1

            let rightLocation = Location(
                zone: zoneInfo.zone,
                side: "right",
                isEnabled: true,
                isCustom: false,
                sortOrder: sortOrder
            )
            context.insert(rightLocation)
            sortOrder += 1
        } else {
            let location = Location(
                zone: zoneInfo.zone,
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
