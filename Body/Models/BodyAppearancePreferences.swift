//
//  BodyAppearancePreferences.swift
//  Body
//

import SwiftUI

enum BodyAppearancePreference {
    static let selectedThemeKey = "selectedTheme"
    static let selectedAccentKey = "selectedAppAccent"
    static let selectedUnitPreferenceKey = "selectedUnitPreference"
}

enum BodyHealthTrendRange: String, CaseIterable, Identifiable {
    case recentWeek
    case recentMonth

    static let defaultValue: BodyHealthTrendRange = .recentWeek

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .recentWeek:
            return "Recent Week"
        case .recentMonth:
            return "Recent Month"
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .recentWeek:
            return "7 days"
        case .recentMonth:
            return "30 days"
        }
    }

    var chartTitle: String {
        switch self {
        case .recentWeek:
            return "Last 7 Days"
        case .recentMonth:
            return "Last 30 Days"
        }
    }

    var dayCount: Int {
        switch self {
        case .recentWeek:
            return 7
        case .recentMonth:
            return 30
        }
    }

    var axisStrideDayCount: Int {
        switch self {
        case .recentWeek:
            return 1
        case .recentMonth:
            return 7
        }
    }

    func axisLabel(for date: Date) -> String {
        switch self {
        case .recentWeek:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .recentMonth:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func storedValue(from rawValue: String) -> BodyHealthTrendRange {
        BodyHealthTrendRange(rawValue: rawValue) ?? defaultValue
    }
}

enum BodyAppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultValue: BodyAppTheme = .system

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .system:
            return "Auto"
        case .light:
            return "Bright"
        case .dark:
            return "Dim"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .system:
            return .teal
        case .light:
            return .orange
        case .dark:
            return .indigo
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func storedValue(from rawValue: String) -> BodyAppTheme {
        BodyAppTheme(rawValue: rawValue) ?? defaultValue
    }
}

enum BodyAppAccent: String, CaseIterable, Identifiable {
    case blue
    case purple
    case pink
    case green
    case orange
    case teal
    case indigo
    case red
    case gray

    static let defaultValue: BodyAppAccent = .blue

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .blue:
            return "Blue"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        case .green:
            return "Green"
        case .orange:
            return "Orange"
        case .teal:
            return "Teal"
        case .indigo:
            return "Indigo"
        case .red:
            return "Red"
        case .gray:
            return "Gray"
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .blue:
            return "Classic"
        case .purple:
            return "Vivid"
        case .pink:
            return "Rose"
        case .green:
            return "Fresh"
        case .orange:
            return "Warm"
        case .teal:
            return "Calm"
        case .indigo:
            return "Deep"
        case .red:
            return "Bold"
        case .gray:
            return "Neutral"
        }
    }

    var iconName: String {
        switch self {
        case .blue:
            return "drop.fill"
        case .purple:
            return "sparkles"
        case .pink:
            return "heart.fill"
        case .green:
            return "leaf.fill"
        case .orange:
            return "sun.max.fill"
        case .teal:
            return "water.waves"
        case .indigo:
            return "moon.stars.fill"
        case .red:
            return "flame.fill"
        case .gray:
            return "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .purple:
            return .purple
        case .pink:
            return .pink
        case .green:
            return .green
        case .orange:
            return .orange
        case .teal:
            return .teal
        case .indigo:
            return .indigo
        case .red:
            return .red
        case .gray:
            return .gray
        }
    }

    static func storedValue(from rawValue: String) -> BodyAppAccent {
        BodyAppAccent(rawValue: rawValue) ?? defaultValue
    }
}
