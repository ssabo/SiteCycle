import Foundation
import SwiftData
import Testing
@testable import SiteCycle

/// Pins when `StoreMaintenanceCoordinator` seeds and merges (review §2.3). On
/// an iCloud store, a new phone must not seed its own copies of the defaults
/// before its first download, or merging them could delete the user's copies
/// whose history hasn't arrived yet.
@MainActor
struct StoreMaintenanceCoordinatorTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A store with two copies of the same default, as two devices make.
    private func makeStoreWithDuplicates() throws -> ModelContainer {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0))
        context.insert(Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0))
        try context.save()
        return container
    }

    /// A coordinator that never hears real CloudKit events and has no
    /// fallback timer, so a test drives it only through `importDidSucceed()`.
    private func makeCoordinator() -> StoreMaintenanceCoordinator {
        StoreMaintenanceCoordinator(fallbackDelay: nil, observesCloudKit: false)
    }

    private func locationCount(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<Location>())
    }

    private func problemCount(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<SiteProblem>())
    }

    @Test func aLocalStoreSeedsAndMergesAtStart() throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator()

        coordinator.start(context: ModelContext(container), isCloudKitEnabled: false)

        #expect(try locationCount(container) == 1)
        #expect(try problemCount(container) == DefaultProblems.all.count)
    }

    @Test func anICloudStoreMergesAtStartButDoesNotSeed() throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator()

        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)

        #expect(try locationCount(container) == 1)
        #expect(try problemCount(container) == 0)
    }

    @Test func anICloudStoreSeedsAfterItsFirstDownload() throws {
        let container = try makeContainer()
        let coordinator = makeCoordinator()
        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)
        #expect(try locationCount(container) == 0)

        coordinator.importDidSucceed()

        #expect(try locationCount(container) == DefaultLocations.all.count)
        #expect(try problemCount(container) == DefaultProblems.all.count)
    }

    /// The new-phone case: the download brought the user's own sites, so
    /// nothing is seeded and there is nothing to merge.
    @Test func aDownloadWithTheUsersSitesSeedsNoLocations() throws {
        let container = try makeContainer()
        let coordinator = makeCoordinator()
        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)

        // What the download brought.
        let context = ModelContext(container)
        context.insert(Location(bodyPart: "Thigh", subArea: "Side", side: "right", sortOrder: 0))
        try context.save()
        coordinator.importDidSucceed()

        #expect(try locationCount(container) == 1)
    }

    /// CloudKit can finish its first download before the first window appears.
    @Test func aDownloadBeforeStartSeedsAtStart() throws {
        let container = try makeContainer()
        let coordinator = makeCoordinator()

        coordinator.importDidSucceed()
        #expect(try locationCount(container) == 0)

        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)
        #expect(try locationCount(container) == DefaultLocations.all.count)
    }

    /// Offline, or no iCloud account: no download succeeds, so seed anyway.
    @Test func theFallbackSeedsWhenNoDownloadSucceeds() async throws {
        let container = try makeContainer()
        let coordinator = StoreMaintenanceCoordinator(
            fallbackDelay: .seconds(10),
            observesCloudKit: false,
            sleep: { _ in }
        )

        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)
        await coordinator.fallbackTask?.value

        #expect(try locationCount(container) == DefaultLocations.all.count)
    }

    @Test func startingTwiceRunsMaintenanceOnce() throws {
        let container = try makeContainer()
        let coordinator = makeCoordinator()
        let context = ModelContext(container)

        coordinator.start(context: context, isCloudKitEnabled: false)
        // A second onAppear must not merge again: add a duplicate that a
        // second pass would remove.
        context.insert(Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0))
        try context.save()
        coordinator.start(context: context, isCloudKitEnabled: false)

        #expect(try locationCount(container) == DefaultLocations.all.count + 1)
    }
}
