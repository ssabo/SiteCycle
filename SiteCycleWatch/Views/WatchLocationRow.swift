import SwiftUI

struct WatchLocationRow: View {
    let location: LocationInfo
    let category: LocationCategory
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            if let sideLabel = location.sideLabel {
                let sideColor: Color = location.side == "left" ? .blue : .red
                Text(sideLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(sideColor)
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(sideColor, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(location.displayName)
                    .font(.caption)
                    .lineLimit(1)
                Text(daysAgoText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            categoryBadge
        }
    }

    private var daysAgoText: String {
        guard let date = location.lastUsedDate else { return "Never used" }
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "1 day ago" }
        return "\(days) days ago"
    }

    @ViewBuilder
    private var categoryBadge: some View {
        switch category {
        case .recommended:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        case .avoid:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption2)
        case .neutral:
            EmptyView()
        }
    }
}
