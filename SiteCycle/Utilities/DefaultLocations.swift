import Foundation
import SwiftData

/// A location the app seeds. Its index in `DefaultLocations.all` is the
/// `sortOrder` it is seeded with.
struct DefaultLocation: Sendable {
    let bodyPart: String
    let subArea: String?
    let side: String?
}

enum DefaultLocations {
    /// Seeded in this order: 7 zones, each left then right, 14 locations in all.
    static let all: [DefaultLocation] = zones.flatMap { zone in
        ["left", "right"].map { side in
            DefaultLocation(bodyPart: zone.bodyPart, subArea: zone.subArea, side: side)
        }
    }

    /// Append new zones at the end; never reorder, insert or remove one. Dedup
    /// compares each copy's `sortOrder` with its index here to tell whether it
    /// was moved, so shifting an existing index makes untouched copies look moved.
    private static let zones: [(bodyPart: String, subArea: String?)] = [
        ("Abdomen", "Front"),
        ("Abdomen", "Side"),
        ("Abdomen", "Back"),
        ("Thigh", "Front"),
        ("Thigh", "Side"),
        ("Arm", "Back"),
        ("Buttock", nil),
    ]

    /// The `sortOrder` a fresh seed gives this location, or nil if it is custom
    /// or not one of the current defaults.
    static func seededSortOrder(of location: Location) -> Int? {
        guard !location.isCustom else { return nil }
        return all.firstIndex {
            $0.bodyPart == location.bodyPart && $0.subArea == location.subArea && $0.side == location.side
        }
    }
}

/// Seeds the default body locations into a store that has none.
///
/// Custom zones don't count: on an iCloud store, seeding waits for the first
/// download, so onboarding can show the location list before it runs, and a
/// custom zone added then must not stop the defaults from ever being seeded. The user can only
/// disable a default, not delete it, so this normally seeds once per store;
/// a CSV restore that names no default site brings the defaults back.
@MainActor
func seedDefaultLocations(context: ModelContext) {
    // A failed fetch must not look like an empty store, or this would seed
    // duplicates into the user's data.
    guard let existing = try? context.fetch(FetchDescriptor<Location>()),
          !existing.contains(where: { !$0.isCustom }) else { return }

    // Defaults keep their seeded indexes, which dedup relies on, so any custom
    // zones move after them.
    for location in existing {
        location.sortOrder += DefaultLocations.all.count
    }
    for (index, location) in DefaultLocations.all.enumerated() {
        context.insert(Location(
            bodyPart: location.bodyPart,
            subArea: location.subArea,
            side: location.side,
            isEnabled: true,
            isCustom: false,
            sortOrder: index
        ))
    }

    try? context.save()
}

/// Merges non-custom locations that share `(bodyPart, subArea, side)`, moving
/// their entries onto one keeper. Duplicates arise when two devices both seed
/// the defaults before CloudKit syncs.
///
/// The keeper must be the same on every device, or two devices deduplicating
/// before syncing could each delete the copy the other kept (CLAUDE.md rule 3).
/// So the keeper is the lowest `id`. Entry counts are not used, because entry
/// links sync separately and can differ between devices meanwhile, and seeded
/// copies all tie on `sortOrder`.
///
/// Only entries already on this device can be moved. That is why an iCloud
/// store doesn't seed its defaults until its first download (see
/// `StoreMaintenanceCoordinator`): a new phone's own copies would otherwise be
/// merged with the user's before their history arrived.
///
/// The user's settings are then merged onto the keeper (see
/// `mergeUserSettings(from:into:)`), so keeping a freshly seeded copy doesn't
/// undo them.
///
/// Rows that `migrateLocationBodyParts` hasn't filled in yet (empty `bodyPart`)
/// are skipped: they can't be told apart, so grouping them would merge every
/// legacy left site into one.
@MainActor
func deduplicateLocations(context: ModelContext) {
    guard let allLocations = try? context.fetch(FetchDescriptor<Location>()) else { return }

    var groups: [LocationKey: [Location]] = [:]
    for location in allLocations where !location.isCustom && !location.bodyPart.isEmpty {
        let key = LocationKey(bodyPart: location.bodyPart, subArea: location.subArea, side: location.side)
        groups[key, default: []].append(location)
    }

    // Each group in id order, so its first copy is the keeper.
    let merges = groups.values
        .filter { $0.count > 1 }
        .map { copies in copies.sorted { $0.id.uuidString < $1.id.uuidString } }
    guard !merges.isEmpty else { return }

    for copies in merges {
        guard let keeper = copies.first else { continue }
        let duplicates = Array(copies.dropFirst())

        mergeUserSettings(from: duplicates, into: keeper)
        for duplicate in duplicates {
            for entry in duplicate.safeEntries {
                entry.location = keeper
            }
            context.delete(duplicate)
        }
    }

    try? context.save()
}

