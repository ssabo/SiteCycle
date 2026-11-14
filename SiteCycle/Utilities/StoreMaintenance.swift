import CoreData
import Foundation
import SwiftData

/// Migrates and deduplicates the store. Runs once per launch, before any
/// screen holds a record. It never inserts anything.
///
/// The order matters:
/// - Migration runs before location dedup, which identifies a location by its
///   `bodyPart`. Legacy rows have one only after migration.
/// - Location dedup runs before entry dedup, which matches entries by
///   location. Two copies of an entry match only once both point at the
///   location keeper.
/// - Entry dedup runs before closing superseded entries, so two copies of the
///   active entry are merged rather than one closing the other.
@MainActor
func prepareStore(context: ModelContext) {
    migrateLocationBodyParts(context: context)
    deduplicateLocations(context: context)
    deduplicateSiteChangeEntries(context: context)
    closeSupersededActiveEntries(context: context)
    deduplicateProblems(context: context)
}

/// Closes every open entry but the newest, and saves if that changed anything.
/// It never deletes, so unlike dedup it is safe to run while screens hold
/// records. Returns whether it changed anything.
@MainActor
@discardableResult
func closeSupersededActiveEntries(context: ModelContext) -> Bool {
    guard SiteChangeEntry.closeSupersededActiveEntries(in: context) else { return false }
    try? context.save()
    return true
}

/// Seeds the default locations and problems the store doesn't have yet. It
/// only inserts.
@MainActor
func seedStore(context: ModelContext) {
    seedDefaultLocations(context: context)
    seedDefaultProblems(context: context)
}

extension Notification.Name {
    /// Posted when maintenance changes an iCloud store after launch: it seeded
    /// the defaults, or closed superseded entries after a CloudKit download.
    /// Home refreshes on it, and the app pushes the new state to the watch.
    static let storeMaintenanceDidChangeData = Notification.Name("StoreMaintenanceDidChangeData")
}

/// Runs the store's launch maintenance, and decides when to seed the defaults.
///
/// On an iCloud store, seeding waits for the first successful CloudKit
/// download, then adds only the defaults the user doesn't already have. A new
/// phone that seeded at launch would get its own copy of every default, and
/// merging those with the user's real ones could delete the copy whose history
/// hadn't downloaded yet, leaving those entries with no location (review §2.3).
/// If no download succeeds, for example offline or without an iCloud account,
/// it seeds after `fallbackDelay` anyway. Any duplicates that creates are
/// merged at the next launch.
///
/// After every successful CloudKit download it also closes superseded active
/// entries, since another device may have logged a change offline.
@MainActor
final class StoreMaintenanceCoordinator {
    private let fallbackDelay: Duration?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let notificationCenter: NotificationCenter
    private var context: ModelContext?
    private var importObserver: NSObjectProtocol?
    private var importHasSucceeded = false
    private var hasSeeded = false
    /// The fallback timer, while it runs.
    private(set) var fallbackTask: Task<Void, Never>?

    /// - Parameters:
    ///   - fallbackDelay: how long to wait for a download before seeding
    ///     anyway; nil turns the timer off.
    ///   - observesCloudKit: whether to listen for CloudKit downloads. The app
    ///     starts listening here, before its store exists, so it can't miss
    ///     the first one. Tests turn it off and call `importDidSucceed()`.
    ///   - sleep: waits for a duration; tests pass one that returns at once.
    ///   - notificationCenter: where `.storeMaintenanceDidChangeData` is posted. Tests
    ///     pass their own, so the host app doesn't react to a test's seeding.
    init(
        fallbackDelay: Duration? = .seconds(10),
        observesCloudKit: Bool = true,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        notificationCenter: NotificationCenter = .default
    ) {
        self.fallbackDelay = fallbackDelay
        self.sleep = sleep
        self.notificationCenter = notificationCenter
        if observesCloudKit {
            importObserver = Self.observeSuccessfulImports { [weak self] in
                Task { @MainActor [weak self] in
                    self?.importDidSucceed()
                }
            }
        }
    }

    /// Runs this launch's maintenance. Calls after the first do nothing, so it
    /// is safe to call from `onAppear`.
    func start(context: ModelContext, isCloudKitEnabled: Bool) {
        guard self.context == nil else { return }
        self.context = context

        guard isCloudKitEnabled else {
            seedStore(context: context)
            prepareStore(context: context)
            hasSeeded = true
            return
        }

        prepareStore(context: context)
        if importHasSucceeded {
            if seedOnce() { postDidChangeData() }
        } else if let fallbackDelay {
            let sleep = self.sleep
            fallbackTask = Task { [weak self] in
                try? await sleep(fallbackDelay)
                guard !Task.isCancelled, let self else { return }
                if self.seedOnce() { self.postDidChangeData() }
            }
        }
    }

    /// A CloudKit download succeeded, so the user's existing data is on this
    /// device: seed whichever defaults they don't have. The download may also
    /// have brought a change another device logged offline, leaving two
    /// active entries, so close the superseded one.
    func importDidSucceed() {
        importHasSucceeded = true
        guard let context else { return }
        let closedEntries = closeSupersededActiveEntries(context: context)
        let seeded = seedOnce()
        if closedEntries || seeded { postDidChangeData() }
    }

    /// Seeds the first time it's called once there is a context. Returns
    /// whether it seeded.
    private func seedOnce() -> Bool {
        guard let context, !hasSeeded else { return false }
        hasSeeded = true
        fallbackTask?.cancel()
        seedStore(context: context)
        return true
    }

    private func postDidChangeData() {
        notificationCenter.post(name: .storeMaintenanceDidChangeData, object: self)
    }

    /// Calls `handler` each time a CloudKit import succeeds, on the queue that
    /// posts it. The closure is created here, in a nonisolated function, so it
    /// isn't main-actor isolated (see CLAUDE.md, "Compile gotchas").
    private nonisolated static func observeSuccessfulImports(
        _ handler: @escaping @Sendable () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.endDate != nil,
                event.succeeded else { return }
            handler()
        }
    }
}
