import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72
    @State private var viewModel: HomeViewModel?
    @State private var showingSiteSheet = false
    @State private var now = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.hasActiveSite {
                    activeSiteContent(viewModel: viewModel)
                } else {
                    emptyStateContent
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("SiteCycle")
        .onAppear { setupViewModel() }
        .onReceive(timer) { now = $0 }
        .onChange(of: targetDurationHours) { _, newValue in
            viewModel?.targetDurationHours = Double(newValue)
        }
        .sheet(isPresented: $showingSiteSheet, onDismiss: {
            viewModel?.refreshActiveSite()
        }, content: {
            SiteSelectionSheet()
        })
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

    // MARK: - Active Site Content

    private func activeSiteContent(viewModel: HomeViewModel) -> some View {
        let elapsed = viewModel.elapsedHours(at: now)
        let fraction = viewModel.progressFraction(at: now)
        let color = progressColor(for: fraction)

        return ScrollView {
            VStack(spacing: 24) {
                progressRing(elapsed: elapsed, fraction: fraction, color: color)
                    .padding(.top, 24)

                locationInfo(viewModel: viewModel)

                Spacer(minLength: 40)

                logSiteChangeButton
                    .padding(.bottom, 24)
            }
        }
    }

    private func progressRing(elapsed: Double, fraction: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 16)

            Circle()
                .trim(from: 0, to: min(CGFloat(fraction), 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: fraction)

            VStack(spacing: 4) {
                Text(String(format: "%.1f", elapsed))
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                Text("hours")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
    }

    private func locationInfo(viewModel: HomeViewModel) -> some View {
        VStack(spacing: 8) {
            Text(viewModel.currentLocation?.displayName ?? "Unknown Location")
                .font(.title2)
                .fontWeight(.semibold)

            if let startTime = viewModel.startTime {
                Text("Since \(startTime, format: .dateTime.month().day().hour().minute())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Target: \(targetDurationHours) hours")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cross.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Active Site")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Log your first site change to start tracking your rotation.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showingSiteSheet = true
            } label: {
                Label("Log Your First Site Change", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Shared Components

    private var logSiteChangeButton: some View {
        Button {
            showingSiteSheet = true
        } label: {
            Label("Log Site Change", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func progressColor(for fraction: Double) -> Color {
        if fraction < 0.8 { return .green }
        if fraction <= 1.0 { return .yellow }
        return .red
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
