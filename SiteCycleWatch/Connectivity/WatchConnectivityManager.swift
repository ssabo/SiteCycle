import Foundation
import Observation
import WatchConnectivity
import WidgetKit

@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    private var session: WCSession?

    private(set) var appState: WatchAppState = .empty
    private(set) var hasPendingCommand = false
    var hasReceivedState: Bool { appState.lastUpdated != .distantPast }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func sendSiteChangeCommand(locationId: UUID) {
        guard let session else { return }
        let command = WatchSiteChangeCommand(
            locationId: locationId,
            requestedAt: Date()
        )
        guard let data = command.encode() else { return }
        let payload: [String: Any] = [WatchConnectivityConstants.commandKey: data]
        session.transferUserInfo(payload)
        hasPendingCommand = true
    }

    // MARK: - Private

    private func handleReceivedState(_ data: Data) {
        guard let state = WatchAppState.decode(from: data) else { return }
        appState = state
        hasPendingCommand = false
        writeStateToAppGroup(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func writeStateToAppGroup(_ state: WatchAppState) {
        guard let defaults = UserDefaults(
            suiteName: WatchConnectivityConstants.appGroupIdentifier
        ) else { return }
        defaults.set(state.encode(), forKey: WatchConnectivityConstants.stateKey)
    }

    private func loadStateFromAppGroup() {
        guard let defaults = UserDefaults(
            suiteName: WatchConnectivityConstants.appGroupIdentifier
        ),
              let data = defaults.data(forKey: WatchConnectivityConstants.stateKey),
              let state = WatchAppState.decode(from: data) else { return }
        appState = state
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let stateData = session.receivedApplicationContext[WatchConnectivityConstants.stateKey] as? Data
        Task { @MainActor in
            self.loadStateFromAppGroup()

            if let stateData {
                self.handleReceivedState(stateData)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[WatchConnectivityConstants.stateKey] as? Data else {
            return
        }
        Task { @MainActor in
            self.handleReceivedState(data)
        }
    }
}
