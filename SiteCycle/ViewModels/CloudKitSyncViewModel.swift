import SwiftUI
import Foundation
import Observation
import Network
import CloudKit
import CoreData

enum CloudKitSyncState: Equatable {
    case localOnly
    case offline
    case noAccount
    case syncing
    case synced
    case error(String)

    var iconName: String {
        switch self {
        case .localOnly: return "internaldrive"
        case .offline: return "icloud.slash"
        case .noAccount: return "person.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    var foregroundColor: AnyShapeStyle {
        switch self {
        case .localOnly, .offline, .synced: return AnyShapeStyle(.secondary)
        case .noAccount: return AnyShapeStyle(Color.orange)
        case .syncing: return AnyShapeStyle(.tint)
        case .error: return AnyShapeStyle(Color.red)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .localOnly: return "Stored locally — iCloud not available"
        case .offline: return "Offline — sync paused"
        case .noAccount: return "Sign in to iCloud to enable sync"
        case .syncing: return "Syncing with iCloud…"
        case .synced: return "iCloud synced"
        case .error: return "Sync error — tap for details"
        }
    }

    var alertTitle: String {
        switch self {
        case .localOnly: return "Local Storage"
        case .offline: return "Offline"
        case .noAccount: return "iCloud Unavailable"
        case .syncing: return "Syncing"
        case .synced: return "iCloud Sync"
        case .error: return "Sync Error"
        }
    }

    func alertMessage(lastSyncDate: Date?) -> String {
        switch self {
        case .localOnly:
            return "iCloud is not available. Your data is stored on this device only."
        case .offline:
            return "No network connection. Sync will resume when you're back online."
                + Self.lastSyncSuffix(lastSyncDate)
        case .noAccount:
            return "Sign in to iCloud in Settings to sync your data across devices."
        case .syncing:
            return "Syncing with iCloud…"
                + Self.lastSyncSuffix(lastSyncDate)
        case .synced:
            return Self.syncedMessage(lastSyncDate)
        case .error(let message):
            return message
        }
    }

    private static func lastSyncSuffix(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\nLast synced \(formatter.localizedString(for: date, relativeTo: Date()))."
    }

    private static func syncedMessage(_ date: Date?) -> String {
        guard let date else { return "iCloud sync is active." }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last synced \(formatter.localizedString(for: date, relativeTo: Date()))."
    }
}

@MainActor @Observable final class CloudKitSyncViewModel {
    private(set) var state: CloudKitSyncState
    private(set) var lastSyncDate: Date?
    var showingStatusAlert = false
    var statusAlertMessage: String?

    private let isCloudKitEnabled: Bool
    private var networkMonitor: NWPathMonitor?
    private var cloudKitEventTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?
    private var accountObserver: NSObjectProtocol?

    init(isCloudKitEnabled: Bool) {
        self.isCloudKitEnabled = isCloudKitEnabled
        if isCloudKitEnabled {
            state = .synced
            startMonitoring()
        } else {
            state = .localOnly
        }
    }

    func handleTap() {
        statusAlertMessage = state.alertMessage(lastSyncDate: lastSyncDate)
        showingStatusAlert = true
    }

    func updateNetworkState(isConnected: Bool) {
        guard state != .localOnly else { return }
        if !isConnected {
            state = .offline
        } else if state == .offline {
            state = .synced
            accountTask = Task { await checkAccountStatus() }
        }
    }

    func setStateForTesting(_ newState: CloudKitSyncState) {
        state = newState
    }

    private func startMonitoring() {
        startNetworkMonitor()
        cloudKitEventTask = observeCloudKitEvents()
        accountTask = Task { await checkAccountStatus() }
        observeAccountChanges()
    }

    private func stopMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
        cloudKitEventTask?.cancel()
        cloudKitEventTask = nil
        accountTask?.cancel()
        accountTask = nil
        if let observer = accountObserver {
            NotificationCenter.default.removeObserver(observer)
            accountObserver = nil
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.updateNetworkState(isConnected: connected)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func observeCloudKitEvents() -> Task<Void, Never> {
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                self?.handleCloudKitEvent(notification)
            }
        }
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return }
        applyEvent(event)
    }

    private func applyEvent(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            state = .syncing
        } else if event.succeeded {
            state = .synced
            lastSyncDate = event.endDate
        } else {
            let message = event.error?.localizedDescription ?? "Unknown error"
            state = .error(message)
        }
    }

    private func observeAccountChanges() {
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAccountStatus()
            }
        }
    }

    private func checkAccountStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            if status != .available {
                if state != .offline && state != .localOnly {
                    state = .noAccount
                }
            } else if state == .noAccount {
                state = .synced
            }
        } catch {
            // Ignore account status errors silently
        }
    }
}
