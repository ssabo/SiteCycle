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

/// Seeds the default body locations. Seeds only into a store with no
/// locations at all.
@MainActor
func seedDefaultLocations(context: ModelContext) {
    // A failed count must not look like an empty store, or this would seed
    // duplicates into the user's data.
    guard let existingCount = try? context.fetchCount(FetchDescriptor<Location>()),
          existingCount == 0 else { return }

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
/// Only entries already on this device can be moved, so on a CloudKit store
/// this must run only after an import (see `StoreMaintenancePolicy`).
///
/// The user's settings are then merged onto the keeper (see
/// `mergeUserSettings(from:into:disabledWins:)`), so keeping a freshly seeded
/// copy doesn't undo them.
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

    let disabledWins = disabledCopiesCanWin(merges: merges, allLocations: allLocations)
    for copies in merges {
        guard let keeper = copies.first else { continue }
        let duplicates = Array(copies.dropFirst())

        mergeUserSettings(from: duplicates, into: keeper, disabledWins: disabledWins)
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

/// Whether a disabled copy may win the `isEnabled` merge. It may, unless that
/// would leave no enabled location at all, which happens when devices disabled
/// different sites before syncing. `LocationConfigView` never lets the user
/// turn off the last enabled site, so dedup mustn't either.
private func disabledCopiesCanWin(merges: [[Location]], allLocations: [Location]) -> Bool {
    let merged = Set(merges.joined().map { ObjectIdentifier($0) })
    let otherEnabled = allLocations.contains { !merged.contains(ObjectIdentifier($0)) && $0.isEnabled }
    return otherEnabled || merges.contains { copies in copies.allSatisfy(\.isEnabled) }
}

/// Copies onto the keeper any setting changed on a duplicate, judged against
/// how the copy was seeded. Reads only synced fields, so every device merging
/// the same copies gets the same result.
///
/// - `isEnabled`: a disabled copy wins. Defaults are always seeded enabled, so
///   a disabled copy records the user turning the site off (for example,
///   because of lipohypertrophy), and a fresh device's copy must not turn it
///   back on. The exception is when `disabledWins` is false: then an enabled
///   copy wins, so at least one site stays enabled.
/// - `sortOrder`: the keeper's, if it differs from its seeded index (the user
///   moved it, or a CSV restore renumbered it); otherwise the first such
///   duplicate's, so a reordered list survives a new device's seed. Values can
///   then tie with sites that had no duplicate, which affects only display order.
private func mergeUserSettings(from duplicates: [Location], into keeper: Location, disabledWins: Bool) {
    if disabledWins {
        if duplicates.contains(where: { !$0.isEnabled }) {
            keeper.isEnabled = false
        }
    } else if duplicates.contains(where: \.isEnabled) {
        keeper.isEnabled = true
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
