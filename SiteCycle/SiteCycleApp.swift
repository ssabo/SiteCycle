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
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    seedDefaultLocations(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
