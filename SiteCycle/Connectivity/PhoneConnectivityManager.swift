import Foundation
import Observation
import SwiftData
import WatchConnectivity

@MainActor
@Observable
final class PhoneConnectivityManager: NSObject {
    private var session: WCSession?
    private var modelContext: ModelContext?

    var isReachable = false

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func pushCurrentState() {
        guard let modelContext, let session, session.activationState == .activated else { return }
        let state = Self.buildWatchAppState(context: modelContext)
        guard let data = state.encode() else { return }
        let payload: [String: Any] = [WatchConnectivityConstants.stateKey: data]
        try? session.updateApplicationContext(payload)

        writeStateToAppGroup(state)
    }

    // MARK: - Build State

    static func buildWatchAppState(context: ModelContext) -> WatchAppState {
        let locations = fetchEnabledLocations(context: context)
        let recommendations = SiteChangeViewModel.computeRecommendations(
            locations: locations
        )
        let activeEntry = fetchActiveEntry(context: context)

        let activeSite: ActiveSiteInfo? = activeEntry.flatMap { entry in
            guard let loc = entry.location else { return nil }
            return ActiveSiteInfo(
                locationName: loc.fullDisplayName,
                startTime: entry.startTime
            )
        }

        let targetHours = Double(
            UserDefaults.standard.integer(forKey: "targetDurationHours")
        )

        return WatchAppState(
            activeSite: activeSite,
            recommendedIds: recommendations.recommended.map(\.id),
            avoidIds: recommendations.avoid.map(\.id),
            allLocations: locations.map { loc in
                LocationInfo(
                    id: loc.id,
                    bodyPart: loc.bodyPart,
                    subArea: loc.subArea,
                    side: loc.side,
                    sortOrder: loc.sortOrder
                )
            },
            targetDurationHours: targetHours > 0 ? targetHours : 72,
            lastUpdated: Date()
        )
    }

    // MARK: - Process Watch Command

    private func processCommand(_ command: WatchSiteChangeCommand) {
        guard let modelContext else { return }

        let targetId = command.locationId
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate<Location> { $0.id == targetId }
        )
        guard let location = try? modelContext.fetch(descriptor).first else { return }

        let viewModel = SiteChangeViewModel(modelContext: modelContext)
        viewModel.logSiteChange(location: location, note: nil)

        pushCurrentState()
    }

    // MARK: - Private Helpers

    private static func fetchEnabledLocations(context: ModelContext) -> [Location] {
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate<Location> { $0.isEnabled == true },
            sortBy: [SortDescriptor(\Location.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchActiveEntry(context: ModelContext) -> SiteChangeEntry? {
        var descriptor = FetchDescriptor<SiteChangeEntry>(
            predicate: #Predicate<SiteChangeEntry> { $0.endTime == nil },
            sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func writeStateToAppGroup(_ state: WatchAppState) {
        guard let defaults = UserDefaults(
            suiteName: WatchConnectivityConstants.appGroupIdentifier
        ) else { return }
        defaults.set(state.encode(), forKey: WatchConnectivityConstants.stateKey)
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.pushCurrentState()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard let data = userInfo[WatchConnectivityConstants.commandKey] as? Data,
              let command = WatchSiteChangeCommand.decode(from: data) else { return }
        Task { @MainActor in
            self.processCommand(command)
        }
    }
}
