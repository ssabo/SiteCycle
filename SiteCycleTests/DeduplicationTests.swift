import Testing
import Foundation
import SwiftData
@testable import SiteCycle

/// Every order the three copies in a test can be inserted in. A keeper chosen
/// by fetch order would differ between some of them.
private let insertionOrders: [[Int]] = [
    [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0],
]

/// Dedup runs on each device before CloudKit has synced, so every device must
/// keep the same copy (CLAUDE.md rule 3). These tests pin the keeper of each
/// dedup function to the lowest `id`, whatever the insertion order.
@MainActor
struct DeduplicationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Three fixed ids, in ascending `uuidString` order.
    private func fixedIDs() throws -> [UUID] {
        var ids: [UUID] = []
        for string in [
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002",
            "FFFFFFFF-0000-0000-0000-000000000000",
        ] {
            let id = try #require(UUID(uuidString: string))
            ids.append(id)
        }
        return ids
    }

    /// Pass a fresh `ModelContext(container)`, which sees only what was saved.
    private func fetchLocations(_ context: ModelContext) throws -> [Location] {
        try context.fetch(FetchDescriptor<Location>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    // MARK: - Keeper is the same on every device

    @Test(arguments: insertionOrders)
    func locationKeeperIsLowestIDWhateverTheOrderOrEntryCounts(order: [Int]) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        // The same seeded default from three devices. The highest id has the
        // most history, so a keeper chosen by entry count would pick it.
        let copies = ids.map { Location(id: $0, bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0) }
        for index in order {
            context.insert(copies[index])
        }
        let start = Date(timeIntervalSince1970: 1_000_000)
        for (index, copy) in copies.enumerated() {
            for offset in 0..<index {
                let hours = Double(index * 10 + offset) * 72
                context.insert(SiteChangeEntry(startTime: start.addingTimeInterval(hours * 3600), location: copy))
            }
        }
        try context.save()

        deduplicateLocations(context: context)

        #expect(!context.hasChanges)
        let fresh = ModelContext(container)
        let survivors = try fetchLocations(fresh)
        #expect(survivors.map(\.id) == [ids[0]])
        #expect(survivors.first?.safeEntries.count == 3)
    }

    @Test(arguments: insertionOrders)
    func entryKeeperIsLowestIDWhateverTheOrder(order: [Int]) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        let start = Date(timeIntervalSince1970: 1_000_000)
        let copies = ids.map { SiteChangeEntry(id: $0, startTime: start, note: "same") }
        for index in order {
            context.insert(copies[index])
        }
        try context.save()

        deduplicateSiteChangeEntries(context: context)

        let fresh = ModelContext(container)
        let survivors = try fresh.fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(survivors.map(\.id) == [ids[0]])
    }

    @Test(arguments: insertionOrders)
    func problemKeeperIsLowestIDWhateverTheOrder(order: [Int]) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        // Pristine copies of Leaking (seeded at index 1), so only the id decides.
        let copies = ids.map {
            SiteProblem(id: $0, name: "Leaking", emoji: "💧", sortOrder: 1, defaultKey: "leaking")
        }
        for index in order {
            context.insert(copies[index])
        }
        try context.save()

        deduplicateProblems(context: context)

        let fresh = ModelContext(container)
        let survivors = try fresh.fetch(FetchDescriptor<SiteProblem>())
        #expect(survivors.map(\.id) == [ids[0]])
    }

    // MARK: - Location settings merge

    /// The copy the user turned off is either the keeper (lowest id) or a
    /// duplicate. The other copies were freshly seeded, so they are enabled.
    @Test(arguments: [0, 2])
    func locationDedupKeepsASiteTheUserDisabled(disabledIndex: Int) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        // R Thigh (Side) is seeded at sortOrder 9.
        for (index, id) in ids.enumerated() {
            context.insert(Location(
                id: id,
                bodyPart: "Thigh",
                subArea: "Side",
                side: "right",
                isEnabled: index != disabledIndex,
                sortOrder: 9
            ))
        }
        try context.save()

        deduplicateLocations(context: context)

        let fresh = ModelContext(container)
        let survivors = try fetchLocations(fresh)
        #expect(survivors.map(\.id) == [ids[0]])
        #expect(survivors.first?.isEnabled == false)
    }

    /// L Arm (Back) is seeded at sortOrder 10. The keeper (lowest id) either
    /// still has that, or the user moved it to 3. The user moved the other
    /// copy to 0. A moved keeper keeps its own order; a pristine one takes the
    /// duplicate's.
    @Test(arguments: zip([10, 3], [0, 3]))
    func locationDedupKeepsTheUsersOrder(keeperSortOrder: Int, expectedSortOrder: Int) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        context.insert(Location(id: ids[2], bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 0))
        context.insert(Location(id: ids[0], bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: keeperSortOrder))
        try context.save()

        deduplicateLocations(context: context)

        let fresh = ModelContext(container)
        let survivors = try fetchLocations(fresh)
        #expect(survivors.map(\.id) == [ids[0]])
        #expect(survivors.first?.sortOrder == expectedSortOrder)
    }

    /// L Arm (Back) is seeded at 10 and the keeper still has that. Both other
    /// copies were moved, so the lower id of the two decides, whatever the order.
    @Test(arguments: insertionOrders)
    func locationDedupTakesTheFirstMovedDuplicatesOrder(order: [Int]) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        let sortOrders = [10, 4, 0]
        let copies = zip(ids, sortOrders).map { pair in
            Location(id: pair.0, bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: pair.1)
        }
        for index in order {
            context.insert(copies[index])
        }
        try context.save()

        deduplicateLocations(context: context)

        let fresh = ModelContext(container)
        let survivors = try fetchLocations(fresh)
        #expect(survivors.map(\.id) == [ids[0]])
        #expect(survivors.first?.sortOrder == 4)
    }

    /// A non-custom site that isn't a current default, as a CSV restore can
    /// create, has no seeded index to compare with, so the keeper keeps its own.
    @Test func locationDedupKeepsTheOrderOfASiteWithNoSeededIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        context.insert(Location(id: ids[2], bodyPart: "Arm", subArea: "Upper", side: "left", sortOrder: 3))
        context.insert(Location(id: ids[0], bodyPart: "Arm", subArea: "Upper", side: "left", sortOrder: 20))
        try context.save()

        deduplicateLocations(context: context)

        let fresh = ModelContext(container)
        let survivors = try fetchLocations(fresh)
        #expect(survivors.map(\.id) == [ids[0]])
        #expect(survivors.first?.sortOrder == 20)
    }

    /// Dedup reads a default's index in `DefaultLocations.all` as its seeded
    /// `sortOrder`, so existing defaults must never move. New ones may only be
    /// appended, which this allows.
    @Test func existingDefaultsKeepTheirSeededIndexes() {
        let seeded = DefaultLocations.all.prefix(14).map { location in
            [location.side, location.bodyPart, location.subArea].compactMap { $0 }.joined(separator: " ")
        }
        #expect(seeded == [
            "left Abdomen Front", "right Abdomen Front",
            "left Abdomen Side", "right Abdomen Side",
            "left Abdomen Back", "right Abdomen Back",
            "left Thigh Front", "right Thigh Front",
            "left Thigh Side", "right Thigh Side",
            "left Arm Back", "right Arm Back",
            "left Buttock", "right Buttock",
        ])
    }

    // MARK: - Legacy rows

    /// Builds a row as it was before the `bodyPart` migration: only `zone` is set.
    private func legacyLocation(id: UUID, zone: String, sortOrder: Int) -> Location {
        let location = Location(id: id, bodyPart: "", side: "left", sortOrder: sortOrder)
        location.zone = zone
        return location
    }

    @Test func locationDedupSkipsRowsNotYetMigrated() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        // Both have an empty bodyPart and the same side, but they are different sites.
        context.insert(legacyLocation(id: ids[0], zone: "Front Abdomen", sortOrder: 0))
        context.insert(legacyLocation(id: ids[1], zone: "Side Abdomen", sortOrder: 2))
        try context.save()

        deduplicateLocations(context: context)

        let fresh = ModelContext(container)
        let survivors = try fetchLocations(fresh)
        #expect(survivors.map(\.id) == [ids[0], ids[1]])
    }

    @Test func prepareStoreMigratesLegacyRowsBeforeMergingThem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ids = try fixedIDs()

        // A legacy store with two copies of left Front Abdomen and one left Side Abdomen.
        context.insert(legacyLocation(id: ids[2], zone: "Front Abdomen", sortOrder: 0))
        context.insert(legacyLocation(id: ids[1], zone: "Side Abdomen", sortOrder: 2))
        context.insert(legacyLocation(id: ids[0], zone: "Front Abdomen", sortOrder: 0))
        try context.save()

        prepareStore(context: context)

        let fresh = ModelContext(container)
        let survivors = try fetchLocations(fresh)
        #expect(survivors.map(\.id) == [ids[0], ids[1]])
        #expect(survivors.map(\.fullDisplayName) == ["L Abdomen (Front)", "L Abdomen (Side)"])
    }
}
