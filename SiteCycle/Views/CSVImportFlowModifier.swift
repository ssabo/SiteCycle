import SwiftData
import SwiftUI

/// Presents the CSV import flow that `CSVImportViewModel` drives: the file
/// picker, the confirmation that says what the file holds, and the outcome.
struct CSVImportFlowModifier: ViewModifier {
    @Bindable var flow: CSVImportViewModel
    /// Called after the data has been replaced.
    let onImported: () -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if flow.showingPicker {
                        DocumentPickerView(
                            onPickURL: { url in flow.prepare(fileAt: url, context: modelContext) },
                            isPresented: $flow.showingPicker
                        )
                    }
                }
            )
            .alert(
                flow.pendingConfirmation?.title ?? "",
                isPresented: Binding(
                    get: { flow.pendingConfirmation != nil },
                    set: { if !$0 { flow.cancel() } }
                ),
                presenting: flow.pendingConfirmation,
                actions: { confirmation in
                    Button(confirmation.confirmButtonTitle, role: .destructive) {
                        if flow.confirm(confirmation, context: modelContext) {
                            onImported()
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                },
                message: { confirmation in
                    Text(confirmation.message)
                }
            )
            .alert(
                flow.alert?.title ?? "",
                isPresented: Binding(
                    get: { flow.alert != nil },
                    set: { if !$0 { flow.alert = nil } }
                ),
                presenting: flow.alert,
                actions: { _ in
                    Button("OK", role: .cancel) { }
                },
                message: { alert in
                    Text(alert.message)
                }
            )
    }
}

extension View {
    func csvImportFlow(_ flow: CSVImportViewModel, onImported: @escaping () -> Void) -> some View {
        modifier(CSVImportFlowModifier(flow: flow, onImported: onImported))
    }
}
