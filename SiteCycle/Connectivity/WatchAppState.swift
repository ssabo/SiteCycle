import Foundation

// MARK: - Constants

enum WatchConnectivityConstants {
    // Derived from the bundle ID so it automatically matches whichever
    // SITECYCLE_BUNDLE_PREFIX the builder set in SiteCycleConfigOverride.xcconfig.
    // Bundle IDs follow the pattern <prefix>.sitecycle.app[.watchkitapp[.widgets]].
    // Stripping the watch/widget suffix gives the iOS app bundle ID, which is
    // the base used for the app group identifier.
    static var appGroupIdentifier: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sitecycle.app"
        let base = bundleId
            .replacingOccurrences(of: ".watchkitapp.widgets", with: "")
            .replacingOccurrences(of: ".watchkitapp", with: "")
        return "group.\(base)"
    }
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
// Display name logic (displayName, fullDisplayName, sideLabel) must match Location.swift

struct LocationInfo: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let bodyPart: String
    let subArea: String?
    let side: String?
    let sortOrder: Int
    let lastUsedDate: Date?

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
