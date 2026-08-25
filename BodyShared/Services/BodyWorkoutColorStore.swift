//
//  BodyWorkoutColorStore.swift
//  Body
//

import SwiftUI

/// Shared App Group access for workout color customization: the raw override string
/// consumed by `BodyWorkoutColorOverrides`/`BodyWorkoutColorPalette` and the raw
/// known-workout-types census consumed by `BodyKnownWorkoutTypesCensus`.
///
/// Mirrors `BodyProEntitlement`'s suite access so the app, the widget extension, and any
/// other App Group process read the same values `BodyApp`'s `@AppStorage` writes.
enum BodyWorkoutColorStore {
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WorkoutSnapshotStore.appGroupIdentifier)
    }

    /// Raw override string at `BodyAppearancePreference.workoutColorOverridesKey`. The app
    /// writes this via `@AppStorage(..., store: BodyWorkoutColorStore.sharedDefaults)`; this
    /// accessor exists for non-SwiftUI readers/writers (the widget timeline provider, tests).
    static var rawOverrides: String {
        get { sharedDefaults?.string(forKey: BodyAppearancePreference.workoutColorOverridesKey) ?? "" }
        set { sharedDefaults?.set(newValue, forKey: BodyAppearancePreference.workoutColorOverridesKey) }
    }

    /// Resolves the palette from the persisted raw override string for callers that can't
    /// reach the SwiftUI environment (the widget timeline provider).
    static func palette(isProUnlocked: Bool) -> BodyWorkoutColorPalette {
        BodyWorkoutColorPalette(rawOverrides: rawOverrides, isProUnlocked: isProUnlocked)
    }

    /// Raw known-workout-types census string at `BodyAppearancePreference.knownWorkoutTypesKey`.
    static var knownWorkoutTypesRawValue: String {
        get { sharedDefaults?.string(forKey: BodyAppearancePreference.knownWorkoutTypesKey) ?? "" }
        set { sharedDefaults?.set(newValue, forKey: BodyAppearancePreference.knownWorkoutTypesKey) }
    }

    /// The decoded census: every workout type the user has ever logged, so the color editor
    /// can show activities that matter even after they scroll out of the loaded history.
    static var knownWorkoutTypes: Set<BodyWorkoutType> {
        BodyKnownWorkoutTypesCensus.types(from: knownWorkoutTypesRawValue)
    }

    /// Unions `types` into the persisted census, skipping the write when nothing is new.
    /// Returns whether the census actually changed.
    @discardableResult
    static func mergeKnownWorkoutTypes(_ types: Set<BodyWorkoutType>) -> Bool {
        guard !types.isEmpty else { return false }

        let current = knownWorkoutTypesRawValue
        let merged = BodyKnownWorkoutTypesCensus.merging(rawValue: current, with: types)
        guard merged != current else { return false }

        knownWorkoutTypesRawValue = merged
        return true
    }
}

private struct WorkoutColorPaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue = BodyWorkoutColorPalette.builtIn
}

extension EnvironmentValues {
    /// The resolved workout-color palette (built-in defaults plus any Pro customization).
    /// Populated at the app root (`BodyApp`) from the persisted override string and the Pro
    /// entitlement. `ImageRenderer` roots used for share exports do not inherit the app's
    /// environment, so they must inject this explicitly to match on-screen previews.
    var workoutColorPalette: BodyWorkoutColorPalette {
        get { self[WorkoutColorPaletteEnvironmentKey.self] }
        set { self[WorkoutColorPaletteEnvironmentKey.self] = newValue }
    }
}
