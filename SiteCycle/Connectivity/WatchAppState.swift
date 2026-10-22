import Foundation

// MARK: - Constants

enum WatchConnectivityConstants {
    // Derived from the bundle ID so it automatically matches whichever
    // SITECYCLE_BUNDLE_PREFIX the builder set in SiteCycleConfigOverride.xcconfig.
    // Bundle IDs follow the pattern <prefix>.app[.widgets|.watchkitapp[.widgets]].
    // Stripping the watch / iPhone-widget suffixes gives the iOS app bundle ID,
    // which is the base used for the app group identifier.
    static var appGroupIdentifier: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sitecycle.app"
        let base = bundleId
            .replacingOccurrences(of: ".watchkitapp.widgets", with: "")
            .replacingOccurrences(of: ".watchkitapp", with: "")
            .replacingOccurrences(of: ".widgets", with: "")
        return "group.\(base)"
    }
    static let stateKey = "watchAppState"
    static let commandKey = "watchSiteChangeCommand"
    /// iPhone `@AppStorage` key for the "Show All Locations" watch setting.
    static let showAllLocationsKey = "watchShowAllLocations"
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
    /// When false, the watch site picker lists only the recommended locations.
    var showAllLocations: Bool = true

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

// Custom decoding (in an extension, so the memberwise init is kept) lets state
// written before `showAllLocations` existed — e.g. still cached in the App Group
// or sent by an older iPhone build — decode with the default instead of failing.
extension WatchAppState {
    private enum CodingKeys: String, CodingKey {
        case activeSite, recommendedIds, avoidIds, allLocations
        case targetDurationHours, lastUpdated, showAllLocations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeSite = try container.decodeIfPresent(ActiveSiteInfo.self, forKey: .activeSite)
        recommendedIds = try container.decode([UUID].self, forKey: .recommendedIds)
        avoidIds = try container.decode([UUID].self, forKey: .avoidIds)
        allLocations = try container.decode([LocationInfo].self, forKey: .allLocations)
        targetDurationHours = try container.decode(Double.self, forKey: .targetDurationHours)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        showAllLocations = try container.decodeIfPresent(Bool.self, forKey: .showAllLocations) ?? true
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
