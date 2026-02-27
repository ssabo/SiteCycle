import Foundation
import Observation

@MainActor
@Observable
final class WatchSiteChangeViewModel {
    private let connectivityManager: WatchConnectivityManager

    init(connectivityManager: WatchConnectivityManager) {
        self.connectivityManager = connectivityManager
    }

    var hasPendingCommand: Bool { connectivityManager.hasPendingCommand }

    var recommendedLocations: [LocationInfo] {
        let state = connectivityManager.appState
        return state.allLocations.filter { state.recommendedIds.contains($0.id) }
    }

    var allLocationsSorted: [LocationInfo] {
        connectivityManager.appState.allLocations.sorted { $0.sortOrder < $1.sortOrder }
    }

    func category(for location: LocationInfo) -> LocationCategory {
        connectivityManager.appState.category(for: location.id)
    }

    func logSiteChange(locationId: UUID) {
        connectivityManager.sendSiteChangeCommand(locationId: locationId)
    }
}
