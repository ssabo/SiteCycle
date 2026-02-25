import SwiftUI
import SwiftData
import WidgetKit

@main
struct SiteCycleWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let sharedModelContainer: ModelContainer

    init() {
        sharedModelContainer = Self.makeModelContainer()
    }

    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Location.self,
            SiteChangeEntry.self,
        ])

        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.sitecycle.app"
        )
        let storeURL = appGroupURL?.appendingPathComponent("SiteCycle.store")

        if let storeURL {
            let cloudConfig = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .automatic
            )
            do {
                return try ModelContainer(for: schema, configurations: [cloudConfig])
            } catch {
                print("CloudKit ModelContainer failed: \(error)")
            }
        }

        // Fallback: local storage without App Group (e.g. CI, no entitlements)
        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    seedDefaultLocations(context: context)
                    migrateLocationBodyParts(context: context)
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
