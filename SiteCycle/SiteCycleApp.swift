import SwiftUI
import SwiftData

@main
struct SiteCycleApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let sharedModelContainer: ModelContainer
    let isCloudKitEnabled: Bool

    init() {
        let result = Self.makeModelContainer()
        sharedModelContainer = result.0
        isCloudKitEnabled = result.1
    }

    private func setupWatchConnectivity(context: ModelContext) {
        WatchConnectivityManager.shared.activate()
        WatchConnectivityManager.shared.logHandler = { locationID in
            let desc = FetchDescriptor<Location>(
                predicate: #Predicate { $0.id == locationID }
            )
            guard let location = try? context.fetch(desc).first else { return nil }
            let now = Date()
            var activeDesc = FetchDescriptor<SiteChangeEntry>(
                predicate: #Predicate { $0.endTime == nil },
                sortBy: [SortDescriptor(\SiteChangeEntry.startTime, order: .reverse)]
            )
            activeDesc.fetchLimit = 1
            if let active = try? context.fetch(activeDesc).first {
                active.endTime = now
            }
            let entry = SiteChangeEntry(startTime: now, note: nil, location: location)
            context.insert(entry)
            try? context.save()
            return (location.fullDisplayName, now)
        }
    }

    static func makeModelContainer() -> (ModelContainer, Bool) {
        let schema = Schema([
            Location.self,
            SiteChangeEntry.self,
        ])
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [cloudConfig]
            )
            return (container, true)
        } catch {
            print("CloudKit ModelContainer failed: \(error)")
            // CloudKit unavailable (e.g. CI, no entitlements) — fall back to local storage
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                let container = try ModelContainer(
                    for: schema,
                    configurations: [localConfig]
                )
                return (container, false)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(isCloudKitEnabled: isCloudKitEnabled)
                .onAppear {
                    let context = sharedModelContainer.mainContext
                    seedDefaultLocations(context: context)
                    deduplicateLocations(context: context)
                    migrateLocationBodyParts(context: context)
                    setupWatchConnectivity(context: context)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { newValue in hasCompletedOnboarding = !newValue }
                )) {
                    OnboardingView()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
