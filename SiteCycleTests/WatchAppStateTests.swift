import Testing
import Foundation
@testable import SiteCycle

struct WatchAppStateTests {
    // MARK: - LocationInfo Display Names

    @Test func locationInfoDisplayNameWithSubArea() {
        let info = LocationInfo(
            id: UUID(),
            bodyPart: "Abdomen",
            subArea: "Front",
            side: "left",
            sortOrder: 0
        )
        #expect(info.displayName == "Abdomen (Front)")
        #expect(info.fullDisplayName == "L Abdomen (Front)")
        #expect(info.sideLabel == "L")
    }

    @Test func locationInfoDisplayNameWithoutSubArea() {
        let info = LocationInfo(
            id: UUID(),
            bodyPart: "Upper Arm",
            subArea: nil,
            side: "right",
            sortOrder: 1
        )
        #expect(info.displayName == "Upper Arm")
        #expect(info.fullDisplayName == "R Upper Arm")
        #expect(info.sideLabel == "R")
    }

    @Test func locationInfoDisplayNameWithoutSide() {
        let info = LocationInfo(
            id: UUID(),
            bodyPart: "Back",
            subArea: nil,
            side: nil,
            sortOrder: 2
        )
        #expect(info.displayName == "Back")
        #expect(info.fullDisplayName == "Back")
        #expect(info.sideLabel == nil)
    }

    // MARK: - WatchAppState Encoding/Decoding

    @Test func watchAppStateRoundTrip() throws {
        let state = WatchAppState(
            activeSite: ActiveSiteInfo(
                locationName: "L Abdomen (Front)",
                startTime: Date(timeIntervalSince1970: 1_000_000)
            ),
            recommendedIds: [UUID()],
            avoidIds: [UUID()],
            allLocations: [
                LocationInfo(
                    id: UUID(),
                    bodyPart: "Abdomen",
                    subArea: "Front",
                    side: "left",
                    sortOrder: 0
                ),
            ],
            targetDurationHours: 72,
            lastUpdated: Date(timeIntervalSince1970: 2_000_000)
        )

        let data = try #require(state.encode())
        let decoded = try #require(WatchAppState.decode(from: data))

        #expect(decoded.activeSite?.locationName == "L Abdomen (Front)")
        #expect(decoded.recommendedIds.count == 1)
        #expect(decoded.avoidIds.count == 1)
        #expect(decoded.allLocations.count == 1)
        #expect(decoded.targetDurationHours == 72)
    }

    @Test func watchAppStateEmptyRoundTrip() throws {
        let data = try #require(WatchAppState.empty.encode())
        let decoded = try #require(WatchAppState.decode(from: data))

        #expect(decoded.activeSite == nil)
        #expect(decoded.allLocations.isEmpty)
        #expect(decoded.targetDurationHours == 72)
    }

    // MARK: - WatchSiteChangeCommand Encoding/Decoding

    @Test func watchSiteChangeCommandRoundTrip() throws {
        let id = UUID()
        let command = WatchSiteChangeCommand(
            locationId: id,
            requestedAt: Date(timeIntervalSince1970: 1_000_000)
        )

        let data = try #require(command.encode())
        let decoded = try #require(WatchSiteChangeCommand.decode(from: data))

        #expect(decoded.locationId == id)
    }

    // MARK: - Category Logic

    @Test func categoryForLocation() {
        let recommendedId = UUID()
        let avoidId = UUID()
        let neutralId = UUID()

        let state = WatchAppState(
            activeSite: nil,
            recommendedIds: [recommendedId],
            avoidIds: [avoidId],
            allLocations: [],
            targetDurationHours: 72,
            lastUpdated: Date()
        )

        #expect(state.category(for: recommendedId) == .recommended)
        #expect(state.category(for: avoidId) == .avoid)
        #expect(state.category(for: neutralId) == .neutral)
    }
}
