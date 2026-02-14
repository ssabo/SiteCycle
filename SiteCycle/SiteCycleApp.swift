import SwiftUI
import SwiftData

@main
struct SiteCycleApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let sharedModelContainer: ModelContainer = {
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
            return try ModelContainer(
                for: schema,
                configurations: [cloudConfig]
            )
        } catch {
            // CloudKit unavailable (e.g. CI, no entitlements) — fall back to local storage
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [localConfig]
                )
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    seedDefaultLocations(context: sharedModelContainer.mainContext)
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
