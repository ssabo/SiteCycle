import SwiftUI
import SwiftData

private struct ZoneGroup: Identifiable {
    let zone: String
    let isCustom: Bool
    let locations: [Location]
    var id: String { zone }
}

struct LocationConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Location.sortOrder) private var allLocations: [Location]
    @State private var showingAddSheet = false

    private var zoneGroups: [ZoneGroup] {
        var groups: [ZoneGroup] = []
        var seen = Set<String>()
        for location in allLocations {
            guard !seen.contains(location.zone) else { continue }
            seen.insert(location.zone)
            let locs = allLocations.filter { $0.zone == location.zone }
            groups.append(ZoneGroup(zone: location.zone, isCustom: location.isCustom, locations: locs))
        }
        return groups
    }

    var body: some View {
        List {
            ForEach(zoneGroups) { group in
                ZoneRow(
                    zone: group.zone,
                    isCustom: group.isCustom,
                    locations: group.locations
                )
            }
            .onDelete(perform: deleteZones)
            .onMove(perform: moveZones)

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Custom Zone", systemImage: "plus.circle")
            }
        }
        .navigationTitle("Manage Locations")
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCustomZoneSheet { zoneName, hasLaterality in
                addCustomZone(name: zoneName, hasLaterality: hasLaterality)
            }
        }
    }

    private func addCustomZone(name: String, hasLaterality: Bool) {
        let maxSortOrder = allLocations.map(\.sortOrder).max() ?? -1

        if hasLaterality {
            let left = Location(
                zone: name,
                side: "left",
                isEnabled: true,
                isCustom: true,
                sortOrder: maxSortOrder + 1
            )
            let right = Location(
                zone: name,
                side: "right",
                isEnabled: true,
                isCustom: true,
                sortOrder: maxSortOrder + 2
            )
            modelContext.insert(left)
            modelContext.insert(right)
        } else {
            let location = Location(
                zone: name,
                side: nil,
                isEnabled: true,
                isCustom: true,
                sortOrder: maxSortOrder + 1
            )
            modelContext.insert(location)
        }
        try? modelContext.save()
    }

    private func deleteZones(at offsets: IndexSet) {
        let groups = zoneGroups
        for index in offsets {
            let group = groups[index]
            guard group.isCustom else { continue }

            let hasHistory = group.locations.contains { !$0.entries.isEmpty }
            for location in group.locations {
                if hasHistory {
                    location.isEnabled = false
                } else {
                    modelContext.delete(location)
                }
            }
        }
        try? modelContext.save()
    }

    private func moveZones(from source: IndexSet, to destination: Int) {
        var groups = zoneGroups
        groups.move(fromOffsets: source, toOffset: destination)

        var sortOrder = 0
        for group in groups {
            for location in group.locations {
                location.sortOrder = sortOrder
                sortOrder += 1
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Zone Row

private struct ZoneRow: View {
    let zone: String
    let isCustom: Bool
    let locations: [Location]

    private var isEnabled: Bool {
        locations.contains { $0.isEnabled }
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isEnabled },
            set: { newValue in
                for location in locations {
                    location.isEnabled = newValue
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zone)
                    .font(.body)
                if locations.count > 1 {
                    Text("Left & Right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isCustom {
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Add Custom Zone Sheet

private struct AddCustomZoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var zoneName = ""
    @State private var hasLaterality = true
    let onSave: (String, Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Zone Name", text: $zoneName)
                    Toggle("Has Left & Right Sides", isOn: $hasLaterality)
                } footer: {
                    if hasLaterality {
                        Text("Two locations will be created: Left and Right.")
                    } else {
                        Text("One location will be created.")
                    }
                }
            }
            .navigationTitle("Add Custom Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(zoneName.trimmingCharacters(in: .whitespaces), hasLaterality)
                        dismiss()
                    }
                    .disabled(zoneName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LocationConfigView()
    }
    .modelContainer(for: [Location.self, SiteChangeEntry.self], inMemory: true)
}
