import Testing
import CloudKit
@testable import SiteCycle

@MainActor
struct CloudKitSyncViewModelTests {
    @Test func initialStateIsLocalOnlyWhenDisabled() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: false)
        #expect(vm.state == .localOnly)
    }

    @Test func initialStateIsWaitingWhenEnabled() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        #expect(vm.state == .waiting)
    }

    @Test func waitingStateProperties() {
        let state = CloudKitSyncState.waiting
        #expect(state.iconName == "icloud")
        #expect(state.accessibilityLabel == "Waiting for iCloud sync…")
        #expect(state.alertTitle == "Connecting")
    }

    @Test func waitingTransitionsToSyncedOnSuccessfulEvent() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        #expect(vm.state == .waiting)
        vm.setStateForTesting(.synced)
        #expect(vm.state == .synced)
    }

    @Test func networkOfflineSetsOfflineState() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.updateNetworkState(isConnected: false)
        #expect(vm.state == .offline)
    }

    @Test func networkOnlineFromOfflineRestoresWaiting() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.updateNetworkState(isConnected: false)
        vm.updateNetworkState(isConnected: true)
        #expect(vm.state == .waiting)
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

    @Test func handleTapInWaitingStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage == "Waiting for the first iCloud sync to complete.")
    }

    @Test func handleTapInSyncedStateSetsAlert() {
        let vm = CloudKitSyncViewModel(isCloudKitEnabled: true)
        vm.setStateForTesting(.synced)
        vm.handleTap()
        #expect(vm.showingStatusAlert == true)
        #expect(vm.statusAlertMessage == "iCloud sync is active.")
    }

    // MARK: - fromSyncError tests

    @Test func fromSyncErrorNetworkUnavailableMapsToOffline() {
        let error = CKError(CKError.networkUnavailable)
        #expect(CloudKitSyncState.fromSyncError(error) == .offline)
    }

    @Test func fromSyncErrorNetworkFailureMapsToOffline() {
        let error = CKError(CKError.networkFailure)
        #expect(CloudKitSyncState.fromSyncError(error) == .offline)
    }

    @Test func fromSyncErrorServiceUnavailableMapsFriendly() {
        let error = CKError(CKError.serviceUnavailable)
        let state = CloudKitSyncState.fromSyncError(error)
        #expect(state == .error("iCloud is temporarily unavailable. Sync will retry automatically."))
    }

    @Test func fromSyncErrorRateLimitedMapsFriendly() {
        let error = CKError(CKError.requestRateLimited)
        let state = CloudKitSyncState.fromSyncError(error)
        #expect(state == .error("iCloud is busy. Sync will retry shortly."))
    }

    @Test func fromSyncErrorNotAuthenticatedMapsToNoAccount() {
        let error = CKError(CKError.notAuthenticated)
        #expect(CloudKitSyncState.fromSyncError(error) == .noAccount)
    }

    @Test func fromSyncErrorUnknownNSErrorMapsGeneric() {
        let error = NSError(domain: "TestDomain", code: 999)
        let state = CloudKitSyncState.fromSyncError(error)
        #expect(state == .error("Sync failed. Tap for details."))
    }
}
