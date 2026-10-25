import SwiftUI

/// "Why was this site changed early?" picker, shared by the site change
/// confirmation sheet and the history editor.
struct ProblemPicker: View {
    @Binding var selection: SiteProblem?
    let problems: [SiteProblem]
    /// The entry's problem before editing; offered even if it has been disabled.
    let original: SiteProblem?

    var body: some View {
        Picker("Problem", selection: $selection) {
            Text("None").tag(SiteProblem?.none)
            ForEach(SiteProblem.pickerOptions(from: problems, including: original, selection)) { problem in
                Text(problem.labelText).tag(SiteProblem?.some(problem))
            }
        }
    }
}
