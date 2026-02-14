import Testing
import Foundation
@testable import SiteCycle

struct LocationTests {

    @Test func displayNameWithLeftSide() {
        let location = Location(zone: "Front Abdomen", side: "left")
        #expect(location.displayName == "Left Front Abdomen")
    }

    @Test func displayNameWithRightSide() {
        let location = Location(zone: "Front Abdomen", side: "right")
        #expect(location.displayName == "Right Front Abdomen")
    }

    @Test func displayNameWithoutSide() {
        let location = Location(zone: "Lower Back")
        #expect(location.displayName == "Lower Back")
    }

    @Test func defaultInitValues() {
        let location = Location(zone: "Test Zone")
        #expect(location.zone == "Test Zone")
        #expect(location.side == nil)
        #expect(location.isEnabled == true)
        #expect(location.isCustom == false)
        #expect(location.sortOrder == 0)
        #expect(location.entries.isEmpty)
    }

    @Test func customInitValues() {
        let id = UUID()
        let location = Location(
            id: id,
            zone: "Custom Zone",
            side: "left",
            isEnabled: false,
            isCustom: true,
            sortOrder: 5
        )
        #expect(location.id == id)
        #expect(location.zone == "Custom Zone")
        #expect(location.side == "left")
        #expect(location.isEnabled == false)
        #expect(location.isCustom == true)
        #expect(location.sortOrder == 5)
    }

    @Test func displayNameSideCapitalization() {
        let left = Location(zone: "Back Arm", side: "left")
        let right = Location(zone: "Back Arm", side: "right")
        #expect(left.displayName.hasPrefix("Left"))
        #expect(right.displayName.hasPrefix("Right"))
    }

    @Test func uniqueIDGeneration() {
        let location1 = Location(zone: "Front Abdomen", side: "left")
        let location2 = Location(zone: "Front Abdomen", side: "left")
        #expect(location1.id != location2.id)
    }
}
