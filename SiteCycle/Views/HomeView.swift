import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("targetDurationHours") private var targetDurationHours: Int = 72
    @State private var viewModel: HomeViewModel?
    @State private var siteChangeViewModel: SiteChangeViewModel?
    @State private var showingSiteSheet = false
    @State private var now = Date()
    @State private var quickLogLocation: Location?
    @State private var quickLogNote = ""
    @State private var showingQuickLogConfirmation = false
    @State private var isQuickLogging = false

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
            siteChangeViewModel?.refresh()
        }, content: {
            SiteSelectionSheet()
        })
        .alert("Confirm Site Change", isPresented: $showingQuickLogConfirmation, actions: {
            TextField("Add a note (optional)", text: $quickLogNote)
            Button("Confirm") {
                guard !isQuickLogging, let location = quickLogLocation else { return }
                isQuickLogging = true
                siteChangeViewModel?.logSiteChange(location: location, note: quickLogNote)
                viewModel?.refreshActiveSite()
                siteChangeViewModel?.refresh()
                isQuickLogging = false
                quickLogLocation = nil
                quickLogNote = ""
            }
            Button("Cancel", role: .cancel) {
                quickLogLocation = nil
                quickLogNote = ""
            }
        }, message: {
            Text("Log site change to \(quickLogLocation?.fullDisplayName ?? "")?")
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
        if siteChangeViewModel == nil {
            siteChangeViewModel = SiteChangeViewModel(modelContext: modelContext)
        } else {
            siteChangeViewModel?.refresh()
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

                if let scvm = siteChangeViewModel, !scvm.recommendations.recommended.isEmpty {
                    recommendedShortcuts(scvm: scvm)
                }

                allLocationsButton
                    .padding(.bottom, 24)
            }
        }
    }

    private func recommendedShortcuts(scvm: SiteChangeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recommended Next", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(scvm.recommendations.recommended) { location in
                    quickLogButton(for: location)
                }
            }
            .padding(.horizontal)
        }
    }

    private func quickLogButton(for location: Location) -> some View {
        Button {
            quickLogLocation = location
            quickLogNote = ""
            showingQuickLogConfirmation = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    LocationLabelView(location: location)
                        .fontWeight(.medium)
                    Text(daysAgoText(for: location))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .tint(.primary)
    }

    private func daysAgoText(for location: Location) -> String {
        guard let lastUsed = location.entries.map(\.startTime).max() else { return "Never used" }
        let days = Calendar.current.dateComponents([.day], from: lastUsed, to: .now).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }

    // MARK: - Progress Ring

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
            if let loc = viewModel.currentLocation {
                LocationLabelView(location: loc, font: .title2)
                    .fontWeight(.semibold)
            } else {
                Text("Unknown Location")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

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
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "cross.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)

                Text("No Active Site")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Log your first site change to start tracking your rotation.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let scvm = siteChangeViewModel, !scvm.recommendations.recommended.isEmpty {
                    recommendedShortcuts(scvm: scvm)
                        .padding(.top, 8)
                }

                allLocationsButton
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Shared Components

    private var allLocationsButton: some View {
        Button {
            showingSiteSheet = true
        } label: {
            Label("All Locations", systemImage: "list.bullet")
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(.secondary)
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
