import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPickURL: (URL) -> Void
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onPickURL: onPickURL, isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard uiViewController.presentedViewController == nil else { return }
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.commaSeparatedText, .plainText]
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        uiViewController.present(picker, animated: true)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPickURL: (URL) -> Void
        @Binding var isPresented: Bool

        init(onPickURL: @escaping (URL) -> Void, isPresented: Binding<Bool>) {
            self.onPickURL = onPickURL
            self._isPresented = isPresented
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            if let url = urls.first {
                onPickURL(url)
            }
            isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented = false
        }
    }
}
