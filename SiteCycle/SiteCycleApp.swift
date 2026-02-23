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
                    migrateLocationBodyParts(context: context)
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
