import Foundation
import SwiftData
import Testing
@testable import SiteCycle

/// Pins what `StoreMaintenanceCoordinator` does with the policy's decisions,
/// against a real store: which pass runs, and that nothing merges early. Each
/// fixture holds two copies of L Abdomen (Front), so a store that still has
/// two ran no dedup.
@MainActor
struct StoreMaintenanceCoordinatorTests {
    private let importID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    private let laterImportID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A store with two seeded copies of the same default, as two devices make.
    private func makeStoreWithDuplicates() throws -> ModelContainer {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0))
        context.insert(Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0))
        try context.save()
        return container
    }

    /// A coordinator that never hears real CloudKit events and has no
    /// fallback timer, so a test drives it only through `handle(_:)`.
    private func makeCoordinator(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> StoreMaintenanceCoordinator {
        StoreMaintenanceCoordinator(fallbackDelay: nil, observesCloudKit: false, sleep: sleep)
    }

    private func locationCount(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<Location>())
    }

    private func problemCount(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<SiteProblem>())
    }

    @Test func aLocalStoreRunsTheFullPassAtStart() throws {
        let container = try makeStoreWithDuplicates()
        let context = ModelContext(container)
        let coordinator = makeCoordinator()

        coordinator.start(context: context, isCloudKitEnabled: false)

        #expect(try locationCount(container) == 1)
        #expect(try problemCount(container) == DefaultProblems.all.count)
    }

    @Test func aCloudKitStoreRunsNothingUntilAnImport() throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator()

        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)

        #expect(coordinator.scheduledPass == nil)
        #expect(try locationCount(container) == 2)
        #expect(try problemCount(container) == 0)
    }

    /// The fallback runs before anything is imported, so it must seed without
    /// merging: the duplicate's entries may not have arrived yet.
    @Test func theFallbackSeedsButNeverMerges() throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator()
        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)

        coordinator.handle(.setupFailed)

        #expect(try locationCount(container) == 2)
        #expect(try problemCount(container) == DefaultProblems.all.count)
    }

    @Test func aSuccessfulImportRunsTheFullPass() async throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator()
        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)

        coordinator.handle(.importFinished(importID, succeeded: true))
        await coordinator.scheduledPass?.value

        #expect(try locationCount(container) == 1)
        #expect(try problemCount(container) == DefaultProblems.all.count)
    }

    @Test func anImportStartingInTheQuietPeriodCancelsThePass() async throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator(sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)

        coordinator.handle(.importFinished(importID, succeeded: true))
        let pass = try #require(coordinator.scheduledPass)
        coordinator.handle(.importStarted(laterImportID))
        await pass.value

        #expect(coordinator.scheduledPass == nil)
        #expect(try locationCount(container) == 2)
    }

    @Test func aHoldDefersThePassUntilItEnds() async throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator()
        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)
        let sheet = UUID()
        let editor = UUID()

        coordinator.beginHold(sheet)
        coordinator.beginHold(editor)
        coordinator.handle(.importFinished(importID, succeeded: true))
        #expect(coordinator.scheduledPass == nil)

        // The pass waits for every hold, and ending one twice changes nothing.
        coordinator.endHold(sheet)
        coordinator.endHold(sheet)
        #expect(coordinator.scheduledPass == nil)

        coordinator.endHold(editor)
        await coordinator.scheduledPass?.value
        #expect(try locationCount(container) == 1)
    }

    /// CloudKit can finish an import before the first window appears.
    @Test func aPassDueBeforeStartRunsWhenStarted() async throws {
        let container = try makeStoreWithDuplicates()
        let coordinator = makeCoordinator()

        coordinator.handle(.importFinished(importID, succeeded: true))
        await coordinator.scheduledPass?.value
        #expect(try locationCount(container) == 2)

        coordinator.start(context: ModelContext(container), isCloudKitEnabled: true)
        #expect(try locationCount(container) == 1)
    }

    @Test func startingTwiceRunsThePassOnce() throws {
        let container = try makeContainer()
        let coordinator = makeCoordinator()
        let context = ModelContext(container)

        coordinator.start(context: context, isCloudKitEnabled: false)
        // A second onAppear must not seed or merge again: insert a duplicate
        // that a second pass would remove.
        context.insert(Location(bodyPart: "Abdomen", subArea: "Front", side: "left", sortOrder: 0))
        try context.save()
        coordinator.start(context: context, isCloudKitEnabled: false)

        #expect(try locationCount(container) == DefaultLocations.all.count + 1)
    }
}
