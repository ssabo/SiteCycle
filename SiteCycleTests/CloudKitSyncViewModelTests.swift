import Testing
@testable import SiteCycle

@MainActor
struct CloudKitSyncViewModelTests {
    @Test func initialStateIsLocalOnlyWhenDisabled() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: false)
        #expect(vm.state == .localOnly)
    }

    @Test func initialStateIsSyncedWhenEnabled() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        #expect(vm.state == .synced)
    }

    @Test func networkOfflineSetsOfflineState() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.updateNetworkState(isConnected: false)
        #expect(vm.state == .offline)
    }

    @Test func networkOnlineFromOfflineRestoresSynced() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.updateNetworkState(isConnected: false)
        vm.updateNetworkState(isConnected: true)
        #expect(vm.state == .synced)
    }

    @Test func localOnlyIgnoresNetworkChanges() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: false)
        vm.updateNetworkState(isConnected: false)
        #expect(vm.state == .localOnly)
    }

    @Test func handleTapInErrorStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.setStateForTesting(.error("Test error"))
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage == "Test error")
    }

    @Test func handleTapInLocalOnlyStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: false)
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage == "iCloud is not available. Your data is stored on this device only.")
    }

    @Test func handleTapInOfflineStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.setStateForTesting(.offline)
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage?.starts(with: "No network connection.") == true)
    }

    @Test func handleTapInNoAccountStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.setStateForTesting(.noAccount)
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage == "Sign in to iCloud in Settings to sync your data across devices.")
    }

    @Test func handleTapInSyncingStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.setStateForTesting(.syncing)
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage?.starts(with: "Syncing with iCloud") == true)
    }

    @Test func handleTapInSyncedStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage == "iCloud sync is active.")
    }
}
