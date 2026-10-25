import Testing
import Foundation
import SwiftData
@testable import SiteCycle

@MainActor
struct SiteProblemTests {

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

    // MARK: - Emoji

    @Test func sanitizeEmojiKeepsSingleEmoji() {
        #expect(SiteProblem.sanitizeEmoji("💧") == "💧")
    }

    @Test func sanitizeEmojiKeepsLastTyped() {
        #expect(SiteProblem.sanitizeEmoji("💧🤕") == "🤕")
    }

    @Test func sanitizeEmojiKeepsMultiScalarEmojiIntact() {
        #expect(SiteProblem.sanitizeEmoji("👍🏽") == "👍🏽")
        #expect(SiteProblem.sanitizeEmoji("❤️‍🩹") == "❤️‍🩹")
    }

    @Test func sanitizeEmojiIgnoresWhitespace() {
        #expect(SiteProblem.sanitizeEmoji("🩹 ") == "🩹")
        #expect(SiteProblem.sanitizeEmoji("   ").isEmpty)
        #expect(SiteProblem.sanitizeEmoji("").isEmpty)
    }

    @Test func displayEmojiFallsBackWhenEmpty() {
        let problem = SiteProblem(name: "Itchy", emoji: "")
        #expect(problem.displayEmoji == SiteProblem.fallbackEmoji)
        #expect(problem.labelText == "\(SiteProblem.fallbackEmoji) Itchy")
    }

    // MARK: - Picker Options

    @Test func pickerOptionsHideDisabledProblems() {
        let enabled = SiteProblem(name: "A", emoji: "🅰️", sortOrder: 0)
        let disabled = SiteProblem(name: "B", emoji: "🅱️", isEnabled: false, sortOrder: 1)
        let options = SiteProblem.pickerOptions(from: [enabled, disabled], including: nil)
        #expect(options.map(\.name) == ["A"])
    }

    @Test func pickerOptionsKeepCurrentDisabledProblemInOrder() {
        let first = SiteProblem(name: "A", emoji: "🅰️", sortOrder: 0)
        let disabled = SiteProblem(name: "B", emoji: "🅱️", isEnabled: false, sortOrder: 1)
        let third = SiteProblem(name: "C", emoji: "©️", sortOrder: 2)
        let options = SiteProblem.pickerOptions(from: [third, disabled, first], including: disabled)
        #expect(options.map(\.name) == ["A", "B", "C"])
    }

    // MARK: - Seeding

    @Test func seedInsertsAllDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultProblems(context: context)

        let problems = try fetchProblems(context)
        #expect(problems.count == DefaultProblems.all.count)
        #expect(problems.map(\.defaultKey) == DefaultProblems.all.map { Optional($0.key) })
        #expect(problems.allSatisfy { !$0.isCustom && $0.isEnabled && !$0.emoji.isEmpty })
        let names = Set(problems.map(\.name))
        #expect(names.contains("Painful"))
        #expect(names.contains("Leaking"))
        #expect(names.contains("Fell Off / Ripped Off"))
    }

    @Test func seedIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        seedDefaultProblems(context: context)
        seedDefaultProblems(context: context)

        #expect(try fetchProblems(context).count == DefaultProblems.all.count)
    }

    @Test func seedKeepsUserEditsAndAddsOnlyMissingDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let renamed = SiteProblem(name: "Ouch", emoji: "😖", sortOrder: 0, defaultKey: "painful")
        let custom = SiteProblem(name: "Itchy", emoji: "🐜", isCustom: true, sortOrder: 1)
        context.insert(renamed)
        context.insert(custom)
        try context.save()

        seedDefaultProblems(context: context)

        let problems = try fetchProblems(context)
        #expect(problems.count == DefaultProblems.all.count + 1)
        #expect(problems.filter { $0.defaultKey == "painful" }.count == 1)
        #expect(renamed.name == "Ouch")
        #expect(renamed.emoji == "😖")
        // New defaults go after the existing ones.
        let seeded = problems.filter { $0.defaultKey != nil && $0.defaultKey != "painful" }
        #expect(seeded.allSatisfy { $0.sortOrder > custom.sortOrder })
    }

    // MARK: - Deduplication

    @Test func deduplicateMergesDefaultsAndMovesEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let keeper = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 1, defaultKey: "leaking")
        let duplicate = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 7, defaultKey: "leaking")
        context.insert(keeper)
        context.insert(duplicate)
        let location = Location(bodyPart: "Abdomen")
        context.insert(location)
        let entry1 = SiteChangeEntry(location: location, problem: keeper)
        let entry2 = SiteChangeEntry(location: location, problem: keeper)
        let entry3 = SiteChangeEntry(location: location, problem: duplicate)
        context.insert(entry1)
        context.insert(entry2)
        context.insert(entry3)
        try context.save()

        deduplicateProblems(context: context)

        let problems = try fetchProblems(context)
        #expect(problems.count == 1)
        #expect(problems.first?.id == keeper.id)
        #expect(entry3.problem?.id == keeper.id)
        #expect(keeper.safeEntries.count == 3)
    }

    @Test func deduplicateLeavesCustomProblemsAlone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(SiteProblem(name: "Itchy", emoji: "🐜", isCustom: true, sortOrder: 0))
        context.insert(SiteProblem(name: "Itchy", emoji: "🐜", isCustom: true, sortOrder: 1))
        try context.save()

        deduplicateProblems(context: context)

        #expect(try fetchProblems(context).count == 2)
    }

    @Test func deletingProblemNullifiesEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let problem = SiteProblem(name: "Itchy", emoji: "🐜", isCustom: true)
        let entry = SiteChangeEntry(problem: problem)
        context.insert(problem)
        context.insert(entry)
        try context.save()

        context.delete(problem)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.problem == nil)
    }
}

