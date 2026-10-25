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

    @Test func sanitizeEmojiRejectsNonEmoji() {
        #expect(SiteProblem.sanitizeEmoji("a").isEmpty)
        #expect(SiteProblem.sanitizeEmoji("1").isEmpty)
        #expect(SiteProblem.sanitizeEmoji("#").isEmpty)
        #expect(SiteProblem.sanitizeEmoji("🤕a") == "🤕")
    }

    @Test func sanitizeEmojiAcceptsTextStyleBaseWithVariationSelector() {
        #expect(SiteProblem.sanitizeEmoji("❤️") == "❤️")
        #expect(SiteProblem.sanitizeEmoji("1️⃣") == "1️⃣")
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
        let options = SiteProblem.pickerOptions(from: [enabled, disabled], including: [])
        #expect(options.map(\.name) == ["A"])
    }

    @Test func pickerOptionsKeepCurrentDisabledProblemInOrder() {
        let first = SiteProblem(name: "A", emoji: "🅰️", sortOrder: 0)
        let disabled = SiteProblem(name: "B", emoji: "🅱️", isEnabled: false, sortOrder: 1)
        let third = SiteProblem(name: "C", emoji: "©️", sortOrder: 2)
        let options = SiteProblem.pickerOptions(from: [third, disabled, first], including: [disabled])
        #expect(options.map(\.name) == ["A", "B", "C"])
    }

    @Test func pickerOptionsKeepOriginalAfterSelectionMovesAway() {
        let enabled = SiteProblem(name: "A", emoji: "🅰️", sortOrder: 0)
        let disabledOriginal = SiteProblem(name: "B", emoji: "🅱️", isEnabled: false, sortOrder: 1)
        // The user changed the selection from the disabled original to "A".
        let options = SiteProblem.pickerOptions(
            from: [enabled, disabledOriginal],
            including: [disabledOriginal, enabled]
        )
        #expect(options.map(\.name) == ["A", "B"])
    }

    // MARK: - Names

    @Test func nameTakenIsCaseAndWhitespaceInsensitive() {
        let leaking = SiteProblem(name: "Leaking", emoji: "💧")
        #expect(SiteProblem.isNameTaken(" leaking ", among: [leaking]))
        #expect(!SiteProblem.isNameTaken("Leak", among: [leaking]))
    }

    @Test func nameTakenIgnoresTheProblemBeingEdited() {
        let leaking = SiteProblem(name: "Leaking", emoji: "💧")
        let painful = SiteProblem(name: "Painful", emoji: "🤕")
        #expect(!SiteProblem.isNameTaken("LEAKING", among: [leaking, painful], excluding: leaking))
        #expect(SiteProblem.isNameTaken("Painful", among: [leaking, painful], excluding: leaking))
    }

    @Test func nameKeyIgnoresCaseAndSurroundingSpaces() {
        #expect(SiteProblem.nameKey("  Leaking ") == SiteProblem.nameKey("leaking"))
        #expect(SiteProblem.nameKey("Leak") != SiteProblem.nameKey("Leaking"))
    }

    @Test func nameErrorRejectsEmptySeparatorAndDuplicates() {
        let leaking = SiteProblem(name: "Leaking", emoji: "💧")
        #expect(SiteProblem.nameError("  ", among: [leaking]) != nil)
        #expect(SiteProblem.nameError("Sore; red", among: [leaking]) != nil)
        #expect(SiteProblem.nameError("leaking", among: [leaking]) != nil)
        #expect(SiteProblem.nameError("leaking", among: [leaking], excluding: leaking) == nil)
        #expect(SiteProblem.nameError("Itchy", among: [leaking]) == nil)
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

    @Test func deduplicateKeepsLowestIDAndMovesEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // The keeper is chosen by id, not entry count, so two devices that
        // deduplicate before syncing agree on which copy survives.
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000"))
        // Both pristine (Leaking is seeded at index 1), so only the id decides.
        let duplicate = SiteProblem(id: highID, name: "Leaking", emoji: "💧", sortOrder: 1, defaultKey: "leaking")
        let keeper = SiteProblem(id: lowID, name: "Leaking", emoji: "💧", sortOrder: 1, defaultKey: "leaking")
        context.insert(duplicate)
        context.insert(keeper)
        let location = Location(bodyPart: "Abdomen")
        context.insert(location)
        let entry1 = SiteChangeEntry(location: location, problems: [duplicate])
        let entry2 = SiteChangeEntry(location: location, problems: [duplicate, keeper])
        let entry3 = SiteChangeEntry(location: location, problems: [keeper])
        [entry1, entry2, entry3].forEach { context.insert($0) }
        try context.save()

        deduplicateProblems(context: context)

        let problems = try fetchProblems(context)
        #expect(problems.count == 1)
        #expect(problems.first?.id == lowID)
        #expect(entry1.safeProblems.map(\.id) == [lowID])
        // An entry that had both copies ends up with the keeper once.
        #expect(entry2.safeProblems.map(\.id) == [lowID])
        #expect(entry3.safeProblems.map(\.id) == [lowID])
        #expect(keeper.safeEntries.count == 3)
    }

    @Test func deduplicatePrefersCustomizedCopy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000"))
        let pristine = SiteProblem(id: lowID, name: "Bleeding", emoji: "🩸", sortOrder: 5, defaultKey: "bleeding")
        let renamed = SiteProblem(id: highID, name: "Blood", emoji: "🩸", isEnabled: false, sortOrder: 5, defaultKey: "bleeding")
        context.insert(pristine)
        context.insert(renamed)
        try context.save()

        deduplicateProblems(context: context)

        let problems = try fetchProblems(context)
        #expect(problems.count == 1)
        #expect(problems.first?.name == "Blood")
        #expect(problems.first?.isEnabled == false)
    }

    @Test func entryDeduplicationKeepsProblemsFromBothCopies() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let start = Date(timeIntervalSince1970: 1_000_000)
        let location = Location(bodyPart: "Abdomen")
        let painful = SiteProblem(name: "Painful", emoji: "🤕", sortOrder: 0)
        let leaking = SiteProblem(name: "Leaking", emoji: "💧", sortOrder: 1)
        context.insert(location)
        context.insert(painful)
        context.insert(leaking)
        context.insert(SiteChangeEntry(startTime: start, location: location, problems: [painful]))
        context.insert(SiteChangeEntry(startTime: start, location: location, problems: [painful, leaking]))
        try context.save()

        deduplicateSiteChangeEntries(context: context)

        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.safeProblems.map(\.name) == ["Painful", "Leaking"])
    }

    @Test func deduplicatePrefersReorderedCopy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Bleeding is seeded at index 5; the user dragged one copy to the top.
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000"))
        context.insert(SiteProblem(id: lowID, name: "Bleeding", emoji: "🩸", sortOrder: 5, defaultKey: "bleeding"))
        context.insert(SiteProblem(id: highID, name: "Bleeding", emoji: "🩸", sortOrder: 0, defaultKey: "bleeding"))
        try context.save()

        deduplicateProblems(context: context)

        let problems = try fetchProblems(context)
        #expect(problems.map(\.id) == [highID])
        #expect(problems.first?.sortOrder == 0)
    }

    @Test func deduplicateMergesSameNamedCustomProblemsKeepingEnabledOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000"))
        let disabled = SiteProblem(id: lowID, name: "Kinked", emoji: "➰", isEnabled: false, isCustom: true)
        let enabled = SiteProblem(id: highID, name: " kinked ", emoji: "➰", isCustom: true, sortOrder: 1)
        context.insert(disabled)
        context.insert(enabled)
        let entry = SiteChangeEntry(problems: [disabled])
        context.insert(entry)
        try context.save()

        deduplicateProblems(context: context)

        let problems = try fetchProblems(context)
        #expect(problems.map(\.id) == [highID])
        #expect(entry.safeProblems.map(\.id) == [highID])
    }

    @Test func entryDeduplicationKeepsLowestIDRegardlessOfFetchOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let start = Date(timeIntervalSince1970: 1_000_000)
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000"))
        context.insert(SiteChangeEntry(id: highID, startTime: start))
        context.insert(SiteChangeEntry(id: lowID, startTime: start))
        try context.save()

        deduplicateSiteChangeEntries(context: context)

        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.map(\.id) == [lowID])
    }

    @Test func deletingProblemNullifiesEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let problem = SiteProblem(name: "Itchy", emoji: "🐜", isCustom: true)
        let entry = SiteChangeEntry(problems: [problem])
        context.insert(problem)
        context.insert(entry)
        try context.save()

        context.delete(problem)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<SiteChangeEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.hasProblems == false)
    }
}
