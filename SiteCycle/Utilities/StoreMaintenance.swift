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
@MainActor
func prepareStore(context: ModelContext) {
    migrateLocationBodyParts(context: context)
    deduplicateLocations(context: context)
    deduplicateSiteChangeEntries(context: context)
    deduplicateProblems(context: context)
}

/// Seeds the default locations and problems the store doesn't have yet. It
/// only inserts.
@MainActor
func seedStore(context: ModelContext) {
    seedDefaultLocations(context: context)
    seedDefaultProblems(context: context)
}

extension Notification.Name {
    /// Posted when an iCloud store's defaults are seeded after launch. Home
    /// refreshes on it, and the app pushes the new sites to the watch.
    static let storeDidSeedDefaults = Notification.Name("StoreDidSeedDefaults")
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
    ///   - notificationCenter: where `.storeDidSeedDefaults` is posted. Tests
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
            seedOnce()
        } else if let fallbackDelay {
            let sleep = self.sleep
            fallbackTask = Task { [weak self] in
                try? await sleep(fallbackDelay)
                guard !Task.isCancelled else { return }
                self?.seedOnce()
            }
        }
    }

    /// A CloudKit download succeeded, so the user's existing data is on this
    /// device: seed whichever defaults they don't have.
    func importDidSucceed() {
        importHasSucceeded = true
        seedOnce()
    }

    private func seedOnce() {
        guard let context, !hasSeeded else { return }
        hasSeeded = true
        fallbackTask?.cancel()
        seedStore(context: context)
        notificationCenter.post(name: .storeDidSeedDefaults, object: self)
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
