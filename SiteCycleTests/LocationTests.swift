import Testing
import Foundation
@testable import SiteCycle

struct LocationTests {

    @Test func displayNameWithLeftSide() {
        let location = Location(zone: "Front Abdomen", side: "left")
        #expect(location.displayName == "Abdomen - Front")
    }

    @Test func displayNameWithRightSide() {
        let location = Location(zone: "Front Abdomen", side: "right")
        #expect(location.displayName == "Abdomen - Front")
    }

    @Test func displayNameWithoutSide() {
        let location = Location(zone: "Lower Back")
        #expect(location.displayName == "Back - Lower")
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
        #expect(left.sideLabel == "L")
        #expect(right.sideLabel == "R")
    }

    @Test func sideLabelLeft() {
        let location = Location(zone: "Front Abdomen", side: "left")
        #expect(location.sideLabel == "L")
    }

    @Test func sideLabelRight() {
        let location = Location(zone: "Front Abdomen", side: "right")
        #expect(location.sideLabel == "R")
    }

    @Test func sideLabelNil() {
        let location = Location(zone: "Buttock")
        #expect(location.sideLabel == nil)
    }

    @Test func fullDisplayNameWithSide() {
        let location = Location(zone: "Front Abdomen", side: "left")
        #expect(location.fullDisplayName == "L Abdomen - Front")
    }

    @Test func fullDisplayNameWithoutSide() {
        let location = Location(zone: "Buttock")
        #expect(location.fullDisplayName == "Buttock")
    }

    @Test func displayNameSingleWord() {
        let location = Location(zone: "Buttock")
        #expect(location.displayName == "Buttock")
    }

    @Test func uniqueIDGeneration() {
        let location1 = Location(zone: "Front Abdomen", side: "left")
        let location2 = Location(zone: "Front Abdomen", side: "left")
        #expect(location1.id != location2.id)
    }
}
