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
private func addEntry(to location: Location, at date: Date, active: Bool = false, context: ModelContext) {
    let entry = SiteChangeEntry(
        startTime: date,
        endTime: active ? nil : date.addingTimeInterval(1800),
        location: location
    )
    context.insert(entry)
}

@MainActor
struct SiteChangeViewModelCooldownTests {

    @Test func hotGroupSiblingIsDemoted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let abdomenFront = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let abdomenSide = Location(bodyPart: "Abdomen", subArea: "Side", side: "left", sortOrder: 1)
        let abdomenBack = Location(bodyPart: "Abdomen", subArea: "Back", side: "left", sortOrder: 2)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 3)
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 4)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 5)
        let locations = [abdomenFront, abdomenSide, abdomenBack, thigh, buttock, arm]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: abdomenFront, at: base, context: context)
        addEntry(to: abdomenSide, at: base.addingTimeInterval(-30 * 86400), context: context)
        addEntry(to: abdomenBack, at: base.addingTimeInterval(-25 * 86400), context: context)
        addEntry(to: thigh, at: base.addingTimeInterval(-3600), context: context)
        addEntry(to: buttock, at: base.addingTimeInterval(-7200), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-10 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 2
        )

        // Avoid: abdomenFront, thigh, buttock. Last 2 entries -> hot {Abdomen L, Thigh L}.
        // The stale abdomen siblings (-30d, -25d) that per-site LRU would rank first
        // sort behind the cooler arm because their group was just used.
        #expect(recs.recommended.map(\.id) == [arm.id, abdomenSide.id, abdomenBack.id])
    }

    @Test func perSiteLruWinsWhenGroupNotHot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let abdomenFront = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let abdomenSide = Location(bodyPart: "Abdomen", subArea: "Side", side: "left", sortOrder: 1)
        let abdomenBack = Location(bodyPart: "Abdomen", subArea: "Back", side: "left", sortOrder: 2)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 3)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 4)
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 5)
        let locations = [abdomenFront, abdomenSide, abdomenBack, arm, thigh, buttock]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: abdomenSide, at: base.addingTimeInterval(-30 * 86400), context: context)
        addEntry(to: abdomenBack, at: base.addingTimeInterval(-25 * 86400), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-10 * 86400), context: context)
        addEntry(to: abdomenFront, at: base.addingTimeInterval(-5 * 86400), context: context)
        addEntry(to: thigh, at: base.addingTimeInterval(-3600), context: context)
        addEntry(to: buttock, at: base, context: context)
        try context.save()

        let cooldown = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 2
        )
        let byBodyPart = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPart
        )

        // Avoid: buttock, thigh, abdomenFront. Hot (N=2): {Buttock L, Thigh L} — abdomen
        // is NOT hot (its last use was 5 days ago), so its stale sites win per-site LRU.
        #expect(cooldown.recommended.map(\.id) == [abdomenSide.id, abdomenBack.id, arm.id])
        // Contrast: byBodyPart ranks the Arm group staler than the Abdomen group, giving
        // the single arm site top priority — the per-site overuse this mode fixes.
        #expect(byBodyPart.recommended.first?.id == arm.id)
    }

    @Test func cooldownCountChangesHotWindow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let abdomenFront = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let abdomenBack = Location(bodyPart: "Abdomen", subArea: "Back", side: "left", sortOrder: 1)
        let thighFront = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 2)
        let thighBack = Location(bodyPart: "Thigh", subArea: "Back", side: "left", sortOrder: 3)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 4)
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 5)
        let flank = Location(bodyPart: "Flank", side: "left", sortOrder: 6)
        let locations = [abdomenFront, abdomenBack, thighFront, thighBack, arm, buttock, flank]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: abdomenFront, at: base, context: context)
        addEntry(to: thighFront, at: base.addingTimeInterval(-3600), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-7200), context: context)
        addEntry(to: buttock, at: base.addingTimeInterval(-10 * 86400), context: context)
        addEntry(to: flank, at: base.addingTimeInterval(-12 * 86400), context: context)
        addEntry(to: thighBack, at: base.addingTimeInterval(-15 * 86400), context: context)
        addEntry(to: abdomenBack, at: base.addingTimeInterval(-20 * 86400), context: context)
        try context.save()

        // Avoid in both cases: abdomenFront, thighFront, arm.
        let narrow = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 1
        )
        let wide = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 3
        )

        // N=1 -> only Abdomen is hot: thighBack keeps its per-site LRU lead.
        #expect(narrow.recommended.map(\.id) == [thighBack.id, flank.id, buttock.id])
        // N=3 -> Abdomen, Thigh, and Arm are hot: thighBack drops out, abdomenBack
        // only appears as a demoted third pick.
        #expect(wide.recommended.map(\.id) == [flank.id, buttock.id, abdomenBack.id])
    }

    @Test func allGroupsHotFallsBackToLruOrdering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var locations: [Location] = []
        for i in 0..<5 {
            let loc = Location(bodyPart: "Part \(i)", side: "left", sortOrder: i)
            context.insert(loc)
            locations.append(loc)
        }
        let base = Date()
        for (i, loc) in locations.enumerated() {
            addEntry(to: loc, at: base.addingTimeInterval(Double(-i) * 3600), context: context)
        }
        try context.save()

        let cooldown = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 10
        )
        let bySite = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .bySite
        )

        // Every group is hot, so the cool partition is empty and the ordering
        // degrades gracefully to plain per-site LRU — identical to By Site.
        #expect(cooldown.recommended.map(\.id) == bySite.recommended.map(\.id))
    }

    @Test func neverUsedSiteInHotGroupIsDemoted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let abdomenFront = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let abdomenBack = Location(bodyPart: "Abdomen", subArea: "Back", side: "left", sortOrder: 1)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 2)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 3)
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 4)
        let flank = Location(bodyPart: "Flank", side: "left", sortOrder: 5)
        let locations = [abdomenFront, abdomenBack, thigh, arm, buttock, flank]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: abdomenFront, at: base, context: context)
        addEntry(to: thigh, at: base.addingTimeInterval(-10 * 86400), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-20 * 86400), context: context)
        addEntry(to: buttock, at: base.addingTimeInterval(-3600), context: context)
        addEntry(to: flank, at: base.addingTimeInterval(-7200), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 1
        )

        // Avoid: abdomenFront, buttock, flank. Hot (N=1): {Abdomen L}. The never-used
        // abdomenBack loses its usual first place because its group was just used.
        #expect(recs.recommended.map(\.id) == [arm.id, thigh.id, abdomenBack.id])
    }

    @Test func activeEntryCountsTowardWindow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let abdomenFront = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let abdomenBack = Location(bodyPart: "Abdomen", subArea: "Back", side: "left", sortOrder: 1)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 2)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 3)
        let buttock = Location(bodyPart: "Buttock", side: "left", sortOrder: 4)
        let flank = Location(bodyPart: "Flank", side: "left", sortOrder: 5)
        let locations = [abdomenFront, abdomenBack, thigh, arm, buttock, flank]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: abdomenFront, at: base, active: true, context: context)
        addEntry(to: abdomenBack, at: base.addingTimeInterval(-20 * 86400), context: context)
        addEntry(to: thigh, at: base.addingTimeInterval(-15 * 86400), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-10 * 86400), context: context)
        addEntry(to: buttock, at: base.addingTimeInterval(-5 * 86400), context: context)
        addEntry(to: flank, at: base.addingTimeInterval(-2 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 1
        )

        // The active (endTime == nil) entry is the most recent, so with N=1 it alone
        // defines the hot set: {Abdomen L}. Avoid: abdomenFront, flank, buttock.
        // abdomenBack is the oldest site overall yet still sorts last.
        #expect(recs.recommended.map(\.id) == [thigh.id, arm.id, abdomenBack.id])
    }
}

