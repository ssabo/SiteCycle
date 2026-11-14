import CoreData
import Foundation
import Testing
@testable import SiteCycle

/// Pins when store maintenance may run on a CloudKit store (review §2.3):
/// dedup only after a successful import, and seeding without one only as a
/// fallback.
struct StoreMaintenancePolicyTests {
    private typealias Event = StoreMaintenancePolicy.Event
    private typealias Action = StoreMaintenancePolicy.Action

    /// Feeds the events to a fresh policy and returns its action for each.
    private func actions(for events: [Event]) -> [Action] {
        var policy = StoreMaintenancePolicy()
        return events.map { policy.handle($0) }
    }

    // MARK: - Full pass

    @Test func aSuccessfulImportSchedulesTheFullPass() {
        #expect(
            actions(for: [.importStarted, .importFinished(succeeded: true)])
                == [.cancelPendingPass, .scheduleFullPass]
        )
    }

    /// Dedup can delete a copy whose entries haven't arrived yet, so nothing
    /// short of a successful import may run it.
    @Test func dedupNeverRunsWithoutASuccessfulImport() {
        let events: [Event] = [
            .setupFailed,
            .importStarted,
            .fallbackDelayElapsed,
            .importFinished(succeeded: false),
            .importStarted,
            .importFinished(succeeded: false),
        ]
        #expect(!actions(for: events).contains(.scheduleFullPass))
    }

    @Test func aNewImportCancelsThePendingPassAndItsSuccessReschedules() {
        #expect(
            actions(for: [.importFinished(succeeded: true), .importStarted, .importFinished(succeeded: true)])
                == [.scheduleFullPass, .cancelPendingPass, .scheduleFullPass]
        )
    }

    /// A failed import may have applied only part of the changes.
    @Test func aFailedImportAfterASuccessWaitsForTheNextSuccess() {
        #expect(
            actions(for: [.importFinished(succeeded: true), .importStarted, .importFinished(succeeded: false)])
                == [.scheduleFullPass, .cancelPendingPass, .none]
        )
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
        #expect(
            actions(for: [.importStarted, .fallbackDelayElapsed, .importFinished(succeeded: false)])
                == [.cancelPendingPass, .none, .seedOnly]
        )
    }

    /// Offline at launch, online later: seed so the device is usable, then
    /// merge any duplicates once the user's data has arrived.
    @Test func aDeviceThatSeededStillGetsTheFullPassAfterItsFirstImport() {
        #expect(
            actions(for: [.fallbackDelayElapsed, .importStarted, .importFinished(succeeded: true)])
                == [.seedOnly, .cancelPendingPass, .scheduleFullPass]
        )
    }

    @Test func noFallbackAfterASuccessfulImport() {
        #expect(
            actions(for: [.importFinished(succeeded: true), .fallbackDelayElapsed, .setupFailed])
                == [.scheduleFullPass, .none, .none]
        )
    }

    // MARK: - CloudKit event mapping

    @Test func importEventsMapToStartAndFinish() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        #expect(Event(type: .import, endDate: nil, succeeded: false) == .importStarted)
        #expect(Event(type: .import, endDate: end, succeeded: true) == .importFinished(succeeded: true))
        #expect(Event(type: .import, endDate: end, succeeded: false) == .importFinished(succeeded: false))
    }

    @Test func onlyAFinishedFailedSetupIsMapped() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        #expect(Event(type: .setup, endDate: end, succeeded: false) == .setupFailed)
        #expect(Event(type: .setup, endDate: end, succeeded: true) == nil)
        #expect(Event(type: .setup, endDate: nil, succeeded: false) == nil)
        #expect(Event(type: .export, endDate: end, succeeded: true) == nil)
        #expect(Event(type: .export, endDate: end, succeeded: false) == nil)
    }
}
