import Testing
import Foundation
import SwiftData
@testable import SiteCycle

struct HomeViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Active Site Query

    @Test func noActiveSiteWhenNoEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = HomeViewModel(modelContext: context)

        #expect(viewModel.hasActiveSite == false)
        #expect(viewModel.activeSiteEntry == nil)
        #expect(viewModel.currentLocation == nil)
        #expect(viewModel.startTime == nil)
    }

    @Test func findsActiveSiteEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(startTime: Date(), location: location)
        context.insert(entry)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)

        #expect(viewModel.hasActiveSite == true)
        #expect(viewModel.currentLocation?.zone == "Front Abdomen")
        #expect(viewModel.startTime != nil)
    }

    @Test func ignoresClosedEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-7200),
            endTime: Date(),
            location: location
        )
        context.insert(entry)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)

        #expect(viewModel.hasActiveSite == false)
    }

    @Test func refreshActiveSitePicksMostRecentActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loc1 = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        let loc2 = Location(bodyPart: "Abdomen", subArea: "Side", side: "right")
        context.insert(loc1)
        context.insert(loc2)

        let older = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-7200),
            location: loc1
        )
        context.insert(older)

        let newer = SiteChangeEntry(
            startTime: Date().addingTimeInterval(-3600),
            location: loc2
        )
        context.insert(newer)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)

        #expect(viewModel.currentLocation?.zone == "Side Abdomen")
    }

    // MARK: - Elapsed Hours

    @Test func elapsedHoursComputesCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let start = Date().addingTimeInterval(-7200) // 2 hours ago
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(startTime: start, location: location)
        context.insert(entry)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)
        let elapsed = viewModel.elapsedHours(at: start.addingTimeInterval(7200))

        #expect(abs(elapsed - 2.0) < 0.01)
    }

    @Test func elapsedHoursReturnsZeroWithNoActiveSite() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = HomeViewModel(modelContext: context)

        #expect(viewModel.elapsedHours() == 0)
    }

    // MARK: - Progress Fraction

    @Test func progressFractionComputesCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let start = Date().addingTimeInterval(-36 * 3600) // 36 hours ago
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(startTime: start, location: location)
        context.insert(entry)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context, targetDurationHours: 72)
        let fraction = viewModel.progressFraction(at: start.addingTimeInterval(36 * 3600))

        #expect(abs(fraction - 0.5) < 0.01)
    }

    @Test func progressFractionWithCustomTarget() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let start = Date().addingTimeInterval(-24 * 3600)
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(startTime: start, location: location)
        context.insert(entry)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context, targetDurationHours: 48)
        let fraction = viewModel.progressFraction(at: start.addingTimeInterval(24 * 3600))

        #expect(abs(fraction - 0.5) < 0.01)
    }

    @Test func progressFractionReturnsZeroWithNoActiveSite() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = HomeViewModel(modelContext: context)

        #expect(viewModel.progressFraction() == 0)
    }

    @Test func progressFractionExceedsOneWhenOverdue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let start = Date().addingTimeInterval(-96 * 3600) // 96 hours ago
        let location = Location(bodyPart: "Abdomen", subArea: "Front", side: "left")
        context.insert(location)

        let entry = SiteChangeEntry(startTime: start, location: location)
        context.insert(entry)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context, targetDurationHours: 72)
        let fraction = viewModel.progressFraction(at: start.addingTimeInterval(96 * 3600))

        #expect(fraction > 1.0)
        #expect(abs(fraction - (96.0 / 72.0)) < 0.01)
    }
}
