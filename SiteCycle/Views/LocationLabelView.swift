import SwiftUI

struct LocationLabelView: View {
    let location: Location
    var font: Font = .body

    var body: some View {
        HStack(spacing: 6) {
            if let sideLabel = location.sideLabel {
                let sideColor: Color = location.side == "left" ? .blue : .red
                Text(sideLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(sideColor)
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(sideColor, lineWidth: 1)
                    )
            }
            Text(location.displayName)
                .font(font)
        }
    }
}
