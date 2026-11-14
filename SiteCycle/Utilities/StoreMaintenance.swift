import CoreData
import Foundation
import SwiftData

/// Seeds, migrates and deduplicates the store. Only `StoreMaintenanceCoordinator`
/// calls it, at the times `StoreMaintenancePolicy` allows.
///
/// The order matters:
/// - Migration runs before location dedup, which identifies a location by its
///   `bodyPart`. Legacy rows have one only after migration.
/// - Location dedup runs before entry dedup, which matches entries by
///   location. Two copies of an entry match only once both point at the
///   location keeper.
@MainActor
func prepareStore(context: ModelContext) {
    seedDefaultLocations(context: context)
    migrateLocationBodyParts(context: context)
    deduplicateLocations(context: context)
    deduplicateSiteChangeEntries(context: context)
    seedDefaultProblems(context: context)
    deduplicateProblems(context: context)
}

/// The part of `prepareStore` that never deletes anything, so it is safe to
/// run before CloudKit has imported the user's data.
@MainActor
func seedStore(context: ModelContext) {
    seedDefaultLocations(context: context)
    migrateLocationBodyParts(context: context)
    seedDefaultProblems(context: context)
}

/// Decides when store maintenance may run on a CloudKit store (review §2.3).
///
/// Dedup deletes duplicates after moving their entries onto the keeper, but it
/// can move only the entries already on this device. Run mid-import, for
/// example on a new phone still downloading the user's history, it deletes a
/// copy whose entries haven't arrived yet, and those entries lose their
/// location on every device. So:
/// - The full pass (`prepareStore`) runs only after a successful import, once
///   no import is in progress and none has started for a quiet period.
/// - It also waits while a hold is active: a sheet or editor that keeps a
///   record across user interaction, which the pass could delete under it.
/// - Seeding waits for the first import too, so a new device picks up the
///   user's sites instead of creating duplicates of them. If no full pass can
///   run (offline, signed out of iCloud, setup or import failed), a fallback
///   runs `seedStore` once, so the device still gets its default sites.
///   Duplicates it creates are merged by the next full pass.
///
/// This is pure state, so the rules can be unit-tested without CloudKit.
struct StoreMaintenancePolicy {
    enum Event: Equatable, Sendable {
        case importStarted(UUID)
        case importFinished(UUID, succeeded: Bool)
        case setupFailed
        case fallbackDelayElapsed
        case holdsChanged(active: Bool)
        case fullPassRan

        /// Maps a CloudKit event. Nil for events maintenance ignores: exports,
        /// and setups that started or succeeded.
        init?(_ info: CloudKitEventInfo) {
            switch info.type {
            case .import:
                self = info.endDate == nil
                    ? .importStarted(info.identifier)
                    : .importFinished(info.identifier, succeeded: info.succeeded)
            case .setup:
                guard info.endDate != nil, !info.succeeded else { return nil }
                self = .setupFailed
            default:
                return nil
            }
        }
    }

    enum Action: Equatable {
        case none
        /// Cancel a full pass waiting out its quiet period.
        case cancelPendingPass
        /// Run `prepareStore` once the quiet period passes with no import started.
        case scheduleFullPass
        /// Run `seedStore` now.
        case seedOnly
    }

    /// Keyed by event identifier, in case CloudKit ever overlaps imports.
    private var importsInProgress: Set<UUID> = []
    /// The latest import to finish succeeded, and no full pass has run since.
    private var passDue = false
    private var held = false
    private var fallbackDue = false
    private var fullPassHasRun = false
    private var hasSeeded = false

    mutating func handle(_ event: Event) -> Action {
        switch event {
        case .importStarted(let id):
            importsInProgress.insert(id)
            return .cancelPendingPass
        case .importFinished(let id, let succeeded):
            importsInProgress.remove(id)
            // A failed import may have applied only part of its changes, so
            // the pass waits for the next success.
            passDue = succeeded
            return passDue ? passIfReady() : seedIfDue()
        case .holdsChanged(let active):
            held = active
            return active ? .cancelPendingPass : passIfReady()
        case .setupFailed, .fallbackDelayElapsed:
            fallbackDue = true
            return seedIfDue()
        case .fullPassRan:
            passDue = false
            fullPassHasRun = true
            return .none
        }
    }

    private func passIfReady() -> Action {
        passDue && importsInProgress.isEmpty && !held ? .scheduleFullPass : .none
    }

    private mutating func seedIfDue() -> Action {
        guard fallbackDue, importsInProgress.isEmpty, !fullPassHasRun, !hasSeeded else { return .none }
        hasSeeded = true
        return .seedOnly
    }
}

