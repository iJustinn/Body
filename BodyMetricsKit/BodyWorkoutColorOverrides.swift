//
//  BodyWorkoutColorOverrides.swift
//  Body
//

import SwiftUI

/// Codec for the persisted per-workout-type color customization.
///
/// The stored form is a flat `"<workoutRawValue>:<RRGGBB>"` list joined by commas
/// (e.g. `"cycling:EE9D58,running:1B305D"`) so it round-trips through `@AppStorage`
/// and the App Group defaults shared with the widget and watch targets.
enum BodyWorkoutColorOverrides {
    /// Defensive cap: a corrupt or adversarially large defaults value is treated as
    /// "no customization" rather than parsed token by token.
    static let maximumRawValueLength = 8_192

    /// Parsed overrides, with unknown workout types, malformed tokens, and entries that
    /// merely restate a type's built-in `colorHex` dropped.
    static func overrides(from rawValue: String) -> [BodyWorkoutType: UInt32] {
        guard rawValue.count <= maximumRawValueLength else { return [:] }

        var parsed: [BodyWorkoutType: UInt32] = [:]
        for token in rawValue.split(separator: ",") {
            let pieces = token.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }

            let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let hexText = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let type = BodyWorkoutType(rawValue: name),
                  let hex = hexValue(from: hexText) else { continue }

            // Last-wins on duplicates; a value equal to the built-in default is not an override.
            if hex == type.colorHex {
                parsed.removeValue(forKey: type)
            } else {
                parsed[type] = hex
            }
        }

        return parsed
    }

    /// Canonical storage form: keys sorted by workout raw value, uppercase 6-digit hex,
    /// no `#`, default-equal entries omitted.
    static func rawValue(from overrides: [BodyWorkoutType: UInt32]) -> String {
        overrides
            .filter { $0.value & 0xFFFFFF != $0.key.colorHex }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\(hexText(from: $0.value))" }
            .joined(separator: ",")
    }

    static func hexText(from hex: UInt32) -> String {
        String(format: "%06X", hex & 0xFFFFFF)
    }

    private static func hexValue(from text: String) -> UInt32? {
        guard text.count == 6,
              text.allSatisfy({ $0.isHexDigit }),
              let value = UInt32(text, radix: 16) else { return nil }
        return value
    }
}

/// Immutable resolved workout colors: built-in defaults plus any Pro customization.
///
/// Custom workout colors are a Body Pro feature; a non-Pro palette resolves to the
/// defaults while the raw string stays untouched in storage, so re-subscribing restores
/// the user's picks.
struct BodyWorkoutColorPalette: Equatable, Sendable {
    let overrides: [BodyWorkoutType: UInt32]

    init(rawOverrides: String, isProUnlocked: Bool) {
        overrides = isProUnlocked ? BodyWorkoutColorOverrides.overrides(from: rawOverrides) : [:]
    }

    /// The app-default palette — no overrides at all.
    static let builtIn = BodyWorkoutColorPalette(rawOverrides: "", isProUnlocked: false)

    var isCustomized: Bool { !overrides.isEmpty }

    func resolvedHex(for type: BodyWorkoutType) -> UInt32 {
        overrides[type] ?? type.colorHex
    }

    /// Matches `BodyWorkoutType.color` exactly for non-overridden types.
    func color(for type: BodyWorkoutType) -> Color {
        BodyWorkoutType.attachedWorkoutColor(hex: resolvedHex(for: type))
    }

    /// Matches `BodyWorkoutType.calendarContentColor` exactly for non-overridden types.
    func contentColor(for type: BodyWorkoutType) -> Color {
        BodyWorkoutType.luminance(hex: resolvedHex(for: type)) > 0.58 ? Color.black.opacity(0.82) : .white
    }
}

/// Codec for the durable list of workout types the user has ever logged, so the color
/// editor can show the activities that actually matter to them even after a month of
/// history scrolls out of the loaded window.
enum BodyKnownWorkoutTypesCensus {
    static func types(from rawValue: String) -> Set<BodyWorkoutType> {
        Set(
            rawValue
                .split(separator: ",")
                .compactMap { BodyWorkoutType(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    /// Canonical storage form: sorted raw values joined by commas.
    static func rawValue(from types: Set<BodyWorkoutType>) -> String {
        types
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    /// Unions `types` into an already-stored census string, returning the canonical form.
    static func merging(rawValue: String, with types: Set<BodyWorkoutType>) -> String {
        Self.rawValue(from: Self.types(from: rawValue).union(types))
    }
}
