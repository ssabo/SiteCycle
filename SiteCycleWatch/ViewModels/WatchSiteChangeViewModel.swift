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
        let locationById = Dictionary(uniqueKeysWithValues: state.allLocations.map { ($0.id, $0) })
        return state.recommendedIds.compactMap { locationById[$0] }
    }

    var allLocationsSorted: [LocationInfo] {
        connectivityManager.appState.allLocations.sorted { loc1, loc2 in
            if loc1.displayName == loc2.displayName {
                return Self.sideOrder(loc1.side) < Self.sideOrder(loc2.side)
            }
            return loc1.sortOrder < loc2.sortOrder
        }
    }

    private static func sideOrder(_ side: String?) -> Int {
        switch side {
        case "left": return 0
        case "right": return 1
        default: return 2
        }
    }

    func category(for location: LocationInfo) -> LocationCategory {
        connectivityManager.appState.category(for: location.id)
    }

    func logSiteChange(locationId: UUID) {
        connectivityManager.sendSiteChangeCommand(locationId: locationId)
    }
}