extension Notification.Name {
    /// Posted after each maintenance pass, with the coordinator as the object.
    /// A pass can delete duplicates that a ViewModel still holds, so views
    /// that cache models refresh on it (`onStoreMaintenancePass`).
    static let storeMaintenanceDidRun = Notification.Name("StoreMaintenanceDidRun")
}

/// Runs store maintenance when `StoreMaintenancePolicy` allows: at once on a
/// local-only store, and driven by CloudKit's events on a synced one.
@MainActor
final class StoreMaintenanceCoordinator {
    private let quietPeriod: Duration
    private let fallbackDelay: Duration?
    private let sleep: @Sendable (Duration) async throws -> Void
    private var policy = StoreMaintenancePolicy()
    private var context: ModelContext?
    private var cloudKitObserver: NSObjectProtocol?
    private var holds: Set<UUID> = []
    /// A pass the policy asked for before `start` supplied the context.
    private var waitingForStart: StoreMaintenancePolicy.Action?
    private var fallbackTask: Task<Void, Never>?
    /// The full pass waiting out its quiet period, if any.
    private(set) var scheduledPass: Task<Void, Never>?

    /// - Parameters:
    ///   - quietPeriod: how long no import may start before a full pass runs.
    ///   - fallbackDelay: how long to wait for an import before seeding
    ///     without one; nil turns the fallback timer off.
    ///   - observesCloudKit: whether to listen for CloudKit's events. The app
    ///     starts listening here, before its store exists, so it can't miss
    ///     the first import starting. Tests turn it off and send events
    ///     with `handle(_:)`.
    ///   - sleep: waits for a duration; tests pass one that returns at once.
    init(
        quietPeriod: Duration = .seconds(3),
        fallbackDelay: Duration? = .seconds(10),
        observesCloudKit: Bool = true,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.quietPeriod = quietPeriod
        self.fallbackDelay = fallbackDelay
        self.sleep = sleep
        if observesCloudKit {
            cloudKitObserver = CloudKitEvents.observe { [weak self] info in
                guard let event = StoreMaintenancePolicy.Event(info) else { return }
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        }
    }

    /// Supplies the store and starts maintenance for this launch. Calls after
    /// the first do nothing, so it is safe to call from `onAppear`.
    func start(context: ModelContext, isCloudKitEnabled: Bool) {
        guard self.context == nil else { return }
        self.context = context

        guard isCloudKitEnabled else {
            runFullPass()
            return
        }

        if let waiting = waitingForStart {
            waitingForStart = nil
            if waiting == .scheduleFullPass {
                runFullPass()
            } else {
                runSeedOnly()
            }
        }
        if let fallbackDelay {
            let sleep = self.sleep
            fallbackTask = Task { [weak self] in
                try? await sleep(fallbackDelay)
                guard !Task.isCancelled else { return }
                self?.handle(.fallbackDelayElapsed)
            }
        }
    }

    /// Called by `holdsStoreMaintenance()` when a view that keeps records
    /// appears. The full pass waits until every hold has ended.
    func beginHold(_ token: UUID) {
        let wasHeld = !holds.isEmpty
        holds.insert(token)
        if !wasHeld {
            handle(.holdsChanged(active: true))
        }
    }

    func endHold(_ token: UUID) {
        guard holds.remove(token) != nil, holds.isEmpty else { return }
        handle(.holdsChanged(active: false))
    }

    func handle(_ event: StoreMaintenancePolicy.Event) {
        switch policy.handle(event) {
        case .none:
            break
        case .cancelPendingPass:
            scheduledPass?.cancel()
            scheduledPass = nil
        case .scheduleFullPass:
            scheduledPass?.cancel()
            let sleep = self.sleep
            let quietPeriod = self.quietPeriod
            scheduledPass = Task { [weak self] in
                try? await sleep(quietPeriod)
                guard !Task.isCancelled else { return }
                self?.runFullPass()
            }
        case .seedOnly:
            runSeedOnly()
        }
    }

    private func runFullPass() {
        guard let context else {
            waitingForStart = .scheduleFullPass
            return
        }
        prepareStore(context: context)
        _ = policy.handle(.fullPassRan)
        NotificationCenter.default.post(name: .storeMaintenanceDidRun, object: self)
    }

    private func runSeedOnly() {
        guard let context else {
            if waitingForStart == nil {
                waitingForStart = .seedOnly
            }
            return
        }
        seedStore(context: context)
        NotificationCenter.default.post(name: .storeMaintenanceDidRun, object: self)
    }
}
