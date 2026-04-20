import Foundation
import SwiftData

private struct FixtureEntry: Decodable {
    let side: String?
    let bodyPart: String
    let subArea: String?
    let startOffsetHours: Double
    let endOffsetHours: Double?
    let note: String?
}

private struct HistoryFixture: Decodable {
    let entries: [FixtureEntry]
}

/// Loads a named history fixture from the app bundle and inserts entries into
/// the provided context. No-op unless the app is running under `-uiTestMode`.
/// Also no-op if any `SiteChangeEntry` rows already exist, so repeated
/// `onAppear` firings (scene transitions, cover dismissals) don't double-seed.
@MainActor
func seedHistoryFromFixture(named name: String, context: ModelContext) {
    guard ProcessInfo.processInfo.arguments.contains("-uiTestMode") else { return }

    let existingCount = (try? context.fetchCount(FetchDescriptor<SiteChangeEntry>())) ?? 0
    guard existingCount == 0 else { return }

    let bundleURL = Bundle.main.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Fixtures"
    ) ?? Bundle.main.url(forResource: name, withExtension: "json")

    guard let url = bundleURL else {
        print("[FixtureLoader] Fixture not found in bundle: \(name)")
        return
    }

    do {
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(HistoryFixture.self, from: data)

        let locations = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        let now = Date()

        for entry in fixture.entries {
            guard let location = locations.first(where: {
                $0.side == entry.side
                    && $0.bodyPart == entry.bodyPart
                    && $0.subArea == entry.subArea
            }) else {
                print("[FixtureLoader] No matching location for \(entry.bodyPart)")
                continue
            }

            let startTime = now.addingTimeInterval(entry.startOffsetHours * 3600)
            let endTime = entry.endOffsetHours.map { now.addingTimeInterval($0 * 3600) }

            let siteEntry = SiteChangeEntry(
                startTime: startTime,
                endTime: endTime,
                note: entry.note,
                location: location
            )
            context.insert(siteEntry)
        }

        try? context.save()
    } catch {
        print("[FixtureLoader] Failed to load fixture \(name): \(error)")
    }
}

/// Reads `-seedHistory <name>` from launch args and seeds if present.
@MainActor
func applySeedHistoryLaunchArgumentIfPresent(context: ModelContext) {
    let args = ProcessInfo.processInfo.arguments
    guard let idx = args.firstIndex(of: "-seedHistory"),
          idx + 1 < args.count else { return }
    let name = args[idx + 1]
    seedHistoryFromFixture(named: name, context: context)
}