@MainActor
struct SiteChangeViewModelCooldownEdgeTests {

    @Test func neverUsedGroupIsNeverHotAndSortsFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let abdomen = Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0)
        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 1)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 2)
        let flank = Location(bodyPart: "Flank", side: "left", sortOrder: 3)
        let calfNever = Location(bodyPart: "Calf", side: "left", sortOrder: 4)
        let locations = [abdomen, thigh, arm, flank, calfNever]
        locations.forEach { context.insert($0) }

        let base = Date()
        addEntry(to: abdomen, at: base, context: context)
        addEntry(to: thigh, at: base.addingTimeInterval(-1 * 86400), context: context)
        addEntry(to: arm, at: base.addingTimeInterval(-2 * 86400), context: context)
        addEntry(to: flank, at: base.addingTimeInterval(-4 * 86400), context: context)
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 2
        )

        // Avoid: abdomen, thigh, arm. Hot: {Abdomen L, Thigh L}. The never-used calf
        // belongs to an untouched group, so it keeps its usual first place.
        #expect(recs.recommended.map(\.id) == [calfNever.id, flank.id])
    }

    @Test func avoidListUnchangedAndDisjointInCooldownMode() throws {
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
        let cooldown = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: 2
        )

        #expect(cooldown.avoid.map(\.id) == bySite.avoid.map(\.id))
        #expect(cooldown.avoid.map(\.id) == byBodyPart.avoid.map(\.id))
        let avoidIds = Set(cooldown.avoid.map(\.id))
        #expect(avoidIds.isDisjoint(with: Set(cooldown.recommended.map(\.id))))
    }

    @Test func fewerThanThreeCandidates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let thigh = Location(bodyPart: "Thigh", subArea: "Front", side: "left", sortOrder: 0)
        let arm = Location(bodyPart: "Arm", subArea: "Back", side: "left", sortOrder: 1)
        let locations = [thigh, arm]
        locations.forEach { context.insert($0) }
        try context.save()

        let recs = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown
        )

        #expect(recs.recommended.count == 2)
    }

    @Test func emptyLocationsProduceEmptyCooldownRecommendations() {
        let recs = SiteChangeViewModel.computeRecommendations(
            locations: [],
            strategy: .byBodyPartCooldown
        )

        #expect(recs.avoid.isEmpty)
        #expect(recs.recommended.isEmpty)
        #expect(recs.allSorted.isEmpty)
    }

    @Test func defaultCooldownParameterIsTwo() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var locations: [Location] = []
        for i in 0..<8 {
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
            addEntry(to: loc, at: base.addingTimeInterval(Double(-i) * 86400), context: context)
        }
        try context.save()

        let defaulted = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown
        )
        let explicit = SiteChangeViewModel.computeRecommendations(
            locations: locations,
            strategy: .byBodyPartCooldown,
            cooldownCount: RecommendationStrategy.defaultCooldownCount
        )

        #expect(defaulted.recommended.map(\.id) == explicit.recommended.map(\.id))
    }

    @Test func loadCooldownCountDefaultsAndClamps() throws {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Missing key must yield the default, not integer(forKey:)'s 0 clamped to 1
        #expect(RecommendationStrategy.loadCooldownCount(from: defaults) == 2)

        defaults.set(0, forKey: RecommendationStrategy.cooldownCountKey)
        #expect(RecommendationStrategy.loadCooldownCount(from: defaults) == 1)

        defaults.set(-5, forKey: RecommendationStrategy.cooldownCountKey)
        #expect(RecommendationStrategy.loadCooldownCount(from: defaults) == 1)

        defaults.set(99, forKey: RecommendationStrategy.cooldownCountKey)
        #expect(RecommendationStrategy.loadCooldownCount(from: defaults) == 10)

        defaults.set(4, forKey: RecommendationStrategy.cooldownCountKey)
        #expect(RecommendationStrategy.loadCooldownCount(from: defaults) == 4)
    }

    @Test func strategyLoadParsesCooldownRawValue() throws {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            RecommendationStrategy.byBodyPartCooldown.rawValue,
            forKey: RecommendationStrategy.storageKey
        )
        #expect(RecommendationStrategy.load(from: defaults) == .byBodyPartCooldown)
    }
}
