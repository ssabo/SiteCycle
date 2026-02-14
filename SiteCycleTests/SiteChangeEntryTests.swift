import Testing
import Foundation
@testable import SiteCycle

struct SiteChangeEntryTests {

    @Test func durationHoursReturnsNilWhenNoEndTime() {
        let entry = SiteChangeEntry(startTime: Date())
        #expect(entry.durationHours == nil)
    }

    @Test func durationHoursCalculatesCorrectly() {
        let start = Date()
        let end = start.addingTimeInterval(3 * 3600) // 3 hours later
        let entry = SiteChangeEntry(startTime: start, endTime: end)
        let duration = try #require(entry.durationHours)
        #expect(abs(duration - 3.0) < 0.001)
    }

    @Test func durationHoursPartialHour() {
        let start = Date()
        let end = start.addingTimeInterval(5400) // 1.5 hours
        let entry = SiteChangeEntry(startTime: start, endTime: end)
        let duration = try #require(entry.durationHours)
        #expect(abs(duration - 1.5) < 0.001)
    }

    @Test func defaultInitValues() {
        let entry = SiteChangeEntry()
        #expect(entry.endTime == nil)
        #expect(entry.note == nil)
        #expect(entry.location == nil)
        #expect(entry.durationHours == nil)
    }

    @Test func customInitValues() {
        let id = UUID()
        let start = Date()
        let end = start.addingTimeInterval(7200)
        let location = Location(zone: "Front Abdomen", side: "left")
        let entry = SiteChangeEntry(
            id: id,
            startTime: start,
            endTime: end,
            note: "Test note",
            location: location
        )
        #expect(entry.id == id)
        #expect(entry.startTime == start)
        #expect(entry.endTime == end)
        #expect(entry.note == "Test note")
        #expect(entry.location === location)
    }

    @Test func uniqueIDGeneration() {
        let entry1 = SiteChangeEntry()
        let entry2 = SiteChangeEntry()
        #expect(entry1.id != entry2.id)
    }

    @Test func zeroDuration() {
        let start = Date()
        let entry = SiteChangeEntry(startTime: start, endTime: start)
        let duration = try #require(entry.durationHours)
        #expect(abs(duration) < 0.001)
    }
}
