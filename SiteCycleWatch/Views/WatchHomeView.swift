import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchConnectivityManager.self) private var connectivityManager
    @State private var viewModel: WatchHomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if !viewModel.hasReceivedState {
                    syncingStateContent
                } else if viewModel.hasActiveSite {
                    activeSiteContent(viewModel: viewModel)
                } else {
                    emptyStateContent
                }
            } else {
                ProgressView()
            }
        }
        .onAppear { setupViewModel() }
    }

    private func setupViewModel() {
        if viewModel == nil {
            viewModel = WatchHomeViewModel(
                connectivityManager: connectivityManager
            )
        }
    }

    private func activeSiteContent(viewModel: WatchHomeViewModel) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let elapsed = viewModel.elapsedHours(at: now)
            let fraction = viewModel.progressFraction(at: now)

            ScrollView {
                VStack(spacing: 12) {
                    progressRing(
                        elapsed: elapsed,
                        fraction: fraction,
                        color: progressColor(for: fraction)
                    )

                    locationLabel(viewModel: viewModel)
                }
            }
        }
    }

    private func progressRing(
        elapsed: Double,
        fraction: Double,
        color: Color
    ) -> some View {
        ZStack {
            // Strokes paint centered on the path, so inset each circle by half
            // the line width to keep the ring inside the frame — otherwise the
            // overhang is clipped when the location label below is narrower
            // than the painted ring.
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                .padding(4)

            Circle()
                .trim(from: 0, to: min(CGFloat(fraction), 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)

            VStack(spacing: 2) {
                Text(formatElapsed(elapsed))
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                Text("hours")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 118, height: 118)
    }

    private func locationLabel(viewModel: WatchHomeViewModel) -> some View {
        VStack(spacing: 2) {
            if let name = viewModel.currentLocationName {
                Text(name)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            if let startTime = viewModel.startTime {
                Text(startTime, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncingStateContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Syncing with iPhone...")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "cross.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Active Site")
                .font(.headline)
        }
    }

    private func formatElapsed(_ hours: Double) -> String {
        String(format: "%.1f", hours)
    }

    private func progressColor(for fraction: Double) -> Color {
        if fraction < 0.8 { return .green }
        if fraction <= 1.0 { return .yellow }
        return .red
    }
}
