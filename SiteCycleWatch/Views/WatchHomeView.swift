import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchConnectivityManager.self) private var connectivityManager
    @State private var viewModel: WatchHomeViewModel?
    @State private var showingSiteSelection = false

    var body: some View {
        NavigationStack {
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
            .overlay {
                if connectivityManager.hasPendingCommand {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Sending...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 4)
                }
            }
            .onAppear { setupViewModel() }
            .navigationDestination(isPresented: $showingSiteSelection) {
                WatchSiteSelectionView(onComplete: {
                    showingSiteSelection = false
                })
            }
        }
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

                    changeSiteButton
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
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)

            Circle()
                .trim(from: 0, to: min(CGFloat(fraction), 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(formatElapsed(elapsed))
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                Text("hours")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 110, height: 110)
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

    private var changeSiteButton: some View {
        Button {
            showingSiteSelection = true
        } label: {
            Label("Change Site", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
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

            Button {
                showingSiteSelection = true
            } label: {
                Label("Log Site Change", systemImage: "plus.circle.fill")
                    .font(.footnote)
            }
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
