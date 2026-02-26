import Foundation
import SwiftData

private struct DefaultZone {
    let bodyPart: String
    let subArea: String?
    let hasLaterality: Bool
}

/// Seeds the default body locations into the SwiftData context on first launch.
/// Each of the 7 default zones has left/right laterality, producing 14 locations total.
@MainActor
func seedDefaultLocations(context: ModelContext) {
    let descriptor = FetchDescriptor<Location>()
    let existingCount = (try? context.fetchCount(descriptor)) ?? 0

    guard existingCount == 0 else { return }

    let defaultZones: [DefaultZone] = [
        DefaultZone(bodyPart: "Abdomen", subArea: "Front", hasLaterality: true),
        DefaultZone(bodyPart: "Abdomen", subArea: "Side", hasLaterality: true),
        DefaultZone(bodyPart: "Abdomen", subArea: "Back", hasLaterality: true),
        DefaultZone(bodyPart: "Thigh", subArea: "Front", hasLaterality: true),
        DefaultZone(bodyPart: "Thigh", subArea: "Side", hasLaterality: true),
        DefaultZone(bodyPart: "Arm", subArea: "Back", hasLaterality: true),
        DefaultZone(bodyPart: "Buttock", subArea: nil, hasLaterality: true),
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

/// Deduplicates non-custom locations that share the same semantic identity
/// (bodyPart, subArea, side). Keeps the location with the most history,
/// reassigns entries from duplicates to the keeper, then deletes duplicates.
@MainActor
func deduplicateLocations(context: ModelContext) {
    let descriptor = FetchDescriptor<Location>()
    guard let allLocations = try? context.fetch(descriptor) else { return }

    let nonCustom = allLocations.filter { !$0.isCustom }

    struct LocationKey: Hashable {
        let bodyPart: String
        let subArea: String?
        let side: String?
    }

    var groups: [LocationKey: [Location]] = [:]
    for location in nonCustom {
        let key = LocationKey(
            bodyPart: location.bodyPart,
            subArea: location.subArea,
            side: location.side
        )
        groups[key, default: []].append(location)
    }

    var didChange = false
    for (_, locations) in groups where locations.count > 1 {
        let sorted = locations.sorted { lhs, rhs in
            let lhsCount = lhs.safeEntries.count
            let rhsCount = rhs.safeEntries.count
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.sortOrder < rhs.sortOrder
        }

        guard let keeper = sorted.first else { continue }

        for duplicate in sorted.dropFirst() {
            for entry in duplicate.safeEntries {
                entry.location = keeper
            }
            if duplicate.isEnabled {
                keeper.isEnabled = true
            }
            context.delete(duplicate)
            didChange = true
        }
    }

    if didChange {
        try? context.save()
    }
}

/// Migrates existing locations that have a `zone` but empty `bodyPart`.
/// Parses zone string: last word → bodyPart, remaining words → subArea.
@MainActor
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