// MARK: - Logging, History & CSV

extension SiteProblemTests {

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

    @Test func logSiteChangeRecordsProblemOnClosedEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (active, next) = try setUpActiveSite(context)
        let problem = SiteProblem(name: "Leaking", emoji: "💧")
        context.insert(problem)

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: next, note: nil, previousProblem: .replace(problem))

        #expect(active.endTime != nil)
        #expect(active.problem?.id == problem.id)
        let newEntry = try #require(SiteChangeEntry.fetchActive(in: context))
        #expect(newEntry.problem == nil)
    }

    @Test func logSiteChangeLeavesProblemUnchangedByDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (active, next) = try setUpActiveSite(context)
        let problem = SiteProblem(name: "Painful", emoji: "🤕")
        context.insert(problem)
        active.problem = problem
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: next, note: nil)

        #expect(active.problem?.id == problem.id)
    }

    @Test func logSiteChangeReplaceWithNilClearsProblem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (active, next) = try setUpActiveSite(context)
        let problem = SiteProblem(name: "Painful", emoji: "🤕")
        context.insert(problem)
        active.problem = problem
        try context.save()

        let viewModel = SiteChangeViewModel(modelContext: context)
        viewModel.logSiteChange(location: next, note: nil, previousProblem: .replace(nil))

        #expect(active.problem == nil)
    }

    @Test func historySetProblemSetsAndClears() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let problem = SiteProblem(name: "Fell Off", emoji: "🩹")
        let entry = SiteChangeEntry(startTime: Date().addingTimeInterval(-7200), endTime: Date())
        context.insert(problem)
        context.insert(entry)
        try context.save()

        let viewModel = HistoryViewModel(modelContext: context)
        viewModel.setProblem(entry, problem: problem)
        #expect(entry.problem?.id == problem.id)
        #expect(problem.safeEntries.count == 1)

        viewModel.setProblem(entry, problem: nil)
        #expect(entry.problem == nil)
    }

    @Test func csvExportIncludesProblemName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let location = Location(bodyPart: "Abdomen", side: "left")
        let problem = SiteProblem(name: "Fell Off, Ripped", emoji: "🩹")
        let entry = SiteChangeEntry(
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 3600),
            location: location,
            problem: problem
        )
        context.insert(location)
        context.insert(problem)
        context.insert(entry)
        try context.save()

        let csv = CSVExporter.generate(from: [entry])

        #expect(csv.hasPrefix("date,location,duration_hours,note,problem\n"))
        #expect(csv.contains(",1.0,,\"Fell Off, Ripped\"\n"))
    }

    @Test func csvImportMatchesExistingProblemsAndCreatesUnknownOnes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 0, defaultKey: "leaking")
        context.insert(leaking)
        try context.save()

        let csv = """
        date,location,duration_hours,note,problem
        2024-01-15T10:30:00Z,L Abdomen,40.0,,leaking
        2024-01-17T02:30:00Z,R Abdomen,30.0,,Itchy
        2024-01-18T08:30:00Z,L Thigh,72.0,,
        2024-01-21T08:30:00Z,R Thigh,,,
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let result = try CSVImporter.importCSV(from: url, context: context)
        #expect(result.importedCount == 4)

        let entries = try context.fetch(
            FetchDescriptor<SiteChangeEntry>(sortBy: [SortDescriptor(\.startTime)])
        )
        #expect(entries[0].problem?.id == leaking.id)
        #expect(entries[1].problem?.name == "Itchy")
        #expect(entries[1].problem?.isCustom == true)
        #expect(entries[2].problem == nil)
        #expect(entries[3].problem == nil)
        #expect(try fetchProblems(context).count == 2)
    }
}
