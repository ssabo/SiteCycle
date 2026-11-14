import SwiftUI
import SwiftData

@main
struct SiteCycleApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    let sharedModelContainer: ModelContainer
    let isCloudKitEnabled: Bool
    @State private var connectivityManager = PhoneConnectivityManager()
    @State private var storeMaintenance = StoreMaintenanceCoordinator()

    init() {
        Self.applyUITestLaunchArguments()
        let result = Self.makeModelContainer()
        sharedModelContainer = result.0
        isCloudKitEnabled = result.1
    }

    static func applyUITestLaunchArguments() {
        if ProcessInfo.processInfo.arguments.contains("-completeOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    static func makeModelContainer() -> (ModelContainer, Bool) {
        let schema = Schema([
            Location.self,
            SiteChangeEntry.self,
            SiteProblem.self,
        ])

        if ProcessInfo.processInfo.arguments.contains("-uiTestMode") {
            let testConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                let container = try ModelContainer(for: schema, configurations: [testConfig])
                return (container, false)
            } catch {
                fatalError("Could not create in-memory ModelContainer for UI tests: \(error)")
            }
        }

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
                    storeMaintenance.start(context: context, isCloudKitEnabled: isCloudKitEnabled)
                    connectivityManager.configure(modelContext: context)
                    connectivityManager.pushCurrentState()
                }
                .onReceive(NotificationCenter.default.publisher(for: .storeMaintenanceDidChangeData)) { _ in
                    connectivityManager.pushCurrentState()
                }
                .environment(connectivityManager)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { newValue in hasCompletedOnboarding = !newValue }
                )) {
                    // The `.environment` above reaches only ContentView, not this cover.
                    OnboardingView()
                        .environment(connectivityManager)
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                connectivityManager.pushCurrentState()
            }
        }
    }
}
