import Testing
import Foundation
import SwiftData
@testable import SiteCycle

// MARK: - Shared fixtures

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Location.self, SiteChangeEntry.self])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func addEntry(to location: Location, at date: Date, context: ModelContext) {
    let entry = SiteChangeEntry(
        startTime: date,
        endTime: date.addingTimeInterval(1800),
        location: location
    )
    context.insert(entry)
}

@MainActor
struct SiteChangeViewModelStrategyTests {

    // MARK: - By Body Part: group selection

    @Test func byBodyPartPicksThreeLeastRecentlyUsedGroups() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // 6 single-site groups: Buttock L, Abdomen L/R, Thigh L/R, Arm L
        let buttockL = Location(bodyPart: "Buttock", side: "left", sortOrder: 0)
        let abdomenL = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 1)
        let abdomenR = Location(bodyPart: "Abdomen", subArea: "Front", side: "right", sortOrder: 2)
        let thighL = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 3)
        let thighR = Location(bodyPart: "Thigh", subArea: "Front", side: "right", sortOrder: 4)
        let armL = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 5)
        let locations = [buttockL, abdomenL, abdomenR, thighL, thighR, armL]
        locations.forEach { context.insert($0) }

        // Usage recency: buttockL most recent, armL oldest
        let base = Date()
        for (i, loc) in locations.enumerated() {
            addEntry(to: loc, at: base.addingTimeInterval(Double(-i) * 86400), context: context)
        }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        // Avoid (site-based) takes buttockL/abdomenL/abdomenR; the 3 stalest groups are
        // Arm L, Thigh R, Thigh L (least-recent-first order)
        #expect(recs.recommended.map(\.id) == [armL.id, thighR.id, thighL.id])
    }

    @Test func groupRecencyIsMaxAcrossGroupSites() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Abdomen L holds the single oldest site plus the newest -> group recency is "now"
        let abdomenFront = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let abdomenBack = Location(bodyPart: "Abdomen", subArea: "Back", side: "left", sortOrder: 1)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 2)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 3)
        // Recently used fillers that absorb the site-based avoid list
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 4)
        let flank = Location(bodyPart: "Flank", side: "left", sortOrder: 5)
        let locations = [abdomenFront, abdomenBack, thigh, arm, buttock, flank]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: abdomenFront, at: base.addingTimeInterval(-30 * 86400), context: context)
        addEntry(to: abdomenBack, at: base, context: context)
        addEntry(to: thigh, at: base.addingTimeInterval(-7 * 86400), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-8 * 86400), context: context)
        addEntry(to: buttock, at: base.addingTimeInterval(-1 * 86400), context: context)
        addEntry(to: flank, at: base.addingTimeInterval(-2 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        // Avoid (site-based): abdomenBack, buttock, flank. Group ranking (stalest first):
        // Arm (-8d), Thigh (-7d), Flank, Buttock, Abdomen. Abdomen ranks most recent despite
        // holding the single oldest site; abdomenFront only surfaces once staler groups
        // are exhausted (Flank/Buttock groups are fully avoided and skipped).
        #expect(recs.recommended.map(\.id) == [arm.id, thigh.id, abdomenFront.id])
    }

    @Test func fullyAvoidedSingleGroupYieldsNoRecommendations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // One group whose 3 sites are also the 3 most recently used sites overall
        let front = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let side = Location(bodyPart: "Abdomen", subArea: "Side", side: "left", sortOrder: 1)
        let back = Location(bodyPart: "Abdomen", subArea: "Back", side: "left", sortOrder: 2)
        let locations = [front, side, back]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: front, at: base.addingTimeInterval(-10 * 86400), context: context)
        addEntry(to: side, at: base.addingTimeInterval(-20 * 86400), context: context)
        addEntry(to: back, at: base.addingTimeInterval(-15 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        // All sites are in avoid, so the group has no eligible pick
        #expect(recs.avoid.count == 3)
        #expect(recs.recommended.isEmpty)
    }

    @Test func withinGroupLeastRecentlyUsedSiteWinsOverMoreRecent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Target group (Thigh L) has two sites; 4 other single-site groups absorb the avoid list
        let thighFront = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 0)
        let thighSide = Location(bodyPart: "Thigh", subArea: "Side", side: "left", sortOrder: 1)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 2)
        let abdomen = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 3)
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 4)
        let locations = [thighFront, thighSide, arm, abdomen, buttock]
        locations.forEach { context.insert($0) }

        let base = Date()
        // Most recent 3 (avoid): arm, abdomen, buttock
        addEntry(to: arm, at: base, context: context)
        addEntry(to: abdomen, at: base.addingTimeInterval(-3600), context: context)
        addEntry(to: buttock, at: base.addingTimeInterval(-7200), context: context)
        // Thigh group: front used 10 days ago, side used 20 days ago
        addEntry(to: thighFront, at: base.addingTimeInterval(-10 * 86400), context: context)
        addEntry(to: thighSide, at: base.addingTimeInterval(-20 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        // Thigh L is the stalest group (newest use 10 days ago); its LRU site is thighSide
        #expect(recs.recommended.first?.id == thighSide.id)
        #expect(!recs.recommended.contains { $0.id == thighFront.id })
    }

    @Test func neverUsedGroupSortsOldest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let usedA = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let usedB = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 1)
        let neverUsed = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 2)
        let locations = [usedA, usedB, neverUsed]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: usedA, at: base, context: context)
        addEntry(to: usedB, at: base.addingTimeInterval(-86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        #expect(recs.recommended.first?.id == neverUsed.id)
    }

    @Test func neverUsedSiteWithinGroupWins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Target group has a used site and a never-used site; fillers absorb avoid
        let thighUsed = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 0)
        let thighNever = Location(bodyPart: "Thigh", subArea: "Side", side: "left", sortOrder: 1)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 2)
        let abdomen = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 3)
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 4)
        let locations = [thighUsed, thighNever, arm, abdomen, buttock]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: arm, at: base, context: context)
        addEntry(to: abdomen, at: base.addingTimeInterval(-3600), context: context)
        addEntry(to: buttock, at: base.addingTimeInterval(-7200), context: context)
        addEntry(to: thighUsed, at: base.addingTimeInterval(-30 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        #expect(recs.recommended.first?.id == thighNever.id)
    }

    @Test func withinGroupTieBrokenByLowestSortOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Two never-used sites in the same group, higher sortOrder listed first
        let thighSide = Location(bodyPart: "Thigh", subArea: "Side", side: "left", sortOrder: 5)
        let thighFront = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 2)
        let locations = [thighSide, thighFront]
        locations.forEach { context.insert($0) }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        #expect(recs.recommended.first?.id == thighFront.id)
        #expect(recs.recommended.count == 1)
    }

    @Test func neverUsedGroupTieBrokenByLowestSortOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Three never-used single-site groups with shuffled sortOrders
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 7)
        let abdomen = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 3)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 5)
        let locations = [arm, abdomen, thigh]
        locations.forEach { context.insert($0) }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        #expect(recs.recommended.map(\.id) == [abdomen.id, thigh.id, arm.id])
    }
}

