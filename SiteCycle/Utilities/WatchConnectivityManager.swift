import Foundation
import Observation
import WatchConnectivity

// MARK: - WatchConnectivityManager

/// Manages WatchConnectivity between the iOS and watchOS apps.
///
/// **iOS side:** Set `logHandler` before any messages arrive. The handler receives a
/// `locationID`, logs the site change using the iPhone's SwiftData store, and returns
/// the new entry's display name and start time.
///
/// **Watch side:** Call `requestLogSiteChange(locationID:)` to delegate logging to the
/// iPhone. On success the result is stored in `lastLoggedLocationName`/`lastLoggedStartTime`
/// so the Watch UI can update immediately without waiting for CloudKit sync.
/// Falls back to direct local write when the iPhone is not reachable.
@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    // MARK: - Watch UI state (populated after iPhone logs successfully)

    /// Location name of the most recently WC-logged site. Used by Watch UI
    /// to show immediate feedback before CloudKit syncs the entry.
    private(set) var lastLoggedLocationName: String?

    /// Start time of the most recently WC-logged site.
    private(set) var lastLoggedStartTime: Date?

    // MARK: - iOS side

    /// Set on the iOS app to handle incoming log requests from the Watch.
    /// Receives the `locationID`, logs the site change, and returns
    /// `(locationName, startTime)` on success or `nil` if the location is not found.
    var logHandler: ((UUID) async -> (String, Date)?)?

    // MARK: - Init

    private override init() { super.init() }

    // MARK: - Session activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Watch → iPhone

    /// Sends a log-site-change request to the iPhone.
    /// - Returns: `true` if the iPhone received and logged the change; `false` if
    ///   the iPhone is not reachable (caller should fall back to local write).
    func requestLogSiteChange(locationID: UUID) async -> Bool {
        guard WCSession.default.isReachable else { return false }
        let idString = locationID.uuidString
        let result: (name: String, time: Date)? = await withCheckedContinuation { continuation in
            let payload: [String: Any] = ["action": "logSiteChange", "locationID": idString]
            WCSession.default.sendMessage(
                payload,
                replyHandler: { reply in
                    if let name = reply["locationName"] as? String,
                       let ts = reply["startTime"] as? TimeInterval {
                        continuation.resume(returning: (name: name, time: Date(timeIntervalSince1970: ts)))
                    } else {
                        continuation.resume(returning: nil)
                    }
                },
                errorHandler: { _ in
                    continuation.resume(returning: nil)
                }
            )
        }
        if let result {
            lastLoggedLocationName = result.name
            lastLoggedStartTime = result.time
            return true
        }
        return false
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard
            let action = message["action"] as? String, action == "logSiteChange",
            let idString = message["locationID"] as? String,
            let locationID = UUID(uuidString: idString)
        else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            if let (name, time) = await logHandler?(locationID) {
                replyHandler(["locationName": name, "startTime": time.timeIntervalSince1970])
            } else {
                replyHandler([:])
            }
        }
    }
}
