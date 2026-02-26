import SwiftUI
import SwiftData

struct WatchHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72
    @State private var viewModel: HomeViewModel?
    @State private var showingSiteSelection = false

    // MARK: - Effective state (prefers WC data until CloudKit syncs)

    private var effectiveHasActiveSite: Bool {
        viewModel?.hasActiveSite == true ||
        WatchConnectivityManager.shared.lastLoggedStartTime != nil
    }

    private var effectiveStartTime: Date? {
        let wcTime = WatchConnectivityManager.shared.lastLoggedStartTime
        let vmTime = viewModel?.startTime
        if let wcTime, wcTime > (vmTime ?? .distantPast) { return wcTime }
        return vmTime
    }

    private var effectiveLocationName: String? {
        let wcTime = WatchConnectivityManager.shared.lastLoggedStartTime
        let vmTime = viewModel?.startTime
        guard let wcTime, wcTime > (vmTime ?? .distantPast) else {
            return viewModel?.currentLocation?.fullDisplayName
        }
        return WatchConnectivityManager.shared.lastLoggedLocationName
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if effectiveHasActiveSite {
                        activeSiteContent(viewModel: viewModel)
                    } else {
                        emptyStateContent
                    }
                } else {
                    ProgressView()
                }
            }
            .onAppear { setupViewModel() }
            .navigationDestination(isPresented: $showingSiteSelection) {
                WatchSiteSelectionView(onComplete: {
                    showingSiteSelection = false
                    viewModel?.refreshActiveSite()
                })
            }
        }
    }

    private func setupViewModel() {
        if viewModel == nil {
            viewModel = HomeViewModel(
                modelContext: modelContext,
                targetDurationHours: Double(targetDurationHours)
            )
        } else {
            viewModel?.refreshActiveSite()
        }
    }

    private func activeSiteContent(viewModel: HomeViewModel) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let start = effectiveStartTime ?? now
            let elapsed = now.timeIntervalSince(start) / 3600.0
            let fraction = elapsed / viewModel.targetDurationHours

            ScrollView {
                VStack(spacing: 12) {
                    progressRing(
                        elapsed: elapsed,
                        fraction: fraction,
                        color: progressColor(for: fraction)
                    )

                    locationLabel(name: effectiveLocationName, startTime: effectiveStartTime)

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

    private func locationLabel(name: String?, startTime: Date?) -> some View {
        VStack(spacing: 2) {
            if let name {
                Text(name)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            if let startTime {
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
