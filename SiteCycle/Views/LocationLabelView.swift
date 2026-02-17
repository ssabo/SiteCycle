import SwiftUI

struct LocationLabelView: View {
    let location: Location
    var font: Font = .body

    var body: some View {
        HStack(spacing: 6) {
            if let sideLabel = location.sideLabel {
                Text(sideLabel)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.primary, lineWidth: 1)
                    )
            }
            Text(location.displayName)
                .font(font)
        }
    }
}
