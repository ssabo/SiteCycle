import Foundation
import Observation
import SwiftData

/// Drives CSV import from Settings and from onboarding.
///
/// Import replaces all entries and locations, and CloudKit syncs that to every
/// device. So the picked file is read and validated first, without changing
/// anything. The user then sees what it holds and confirms, and only then is
/// the data replaced.
@MainActor
@Observable
final class CSVImportViewModel {
    enum Origin {
        /// Settings → Import Data from CSV: an explicit "replace everything".
        case settings
        /// Onboarding → Restore from CSV backup. Onboarding appears on every new
        /// device and reinstall, often while iCloud is still downloading the
        /// user's history, so this refuses once the device has any entries.
        case onboarding
    }

    /// Shown once a file has been validated. It carries its plan, so confirming
    /// doesn't depend on the order in which SwiftUI clears alert state.
    struct Confirmation {
        let plan: CSVImporter.ImportPlan
        let title: String
        let message: String
        let confirmButtonTitle: String
    }

    struct Alert: Equatable {
        let title: String
        let message: String
    }

    let origin: Origin
    var showingPicker = false
    var pendingConfirmation: Confirmation?
    var alert: Alert?

    init(origin: Origin) {
        self.origin = origin
    }

    /// The import button was tapped. Opens the file picker, unless this is
    /// onboarding and the device already has history.
    func start(context: ModelContext) {
        if let refusal = onboardingRefusal(context: context) {
            alert = refusal
        } else {
            showingPicker = true
        }
    }

    /// Reads and validates the picked file without changing any data, then
    /// asks for confirmation or explains why the file can't be imported.
    func prepare(fileAt url: URL, context: ModelContext) {
        do {
            let plan = try CSVImporter.makePlan(fromFileAt: url)
            pendingConfirmation = makeConfirmation(for: plan, existingEntryCount: Self.entryCount(context: context))
        } catch {
            alert = Self.failureAlert(for: error)
        }
    }

    /// Replaces all data with the confirmed plan. Returns true if it did, so the
    /// caller can push the new state to the watch and widgets.
    @discardableResult
    func confirm(_ confirmation: Confirmation, context: ModelContext) -> Bool {
        pendingConfirmation = nil
        // iCloud may have delivered history while the confirmation was showing.
        if let refusal = onboardingRefusal(context: context) {
            alert = refusal
            return false
        }
        do {
            let result = try CSVImporter.apply(confirmation.plan, context: context)
            // Onboarding closes as soon as the restore succeeds, so it shows nothing.
            if origin == .settings {
                alert = Self.successAlert(for: result)
            }
            return true
        } catch {
            alert = Self.failureAlert(for: error)
            return false
        }
    }

    func cancel() {
        pendingConfirmation = nil
    }

    // MARK: - Text

    private func onboardingRefusal(context: ModelContext) -> Alert? {
        guard origin == .onboarding else { return nil }
        let existing = Self.entryCount(context: context)
        guard existing > 0 else { return nil }
        return Alert(
            title: "History Already on This Device",
            message: "This device already has \(Self.siteChanges(existing)), probably from iCloud, "
                + "so there's nothing to restore. Tap Skip to start using them.\n\n"
                + "To replace them with a backup, use Import Data from CSV in Settings."
        )
    }

    private func makeConfirmation(for plan: CSVImporter.ImportPlan, existingEntryCount: Int) -> Confirmation {
        var parts = ["This file has \(Self.siteChanges(plan.entries.count)) to import."]
        if !plan.skippedRows.isEmpty {
            parts.append(
                "\(Self.rows(plan.skippedRows.count)) can't be read and will be skipped:\n"
                    + CSVImporter.describe(plan.skippedRows)
            )
        }

        switch origin {
        case .settings:
            let existing = existingEntryCount > 0 ? "your \(Self.siteChanges(existingEntryCount))" : "all site history"
            parts.append(
                "Importing permanently deletes \(existing) and all locations, "
                    + "including on your other devices that sync with iCloud. This cannot be undone."
            )
            return Confirmation(
                plan: plan, title: "Replace All Data?", message: parts.joined(separator: "\n\n"),
                confirmButtonTitle: "Replace"
            )
        case .onboarding:
            parts.append("Restoring replaces the default locations with the ones in the backup.")
            parts.append(
                "If you already use SiteCycle with iCloud on another device, tap Cancel and then Skip: "
                    + "your history will download by itself, and restoring would replace it on all your devices."
            )
            return Confirmation(
                plan: plan, title: "Restore from Backup?", message: parts.joined(separator: "\n\n"),
                confirmButtonTitle: "Restore"
            )
        }
    }

    static func successAlert(for result: CSVImporter.ImportResult) -> Alert {
        var message = "Imported \(siteChanges(result.importedCount))."
        if !result.skippedRows.isEmpty {
            message += " Skipped \(rows(result.skippedRows.count))."
        }
        return Alert(title: "Import Successful", message: message)
    }

    static func failureAlert(for error: Error) -> Alert {
        let nsError = error as NSError
        return Alert(
            title: "Import Failed",
            message: "\(error.localizedDescription)\n\nYour existing data has not been changed."
                + "\n\nError: \(nsError.domain) \(nsError.code)"
        )
    }

    private static func entryCount(context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<SiteChangeEntry>())) ?? 0
    }

    private static func siteChanges(_ count: Int) -> String {
        count == 1 ? "1 site change" : "\(count) site changes"
    }

    private static func rows(_ count: Int) -> String {
        count == 1 ? "1 row" : "\(count) rows"
    }
}
