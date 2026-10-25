import Testing
import Foundation
import SwiftData
@testable import SiteCycle

/// Recording problems through logging, History, and CSV.
@MainActor
struct SiteProblemWorkflowTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fetchProblems(_ context: ModelContext) throws -> [SiteProblem] {
        try context.fetch(FetchDescriptor<SiteProblem>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    /// Inserts two locations and an active entry on the first; returns (active entry, second location).
    private func setUpActiveSite(_ context: ModelContext) throws -> (SiteChangeEntry, Location) {
        let first = Location(bodyPart: "Abdomen", sortOrder: 0)
        let second = Location(bodyPart: "Thigh", sortOrder: 1)
        context.insert(first)
        context.insert(second)
        let active = SiteChangeEntry(startTime: Date().addingTimeInterval(-3600), location: first)
        context.insert(active)
        try context.save()
        return (active, second)
    }

    private func importCSV(_ csv: String, context: ModelContext) throws -> CSVImporter.ImportResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return try CSVImporter.importCSV(from: url, context: context)
    }

    // MARK: - Logging

    @Test func logSiteChangeRecordsSeveralProblemsOnClosedEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (active, next) = try setUpActiveSite(context)
        let painful = SiteProblem(name: "Painful", emoji: "🤕", sortOrder: 0)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 1)
        context.insert(painful)
        context.insert(leaking)

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: next, note: nil, previousProblems: .replace([leaking, painful]))

        #expect(active.endTime != nil)
        #expect(active.safeProblems.map(\.name) == ["Painful", "Leaking"])
        let newEntry = try #require(SiteChangeEntry.fetchActive(in: context))
        #expect(!newEntry.hasProblems)
    }

    @Test func logSiteChangeLeavesProblemsUnchangedByDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (active, next) = try setUpActiveSite(context)
        let painful = SiteProblem(name: "Painful", emoji: "🤕")
        context.insert(painful)
        active.problems = [painful]
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: next, note: nil)

        #expect(active.safeProblems.map(\.id) == [painful.id])
    }

    @Test func logSiteChangeReplaceWithEmptyClearsProblems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (active, next) = try setUpActiveSite(context)
        let painful = SiteProblem(name: "Painful", emoji: "🤕")
        context.insert(painful)
        active.problems = [painful]
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: next, note: nil, previousProblems: .replace([]))

        #expect(!active.hasProblems)
    }

    @Test func logSiteChangeAppliesProblemsToShownEntryNotNewerActiveOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (shown, next) = try setUpActiveSite(context)
        let painful = SiteProblem(name: "Painful", emoji: "🤕")
        context.insert(painful)

        // While the sheet showed `shown`, a watch command logged another change.
        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: next, note: nil)
        let watchEntry = try #require(SiteChangeEntry.fetchActive(in: context))

        viewModel.logSiteChange(
            location: next,
            note: nil,
            previousNote: .replace("sore"),
            previousProblems: .replace([painful]),
            previousEntry: shown
        )

        #expect(shown.safeProblems.map(\.id) == [painful.id])
        #expect(shown.note == "sore")
        #expect(!watchEntry.hasProblems)
        #expect(watchEntry.note == nil)
        #expect(watchEntry.endTime != nil)
    }

    // MARK: - Early Change

    @Test func earlyChangeIsBelowThreeQuartersOfTarget() {
        #expect(EarlyChange.isEarly(durationHours: 31, targetHours: 72))
        #expect(EarlyChange.isEarly(durationHours: 53.9, targetHours: 72))
        #expect(!EarlyChange.isEarly(durationHours: 54, targetHours: 72))
        #expect(!EarlyChange.isEarly(durationHours: 80, targetHours: 72))
    }

    @Test func earlyChangeNeverTriggersWithoutTarget() {
        #expect(!EarlyChange.isEarly(durationHours: 1, targetHours: 0))
    }

    // MARK: - History

    @Test func historySetProblemsReplacesAndClears() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fellOff = SiteProblem(name: "Fell Off", emoji: "🩹", sortOrder: 0)
        let bleeding = SiteProblem(name: "Bleeding", emoji: "🩸", sortOrder: 1)
        let entry = SiteChangeEntry(startTime: Date().addingTimeInterval(-7200), endTime: Date())
        context.insert(fellOff)
        context.insert(bleeding)
        context.insert(entry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.setProblems(entry, problems: [bleeding, fellOff])
        #expect(entry.safeProblems.map(\.name) == ["Fell Off", "Bleeding"])
        #expect(fellOff.safeEntries.count == 1)

        viewModel.setProblems(entry, problems: [])
        #expect(!entry.hasProblems)
    }

    @Test func historyProblemFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 0)
        let painful = SiteProblem(name: "Painful", emoji: "🤕", sortOrder: 1)
        context.insert(leaking)
        context.insert(painful)
        let now = Date()
        let clean = SiteChangeEntry(startTime: now.addingTimeInterval(-300_000), endTime: now.addingTimeInterval(-200_000))
        let leaky = SiteChangeEntry(
            startTime: now.addingTimeInterval(-200_000),
            endTime: now.addingTimeInterval(-100_000),
            problems: [leaking]
        )
        let both = SiteChangeEntry(startTime: now.addingTimeInterval(-100_000), endTime: now, problems: [leaking, painful])
        [clean, leaky, both].forEach { context.insert($0) }
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        #expect(viewModel.filteredEntries.count == 3)

        viewModel.problemFilter = .anyProblem
        #expect(viewModel.filteredEntries.map(\.id) == [both.id, leaky.id])

        viewModel.problemFilter = .problem(painful)
        #expect(viewModel.filteredEntries.map(\.id) == [both.id])

        viewModel.problemFilter = .problem(leaking)
        #expect(viewModel.filteredEntries.count == 2)
    }

    // MARK: - CSV

    @Test func csvExportJoinsProblemNames() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", side: "left")
        let painful = SiteProblem(name: "Painful", emoji: "🤕", sortOrder: 0)
        let fellOff = SiteProblem(name: "Fell Off, Ripped", emoji: "🩹", sortOrder: 1)
        let entry = SiteChangeEntry(
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 3600),
            location: location,
            problems: [fellOff, painful]
        )
        context.insert(location)
        context.insert(painful)
        context.insert(fellOff)
        context.insert(entry)
        try context.save()

        let csv = CSVExporter.generate(from: [entry])

        #expect(csv.hasPrefix("date,location,duration_hours,note,problems\n"))
        #expect(csv.contains(",1.0,,\"Painful;Fell Off, Ripped\"\n"))
    }

    @Test func csvExportOmitsProblemsColumnWhenNoEntryHasOne() {
        let entry = SiteChangeEntry(startTime: Date(timeIntervalSince1970: 0))
        let csv = CSVExporter.generate(from: [entry])
        #expect(csv.hasPrefix("date,location,duration_hours,note\n"))
        #expect(!csv.contains("problems"))
    }

    @Test func csvImportMatchesExistingProblemsAndCreatesUnknownOnes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 0, defaultKey: "leaking")
        context.insert(leaking)
        try context.save()

        let result = try importCSV("""
        date,location,duration_hours,note,problems
        2024-01-15T10:30:00Z,L Abdomen,40.0,,leaking
        2024-01-17T02:30:00Z,R Abdomen,30.0,,Itchy; Leaking ;itchy
        2024-01-18T08:30:00Z,L Thigh,72.0,,
        2024-01-21T08:30:00Z,R Thigh,,,
        """, context: context)
        #expect(result.importedCount == 4)

        let entries = try context.fetch(
            FetchDescriptor<SiteChangeEntry>(sortBy: [SortDescriptor(\.startTime)])
        )
        #expect(entries[0].safeProblems.map(\.id) == [leaking.id])
        // Repeats (any case) collapse; unknown names become custom problems.
        #expect(Set(entries[1].safeProblems.map(\.name)) == ["Leaking", "Itchy"])
        #expect(entries[1].safeProblems.first { $0.name == "Itchy" }?.isCustom == true)
        #expect(!entries[2].hasProblems)
        #expect(!entries[3].hasProblems)
        #expect(try fetchProblems(context).count == 2)
    }

    @Test func csvImportGivesNewProblemsUniqueSortOrders() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Names collide case-insensitively, so only one is matchable by name,
        // but both must count toward the next sort order.
        context.insert(SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 2))
        context.insert(SiteProblem(name: "leaking", emoji: "💦", isCustom: true, sortOrder: 9))
        try context.save()

        _ = try importCSV("""
        date,location,duration_hours,note,problems
        2024-01-15T10:30:00Z,L Abdomen,40.0,,Itchy
        2024-01-17T02:30:00Z,R Abdomen,30.0,,Kinked
        """, context: context)

        #expect(try fetchProblems(context).map(\.sortOrder) == [2, 9, 10, 11])
    }
}
