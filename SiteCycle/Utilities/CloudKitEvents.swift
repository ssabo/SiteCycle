import CoreData
import Foundation

/// The fields of an `NSPersistentCloudKitContainer.Event` that the app reads,
/// copied out so they can cross to the main actor.
struct CloudKitEventInfo: Sendable {
    /// The same for an event's start and finish notifications.
    let identifier: UUID
    let type: NSPersistentCloudKitContainer.EventType
    let storeIdentifier: String
    /// Nil while the event is in progress.
    let endDate: Date?
    let succeeded: Bool
    let error: (any Error)?
}

enum CloudKitEvents {
    /// Calls `handler` for each CloudKit sync event, on the queue that posts
    /// it, which is not the main queue. It registers before returning, so it
    /// sees every event posted afterwards. Keep the returned token for as long
    /// as you want events.
    ///
    /// The observer closure is created here, in a nonisolated function, so
    /// that it isn't main-actor isolated (see CLAUDE.md, "Compile gotchas").
    nonisolated static func observe(
        _ handler: @escaping @Sendable (CloudKitEventInfo) -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            handler(CloudKitEventInfo(
                identifier: event.identifier,
                type: event.type,
                storeIdentifier: event.storeIdentifier,
                endDate: event.endDate,
                succeeded: event.succeeded,
                error: event.error
            ))
        }
    }
}
