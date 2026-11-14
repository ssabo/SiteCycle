import SwiftUI
import Foundation
import Observation
import Network
import CloudKit
import CoreData
import os

enum CloudKitSyncState: Equatable {
    case localOnly
    case waiting
    case offline
    case noAccount
    case syncing
    case synced
    case error(String)

    var iconName: String {
        switch self {
        case .localOnly: return "internaldrive"
        case .waiting: return "icloud"
        case .offline: return "icloud.slash"
        case .noAccount: return "person.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    var foregroundColor: AnyShapeStyle {
        switch self {
        case .localOnly, .waiting, .offline, .synced: return AnyShapeStyle(.secondary)
        case .noAccount: return AnyShapeStyle(Color.orange)
        case .syncing: return AnyShapeStyle(.tint)
        case .error: return AnyShapeStyle(Color.red)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .localOnly: return "Stored locally — iCloud not available"
        case .waiting: return "Waiting for iCloud sync…"
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
        case .waiting: return "Connecting"
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
        case .waiting:
            return "Waiting for the first iCloud sync to complete."
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

    static func fromSyncError(_ error: (any Error)?) -> CloudKitSyncState {
        guard let error else {
            return .error("Sync failed with an unknown error.")
        }
        let nsError = error as NSError

        // Check for direct CKError
        if let state = classifyCKError(nsError) {
            return state
        }

        // Check for CoreData-CloudKit error codes (NSCocoaErrorDomain)
        if nsError.domain == NSCocoaErrorDomain {
            if let state = classifyCocoaError(nsError) {
                return state
            }
        }

        // Search underlying errors for wrapped CKErrors
        if let state = findCKErrorInChain(nsError) {
            return state
        }

        return .error("\(nsError.localizedDescription)\n\nError: \(nsError.domain) \(nsError.code)")
    }

    private static func classifyCKError(_ nsError: NSError) -> CloudKitSyncState? {
        guard nsError.domain == CKError.errorDomain,
              let code = CKError.Code(rawValue: nsError.code) else {
            return nil
        }
        switch code {
        case .networkUnavailable, .networkFailure:
            return .offline
        case .serviceUnavailable:
            return .error(
                "iCloud is temporarily unavailable. Sync will retry automatically."
                + "\n\nError: \(nsError.domain) \(nsError.code)"
            )
        case .requestRateLimited, .zoneBusy:
            return .error(
                "iCloud is busy. Sync will retry shortly."
                + "\n\nError: \(nsError.domain) \(nsError.code)"
            )
        case .notAuthenticated:
            return .noAccount
        case .partialFailure:
            return classifyPartialFailure(nsError)
        default:
            return nil
        }
    }

    private static func classifyPartialFailure(_ nsError: NSError) -> CloudKitSyncState {
        guard let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError],
              !partialErrors.isEmpty else {
            return .error(
                "iCloud sync encountered partial errors. Sync will retry automatically."
                + "\n\nError: \(nsError.domain) \(nsError.code)"
            )
        }
        for (_, innerError) in partialErrors {
            if let innerState = classifyCKError(innerError) {
                return innerState
            }
        }
        let details = summarizePartialErrors(partialErrors)
        return .error(
            "iCloud sync encountered partial errors. Sync will retry automatically."
            + "\n\nError: \(nsError.domain) \(nsError.code)"
            + "\nDetails: \(details)"
        )
    }

    private static func summarizePartialErrors(_ errors: [AnyHashable: NSError]) -> String {
        var counts: [String: Int] = [:]
        for (_, error) in errors {
            let key = "\(error.domain) \(error.code)"
            counts[key, default: 0] += 1
        }
        return counts
            .sorted { $0.key < $1.key }
            .map { $0.value > 1 ? "\($0.key) (x\($0.value))" : $0.key }
            .joined(separator: ", ")
    }

    private static func classifyCocoaError(_ nsError: NSError) -> CloudKitSyncState? {
        switch nsError.code {
        case 134400, 134405:
            return .noAccount
        default:
            return nil
        }
    }

    private static func findCKErrorInChain(_ nsError: NSError) -> CloudKitSyncState? {
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            if let state = classifyCKError(underlying) { return state }
            if let state = findCKErrorInChain(underlying) { return state }
        }
        if let errors = nsError.userInfo["NSMultipleUnderlyingErrorsKey"] as? [NSError],
           let state = findStateInErrors(errors) { return state }
        if let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError],
           let state = findStateInErrors(Array(partialErrors.values)) { return state }
        return nil
    }

    private static func findStateInErrors(_ errors: [NSError]) -> CloudKitSyncState? {
        for error in errors {
            if let state = classifyCKError(error) { return state }
            if let state = findCKErrorInChain(error) { return state }
        }
        return nil
    }
}

@MainActor @Observable final class CloudKitSyncViewModel {
    private(set) var state: CloudKitSyncState
    private(set) var lastSyncDate: Date?
    var showingStatusAlert = false
    var statusAlertMessage: String?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.sitecycle.app",
        category: "CloudKitSync"
    )
    private let isCloudKitEnabled: Bool
    private var networkMonitor: NWPathMonitor?
    private var cloudKitEventTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?
    private var accountObserver: NSObjectProtocol?

    init(isCloudKitEnabled: Bool) {
        self.isCloudKitEnabled = isCloudKitEnabled
        if isCloudKitEnabled {
            state = .waiting
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
            state = .waiting
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
        let typeName = Self.eventTypeName(event.type)
        let store = event.storeIdentifier
        if event.endDate == nil {
            Self.logger.info("CloudKit sync started: type=\(typeName, privacy: .public), store=\(store, privacy: .public)")
            state = .syncing
        } else if event.succeeded {
            Self.logger.info("CloudKit sync succeeded: type=\(typeName, privacy: .public), store=\(store, privacy: .public)")
            state = .synced
            lastSyncDate = event.endDate
        } else {
            let message = event.error?.localizedDescription ?? "Unknown error"
            Self.logger.error(
                "CloudKit sync failed: type=\(typeName, privacy: .public), store=\(store, privacy: .public), error=\(message, privacy: .public)"
            )
            state = CloudKitSyncState.fromSyncError(event.error)
        }
    }

    private static func eventTypeName(
        _ type: NSPersistentCloudKitContainer.EventType
    ) -> String {
        switch type {
        case .setup: return "setup"
        case .import: return "import"
        case .export: return "export"
        @unknown default: return "unknown(\(type.rawValue))"
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
                state = .waiting
            }
        } catch {
            // Ignore account status errors silently
        }
    }
}
