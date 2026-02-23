import Testing
import Foundation
@testable import SiteCycle

struct LocationTests {

    @Test func displayNameWithSubArea() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        #expect(location.displayName == "Abdomen (Front)")
    }

    @Test func displayNameWithRightSide() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "right")
        #expect(location.displayName == "Abdomen (Front)")
    }

    @Test func displayNameWithoutSide() {
        let location = Location(bodyPart: "Back", subArea: "Lower")
        #expect(location.displayName == "Back (Lower)")
    }

    @Test func defaultInitValues() {
        let location = Location(bodyPart: "Test Zone")
        #expect(location.bodyPart == "Test Zone")
        #expect(location.subArea == nil)
        #expect(location.zone == "Test Zone")
        #expect(location.side == nil)
        #expect(location.isEnabled == true)
        #expect(location.isCustom == false)
        #expect(location.sortOrder == 0)
        #expect(location.safeEntries.isEmpty)
    }

    @Test func customInitValues() {
        let id = UUID()
        let location = Location(
            id: id,
            bodyPart: "Custom",
            subArea: "Zone",
            side: "left",
            isEnabled: false,
            isCustom: true,
            sortOrder: 5
        )
        #expect(location.id == id)
        #expect(location.bodyPart == "Custom")
        #expect(location.subArea == "Zone")
        #expect(location.zone == "Zone Custom")
        #expect(location.side == "left")
        #expect(location.isEnabled == false)
        #expect(location.isCustom == true)
        #expect(location.sortOrder == 5)
    }

    @Test func displayNameSideCapitalization() {
        let left = Location(bodyPart: "Arm", subArea: "Back", side: "left")
        let right = Location(bodyPart: "Arm", subArea: "Back", side: "right")
        #expect(left.sideLabel == "L")
        #expect(right.sideLabel == "R")
    }

    @Test func sideLabelLeft() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        #expect(location.sideLabel == "L")
    }

    @Test func sideLabelRight() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "right")
        #expect(location.sideLabel == "R")
    }

    @Test func sideLabelNil() {
        let location = Location(bodyPart: "Buttock")
        #expect(location.sideLabel == nil)
    }

    @Test func fullDisplayNameWithSide() {
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        #expect(location.fullDisplayName == "L Abdomen (Front)")
    }

    @Test func fullDisplayNameWithoutSide() {
        let location = Location(bodyPart: "Buttock")
        #expect(location.fullDisplayName == "Buttock")
    }

    @Test func displayNameSingleWord() {
        let location = Location(bodyPart: "Buttock")
        #expect(location.displayName == "Buttock")
    }

    @Test func uniqueIDGeneration() {
        let location1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let location2 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        #expect(location1.id != location2.id)
    }

    @Test func zoneComputedFromBodyPartAndSubArea() {
        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front")
        #expect(loc1.zone == "Front Abdomen")

        let loc2 = Location(bodyPart: "Buttock")
        #expect(loc2.zone == "Buttock")

        let loc3 = Location(bodyPart: "Arm", subArea: "Back")
        #expect(loc3.zone == "Back Arm")
    }
}
