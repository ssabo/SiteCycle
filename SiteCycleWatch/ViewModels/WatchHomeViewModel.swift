import Foundation
import Observation

@MainActor
@Observable
final class WatchHomeViewModel {
    private let connectivityManager: WatchConnectivityManager

    init(connectivityManager: WatchConnectivityManager) {
        self.connectivityManager = connectivityManager
    }

    var hasReceivedState: Bool { connectivityManager.hasReceivedState }
    var hasActiveSite: Bool { connectivityManager.appState.activeSite != nil }

    var currentLocationName: String? {
        connectivityManager.appState.activeSite?.locationName
    }

    var startTime: Date? {
        connectivityManager.appState.activeSite?.startTime
    }

    var targetDurationHours: Double {
        connectivityManager.appState.targetDurationHours
    }

    func elapsedHours(at now: Date = Date()) -> Double {
        guard let startTime else { return 0 }
        return now.timeIntervalSince(startTime) / 3600.0
    }

    func progressFraction(at now: Date = Date()) -> Double {
        guard hasActiveSite else { return 0 }
        return elapsedHours(at: now) / targetDurationHours
    }
}
