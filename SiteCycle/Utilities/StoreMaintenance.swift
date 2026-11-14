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
///   no other import has started for a quiet period.
/// - Seeding waits for that first import too, so a new device picks up the
///   user's sites instead of creating duplicates of them. If no import can
///   succeed (offline, signed out of iCloud, setup failed), a fallback runs
///   `seedStore` once, so the device still gets its default sites. Duplicates
///   it creates are merged after the next successful import.
///
/// This is pure state, so the rules can be unit-tested without CloudKit.
struct StoreMaintenancePolicy {
    enum Event: Equatable {
        case importStarted
        case importFinished(succeeded: Bool)
        case setupFailed
        case fallbackDelayElapsed

        /// Maps a CloudKit event's fields. Nil for events maintenance ignores:
        /// exports, and setups that started or succeeded.
        init?(type: NSPersistentCloudKitContainer.EventType, endDate: Date?, succeeded: Bool) {
            switch type {
            case .import:
                self = endDate == nil ? .importStarted : .importFinished(succeeded: succeeded)
            case .setup:
                guard endDate != nil, !succeeded else { return nil }
                self = .setupFailed
            default:
                return nil
            }
        }
    }

    enum Action: Equatable {
        case none
        /// Another import started: cancel a full pass waiting out its quiet period.
        case cancelPendingPass
        /// Run `prepareStore` once no import has started for the quiet period.
        case scheduleFullPass
        /// Run `seedStore` now.
        case seedOnly
    }

    private var importInProgress = false
    private var hasImported = false
    private var fallbackDue = false
    private var hasSeeded = false

    mutating func handle(_ event: Event) -> Action {
        switch event {
        case .importStarted:
            importInProgress = true
            return .cancelPendingPass
        case .importFinished(let succeeded):
            importInProgress = false
            guard succeeded else {
                // A failed import may have applied only part of the changes, so
                // a pass cancelled by its start waits for the next success.
                return seedIfDue()
            }
            hasImported = true
            return .scheduleFullPass
        case .setupFailed, .fallbackDelayElapsed:
            fallbackDue = true
            return seedIfDue()
        }
    }

    private mutating func seedIfDue() -> Action {
        guard fallbackDue, !importInProgress, !hasImported, !hasSeeded else { return .none }
        hasSeeded = true
        return .seedOnly
    }
}

extension Notification.Name {
    /// Posted after each maintenance pass. A pass can delete duplicates that a
    /// ViewModel still holds, so views that cache models refresh on it.
    static let storeMaintenanceDidRun = Notification.Name("StoreMaintenanceDidRun")
}

/// Runs store maintenance when `StoreMaintenancePolicy` allows: at once on a
/// local-only store, and driven by CloudKit's events on a synced one.
@MainActor
final class StoreMaintenanceCoordinator {
    /// How long no import may start before a full pass runs.
    static let quietPeriod: Duration = .seconds(3)
    /// How long to wait for an import before seeding without one.
    static let fallbackDelay: Duration = .seconds(10)

    private var policy = StoreMaintenancePolicy()
    private var context: ModelContext?
    private var eventTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var pendingPass: Task<Void, Never>?

    /// Starts maintenance for this launch. Calls after the first do nothing,
    /// so it is safe to call from `onAppear`.
    func start(context: ModelContext, isCloudKitEnabled: Bool) {
        guard self.context == nil else { return }
        self.context = context

        guard isCloudKitEnabled else {
            runFullPass()
            return
        }

        eventTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                    let policyEvent = StoreMaintenancePolicy.Event(
                        type: event.type,
                        endDate: event.endDate,
                        succeeded: event.succeeded
                    ) else { continue }
                self?.handle(policyEvent)
            }
        }
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.fallbackDelay)
            guard !Task.isCancelled else { return }
            self?.handle(.fallbackDelayElapsed)
        }
    }

    private func handle(_ event: StoreMaintenancePolicy.Event) {
        switch policy.handle(event) {
        case .none:
            break
        case .cancelPendingPass:
            pendingPass?.cancel()
            pendingPass = nil
        case .scheduleFullPass:
            pendingPass?.cancel()
            pendingPass = Task { [weak self] in
                try? await Task.sleep(for: Self.quietPeriod)
                guard !Task.isCancelled else { return }
                self?.runFullPass()
            }
        case .seedOnly:
            guard let context else { return }
            seedStore(context: context)
            NotificationCenter.default.post(name: .storeMaintenanceDidRun, object: nil)
        }
    }

    private func runFullPass() {
        guard let context else { return }
        prepareStore(context: context)
        NotificationCenter.default.post(name: .storeMaintenanceDidRun, object: nil)
    }
}