@MainActor
struct SiteChangeViewModelStrategyEdgeTests {

    // MARK: - Avoid interplay

    @Test func avoidListUnchangedInByBodyPartMode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var locations: [Location] = []
        for i in 0..<6 {
            let loc = Location(
                bodyPart: "Part \(i / 2)",
                subArea: "Sub \(i % 2)",
                side: "left",
                sortOrder: i
            )
            context.insert(loc)
            locations.append(loc)
        }
        let base = Date()
        for (i, loc) in locations.enumerated() {
            addEntry(to: loc, at: base.addingTimeInterval(Double(-i) * 3600), context: context)
        }
        try context.save()

        let bySite = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .bySite
        )
        let byBodyPart = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        #expect(bySite.avoid.map(\.id) == byBodyPart.avoid.map(\.id))
    }

    @Test func avoidSitesExcludedFromGroupPicks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Stalest group's only site is also in avoid (few sites overall)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 0)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 1)
        let abdomen = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 2)
        let neverUsed = Location(bodyPart: "Buttock", side: "left", sortOrder: 3)
        let locations = [thigh, arm, abdomen, neverUsed]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: thigh, at: base.addingTimeInterval(-3 * 86400), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-2 * 86400), context: context)
        addEntry(to: abdomen, at: base.addingTimeInterval(-1 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        // thigh/arm/abdomen are the 3 most recently used -> avoid; their groups yield no picks
        #expect(recs.recommended.map(\.id) == [neverUsed.id])
        let avoidIds = Set(recs.avoid.map(\.id))
        let recIds = Set(recs.recommended.map(\.id))
        #expect(avoidIds.isDisjoint(with: recIds))
    }

    // MARK: - Edge cases

    @Test func fewerThanThreeGroupsHandledGracefully() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let thighL = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 0)
        let thighR = Location(bodyPart: "Thigh", subArea: "Front", side: "right", sortOrder: 1)
        let locations = [thighL, thighR]
        locations.forEach { context.insert($0) }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        #expect(recs.recommended.count == 2)
    }

    @Test func emptyLocationsProduceEmptyByBodyPartRecommendations() {
        let recs = SiteChangeViewModel.computeRecommendations(
            locations: [],
            strategy: .byBodyPart
        )

        #expect(recs.avoid.isEmpty)
        #expect(recs.recommended.isEmpty)
        #expect(recs.allSorted.isEmpty)
    }

    @Test func allSortedIdenticalAcrossStrategies() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let locB = Location(bodyPart: "Bravo", sortOrder: 1)
        let locA = Location(bodyPart: "Alpha", sortOrder: 0)
        let locations = [locB, locA]
        locations.forEach { context.insert($0) }
        try context.save()

        let bySite = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .bySite
        )
        let byBodyPart = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        #expect(bySite.allSorted.map(\.id) == byBodyPart.allSorted.map(\.id))
    }

    // MARK: - Defaults

    @Test func defaultParameterMatchesBySiteStrategy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var locations: [Location] = []
        for i in 0..<6 {
            let loc = Location(bodyPart: "Zone \(i)", sortOrder: i)
            context.insert(loc)
            locations.append(loc)
        }
        let base = Date()
        for (i, loc) in locations.enumerated() {
            addEntry(to: loc, at: base.addingTimeInterval(Double(-i) * 3600), context: context)
        }
        try context.save()

        let defaulted = SiteChangeViewModel.computeRecommendations(locations: locations)
        let explicit = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .bySite
        )

        #expect(defaulted.recommended.map(\.id) == explicit.recommended.map(\.id))
        #expect(defaulted.avoid.map(\.id) == explicit.avoid.map(\.id))
    }

    @Test func strategyLoadDefaultsToBySiteWhenKeyMissingOrInvalid() throws {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(RecommendationStrategy.load(from: defaults) == .bySite)

        defaults.set("garbage", forKey: RecommendationStrategy.storageKey)
        #expect(RecommendationStrategy.load(from: defaults) == .bySite)

        defaults.set(RecommendationStrategy.byBodyPart.rawValue, forKey: RecommendationStrategy.storageKey)
        #expect(RecommendationStrategy.load(from: defaults) == .byBodyPart)
    }
}
