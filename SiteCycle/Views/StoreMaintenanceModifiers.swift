import SwiftUI

private struct StoreMaintenanceKey: EnvironmentKey {
    static let defaultValue: StoreMaintenanceCoordinator? = nil
}

extension EnvironmentValues {
    /// The app's store maintenance coordinator. Optional, so a view without it
    /// (a preview, or onboarding's cover) still works; its holds do nothing.
    var storeMaintenance: StoreMaintenanceCoordinator? {
        get { self[StoreMaintenanceKey.self] }
        set { self[StoreMaintenanceKey.self] = newValue }
    }
}

extension View {
    /// Keeps the full maintenance pass from running while this view is shown.
    /// Use it on every sheet or editor that keeps a record across user
    /// interaction: the pass can delete a duplicate the view still shows or is
    /// about to save to.
    func holdsStoreMaintenance() -> some View {
        modifier(StoreMaintenanceHold())
    }

    /// Runs `action` after each store maintenance pass. Views that cache
    /// records refetch in it, because a pass can delete duplicates.
    func onStoreMaintenancePass(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .storeMaintenanceDidRun)) { _ in
            action()
        }
    }
}

private struct StoreMaintenanceHold: ViewModifier {
    @Environment(\.storeMaintenance) private var storeMaintenance
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { storeMaintenance?.beginHold(token) }
            .onDisappear { storeMaintenance?.endHold(token) }
    }
}
