import SwiftUI

/// One of 8 curated base/accent color pairs for the panel's overall look
/// (Preferences -> Appearance), distinct from TodoColorTag's 16 per-item
/// tag colors -- these are deliberately paired, not freely mixed, so every
/// combination stays legible against white panel text. Pure/dependency-free
/// like WidgetSnapshot, so it's shared by both the main app and widget
/// targets: the widget mirrors whatever theme is currently selected.
enum PanelTheme: String, CaseIterable, Codable {
    case blue, purple, green, crimson, amber, teal, rose, graphite

    var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .green: return "Green"
        case .crimson: return "Crimson"
        case .amber: return "Amber"
        case .teal: return "Teal"
        case .rose: return "Rose"
        case .graphite: return "Graphite"
        }
    }

    /// The panel's overall glass-card fill.
    var base: Color {
        switch self {
        case .blue:     return Color(red: 0x2A / 255, green: 0x3D / 255, blue: 0x63 / 255)
        case .purple:   return Color(red: 0x3D / 255, green: 0x2E / 255, blue: 0x5C / 255)
        case .green:    return Color(red: 0x1F / 255, green: 0x3D / 255, blue: 0x33 / 255)
        case .crimson:  return Color(red: 0x4A / 255, green: 0x23 / 255, blue: 0x28 / 255)
        case .amber:    return Color(red: 0x4A / 255, green: 0x34 / 255, blue: 0x20 / 255)
        case .teal:     return Color(red: 0x1E / 255, green: 0x3A / 255, blue: 0x3A / 255)
        case .rose:     return Color(red: 0x3D / 255, green: 0x24 / 255, blue: 0x36 / 255)
        case .graphite: return Color(red: 0x2B / 255, green: 0x2F / 255, blue: 0x38 / 255)
        }
    }

    /// The interactive/highlight color: buttons, checkboxes, the streak
    /// number while celebrating, etc. -- replaces every former use of the
    /// static Color.accentColor asset.
    var accent: Color {
        switch self {
        case .blue:     return Color(red: 0x24 / 255, green: 0x89 / 255, blue: 0xFF / 255)
        case .purple:   return Color(red: 0x9B / 255, green: 0x5D / 255, blue: 0xE5 / 255)
        case .green:    return Color(red: 0x2E / 255, green: 0xCC / 255, blue: 0x71 / 255)
        case .crimson:  return Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
        case .amber:    return Color(red: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255)
        case .teal:     return Color(red: 0x14 / 255, green: 0xB8 / 255, blue: 0xA6 / 255)
        case .rose:     return Color(red: 0xEC / 255, green: 0x48 / 255, blue: 0x99 / 255)
        case .graphite: return Color(red: 0x8B / 255, green: 0x93 / 255, blue: 0xA7 / 255)
        }
    }
}
