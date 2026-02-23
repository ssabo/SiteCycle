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

    @Test func handleErrorTapSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.setStateForTesting(.error("Test error"))
        vm.handleErrorTap()
        #expect(vm.showingErrorAlert == true)
        #expect(vm.errorAlertMessage == "Test error")
    }
}
