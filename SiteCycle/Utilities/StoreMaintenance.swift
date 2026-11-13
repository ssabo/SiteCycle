import Foundation
import SwiftData

/// Seeds, migrates and deduplicates the store. `SiteCycleApp` runs this once
/// per launch, before anything reads the data.
///
/// The order matters:
/// - Migration runs before location dedup, which identifies a location by its
///   `bodyPart`. Legacy rows have one only after migration.
/// - Location dedup runs before entry dedup, which matches entries by
///   location. Two copies of an entry match only once both point at the
///   location keeper.
@MainActor
func prepareStore(context: ModelContext) {
    seedDefaultLocations(context: context)
    migrateLocationBodyParts(context: context)
    deduplicateLocations(context: context)
    deduplicateSiteChangeEntries(context: context)
    seedDefaultProblems(context: context)
    deduplicateProblems(context: context)
}
