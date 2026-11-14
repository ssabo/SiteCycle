import CoreData
import Foundation
import Testing
@testable import SiteCycle

/// Pins when store maintenance may run on a CloudKit store (review §2.3):
/// dedup only after a successful import and while nothing holds it off, and
/// seeding without an import only as a fallback.
struct StoreMaintenancePolicyTests {
    private typealias Event = StoreMaintenancePolicy.Event
    private typealias Action = StoreMaintenancePolicy.Action

    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()

    /// Feeds the events to a fresh policy and returns its action for each.
    private func actions(for events: [Event]) -> [Action] {
        var policy = StoreMaintenancePolicy()
        return events.map { policy.handle($0) }
    }

    // MARK: - Full pass

    @Test func aSuccessfulImportSchedulesTheFullPass() {
        #expect(
            actions(for: [.importStarted(first), .importFinished(first, succeeded: true)])
                == [.cancelPendingPass, .scheduleFullPass]
        )
    }

    /// Dedup can delete a copy whose entries haven't arrived yet, so nothing
    /// short of a successful import may run it.
    @Test func dedupNeverRunsWithoutASuccessfulImport() {
        let events: [Event] = [
            .setupFailed,
            .importStarted(first),
            .fallbackDelayElapsed,
            .importFinished(first, succeeded: false),
            .holdsChanged(active: true),
            .holdsChanged(active: false),
            .importStarted(second),
            .importFinished(second, succeeded: false),
        ]
        #expect(!actions(for: events).contains(.scheduleFullPass))
    }

    @Test func aNewImportCancelsThePendingPassAndItsSuccessReschedules() {
        let events: [Event] = [
            .importFinished(first, succeeded: true),
            .importStarted(second),
            .importFinished(second, succeeded: true),
        ]
        #expect(actions(for: events) == [.scheduleFullPass, .cancelPendingPass, .scheduleFullPass])
    }

    /// A failed import may have applied only part of the changes.
    @Test func aFailedImportAfterASuccessWaitsForTheNextSuccess() {
        let events: [Event] = [
            .importFinished(first, succeeded: true),
            .importStarted(second),
            .importFinished(second, succeeded: false),
        ]
        #expect(actions(for: events) == [.scheduleFullPass, .cancelPendingPass, .none])
    }

    /// The first import to finish mustn't let the pass run while the other is
    /// still bringing in entries.
    @Test func overlappingImportsWaitForTheLastToFinish() {
        let events: [Event] = [
            .importStarted(first),
            .importStarted(second),
            .importFinished(first, succeeded: true),
            .importFinished(second, succeeded: true),
        ]
        #expect(actions(for: events) == [.cancelPendingPass, .cancelPendingPass, .none, .scheduleFullPass])
    }

    // MARK: - Holds

    @Test func aHoldDefersThePassUntilItEnds() {
        let events: [Event] = [
            .holdsChanged(active: true),
            .importFinished(first, succeeded: true),
            .holdsChanged(active: false),
        ]
        #expect(actions(for: events) == [.cancelPendingPass, .none, .scheduleFullPass])
    }

    @Test func aHoldCancelsAPendingPassAndItsEndReschedules() {
        let events: [Event] = [
            .importFinished(first, succeeded: true),
            .holdsChanged(active: true),
            .holdsChanged(active: false),
        ]
        #expect(actions(for: events) == [.scheduleFullPass, .cancelPendingPass, .scheduleFullPass])
    }

    @Test func endingAHoldRunsNothingOnceThePassHasRun() {
        let events: [Event] = [
            .importFinished(first, succeeded: true),
            .fullPassRan,
            .holdsChanged(active: true),
            .holdsChanged(active: false),
        ]
        #expect(actions(for: events) == [.scheduleFullPass, .none, .cancelPendingPass, .none])
    }

    // MARK: - Seeding fallback

    @Test func theFallbackSeedsOnceWhenNoImportComes() {
        #expect(
            actions(for: [.fallbackDelayElapsed, .setupFailed, .fallbackDelayElapsed])
                == [.seedOnly, .none, .none]
        )
    }

    @Test func aFailedSetupSeedsWithoutWaitingForTheFallback() {
        #expect(actions(for: [.setupFailed]) == [.seedOnly])
    }

    @Test func theFallbackWaitsForAnImportInProgress() {
        let events: [Event] = [
            .importStarted(first),
            .fallbackDelayElapsed,
            .importFinished(first, succeeded: false),
        ]
        #expect(actions(for: events) == [.cancelPendingPass, .none, .seedOnly])
    }

    /// A successful import whose pass was cancelled, then a failed one, mustn't
    /// leave a new device with no sites until CloudKit next succeeds.
    @Test func theFallbackStillSeedsWhenNoFullPassHasRun() {
        let events: [Event] = [
            .importFinished(first, succeeded: true),
            .importStarted(second),
            .importFinished(second, succeeded: false),
            .fallbackDelayElapsed,
        ]
        #expect(actions(for: events) == [.scheduleFullPass, .cancelPendingPass, .none, .seedOnly])
    }

    /// Offline at launch, online later: seed so the device is usable, then
    /// merge any duplicates once the user's data has arrived.
    @Test func aDeviceThatSeededStillGetsTheFullPassAfterItsFirstImport() {
        let events: [Event] = [
            .fallbackDelayElapsed,
            .importStarted(first),
            .importFinished(first, succeeded: true),
        ]
        #expect(actions(for: events) == [.seedOnly, .cancelPendingPass, .scheduleFullPass])
    }

    @Test func noFallbackOnceTheFullPassHasRun() {
        let events: [Event] = [
            .importFinished(first, succeeded: true),
            .fullPassRan,
            .fallbackDelayElapsed,
            .setupFailed,
        ]
        #expect(actions(for: events) == [.scheduleFullPass, .none, .none, .none])
    }

    // MARK: - CloudKit event mapping

    private func info(
        _ type: NSPersistentCloudKitContainer.EventType,
        finished: Bool,
        succeeded: Bool
    ) -> CloudKitEventInfo {
        CloudKitEventInfo(
            identifier: first,
            type: type,
            storeIdentifier: "store",
            endDate: finished ? Date(timeIntervalSince1970: 1_000_000) : nil,
            succeeded: succeeded,
            error: nil
        )
    }

    @Test func importEventsMapToStartAndFinish() {
        #expect(Event(info(.import, finished: false, succeeded: false)) == .importStarted(first))
        #expect(Event(info(.import, finished: true, succeeded: true)) == .importFinished(first, succeeded: true))
        #expect(Event(info(.import, finished: true, succeeded: false)) == .importFinished(first, succeeded: false))
    }

    @Test func onlyAFinishedFailedSetupIsMapped() {
        #expect(Event(info(.setup, finished: true, succeeded: false)) == .setupFailed)
        #expect(Event(info(.setup, finished: true, succeeded: true)) == nil)
        #expect(Event(info(.setup, finished: false, succeeded: false)) == nil)
        #expect(Event(info(.export, finished: true, succeeded: true)) == nil)
        #expect(Event(info(.export, finished: true, succeeded: false)) == nil)
    }
}
