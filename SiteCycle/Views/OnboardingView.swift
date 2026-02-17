import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage(
                onNext: { currentPage = 1 },
                onImportComplete: completeOnboarding
            )
            .tag(0)

            ConfigureLocationsPage(onNext: { currentPage = 2 })
                .tag(1)

            ReadyPage(onDone: completeOnboarding)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .overlay(alignment: .topTrailing) {
            Button("Skip") {
                completeOnboarding()
            }
            .padding()
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    let onNext: () -> Void
    let onImportComplete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var showingImportPicker = false
    @State private var importResult: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("SiteCycle")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Track your infusion site rotation to prevent tissue damage and optimize insulin absorption.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                onNext()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Button {
                showingImportPicker = true
            } label: {
                Text("Restore from CSV backup")
                    .font(.subheadline)
            }
            .padding(.bottom, 48)
        }
        .background(
            Group {
                if showingImportPicker {
                    DocumentPickerView(
                        onPickURL: { url in handleImport(from: url) },
                        isPresented: $showingImportPicker
                    )
                }
            }
        )
        .alert("Import Failed", isPresented: .init(
            get: { importResult != nil },
            set: { if !$0 { importResult = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = importResult { Text(msg) }
        }
    }

    private func handleImport(from url: URL) {
        do {
            _ = try CSVImporter.importCSV(from: url, context: modelContext)
            onImportComplete()
        } catch {
            importResult = error.localizedDescription
        }
    }
}

// MARK: - Configure Locations Page

private struct ConfigureLocationsPage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Configure Your Locations")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Toggle which body zones you use for infusion sites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            LocationConfigView()
                .toolbar(.hidden, for: .navigationBar)

            Button {
                onNext()
            } label: {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Ready Page

private struct ReadyPage: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Log your first site change to start tracking your rotation pattern.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
