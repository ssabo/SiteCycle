import Foundation

// MARK: - Constants

enum WatchConnectivityConstants {
    static let appGroupIdentifier = "group.com.sitecycle.app"
    static let stateKey = "watchAppState"
    static let commandKey = "watchSiteChangeCommand"
}

// MARK: - Location Category

enum LocationCategory: String, Codable, Sendable {
    case avoid
    case recommended
    case neutral
}

// MARK: - Location Info (lightweight mirror of Location for watch)

struct LocationInfo: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let bodyPart: String
    let subArea: String?
    let side: String?
    let sortOrder: Int

    var sideLabel: String? {
        guard let side else { return nil }
        return side == "left" ? "L" : "R"
    }

    var displayName: String {
        if let subArea { return "\(bodyPart) (\(subArea))" }
        return bodyPart
    }

    var fullDisplayName: String {
        if let sideLabel { return "\(sideLabel) \(displayName)" }
        return displayName
    }
}

// MARK: - Active Site Info

struct ActiveSiteInfo: Codable, Sendable {
    let locationName: String
    let startTime: Date
}

// MARK: - Watch App State (Phone → Watch)

struct WatchAppState: Codable, Sendable {
    let activeSite: ActiveSiteInfo?
    let recommendedIds: [UUID]
    let avoidIds: [UUID]
    let allLocations: [LocationInfo]
    let targetDurationHours: Double
    let lastUpdated: Date

    static let empty = WatchAppState(
        activeSite: nil,
        recommendedIds: [],
        avoidIds: [],
        allLocations: [],
        targetDurationHours: 72,
        lastUpdated: .distantPast
    )

    func category(for locationId: UUID) -> LocationCategory {
        if avoidIds.contains(locationId) { return .avoid }
        if recommendedIds.contains(locationId) { return .recommended }
        return .neutral
    }

    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(from data: Data) -> WatchAppState? {
        try? JSONDecoder().decode(WatchAppState.self, from: data)
    }
}

// MARK: - Watch Site Change Command (Watch → Phone)

struct WatchSiteChangeCommand: Codable, Sendable {
    let locationId: UUID
    let requestedAt: Date

    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(from data: Data) -> WatchSiteChangeCommand? {
        try? JSONDecoder().decode(WatchSiteChangeCommand.self, from: data)
    }
}