private struct LocationKey: Hashable {
    let bodyPart: String
    let subArea: String?
    let side: String?
}

/// Copies onto the keeper any setting changed on a duplicate, judged against
/// how the copy was seeded. Reads only synced fields, so every device merging
/// the same copies gets the same result.
///
/// - `isEnabled`: a disabled copy wins. Defaults are always seeded enabled, so
///   a disabled copy records the user turning the site off (for example,
///   because of lipohypertrophy), and a fresh device's copy must not turn it
///   back on.
/// - `sortOrder`: the keeper's, if it differs from its seeded index (the user
///   moved it, or a CSV restore renumbered it); otherwise the first such
///   duplicate's, so a reordered list survives a new device's seed. Values can
///   then tie with sites that had no duplicate, which affects only display order.
private func mergeUserSettings(from duplicates: [Location], into keeper: Location) {
    if duplicates.contains(where: { !$0.isEnabled }) {
        keeper.isEnabled = false
    }

    if let seeded = DefaultLocations.seededSortOrder(of: keeper),
       keeper.sortOrder == seeded,
       let moved = duplicates.first(where: { $0.sortOrder != seeded }) {
        keeper.sortOrder = moved.sortOrder
    }
}

/// Deduplicates SiteChangeEntry records that share the same startTime,
/// endTime, location, and note. Keeps one entry and deletes the rest.
@MainActor
func deduplicateSiteChangeEntries(context: ModelContext) {
    let descriptor = FetchDescriptor<SiteChangeEntry>()
    guard let allEntries = try? context.fetch(descriptor) else { return }
    guard allEntries.count > 1 else { return }

    struct EntryKey: Hashable {
        let startTime: Date
        let endTime: Date?
        let locationID: PersistentIdentifier?
        let note: String?
    }

    var groups: [EntryKey: [SiteChangeEntry]] = [:]
    for entry in allEntries {
        let key = EntryKey(
            startTime: entry.startTime,
            endTime: entry.endTime,
            locationID: entry.location?.persistentModelID,
            note: entry.note
        )
        groups[key, default: []].append(entry)
    }

    var didChange = false
    for (_, entries) in groups where entries.count > 1 {
        // Lowest id, not fetch order: every device must keep the same copy, or
        // two devices deduplicating before syncing could each delete the copy
        // the other kept and lose the entry entirely.
        let sorted = entries.sorted { $0.id.uuidString < $1.id.uuidString }
        guard let keeper = sorted.first else { continue }
        for duplicate in sorted.dropFirst() {
            // Problems may have been set on only one copy (e.g. from History);
            // keep them rather than losing them with the deleted duplicate.
            var problems = keeper.problems ?? []
            for problem in duplicate.problems ?? [] where !problems.contains(where: { $0.id == problem.id }) {
                problems.append(problem)
            }
            if problems.count != (keeper.problems ?? []).count {
                keeper.problems = problems
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
