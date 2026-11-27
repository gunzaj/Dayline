import AppKit
import SwiftUI

// MARK: - Hex helper

extension Color {
    /// Creates a color from a 6-digit hex value, e.g. Color(hex: 0xF27D16).
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Dayline color tokens

extension Color {
    // Surfaces
    static let bgCanvas            = Color(hex: 0xFAF9F6)
    static let bgSidebar           = Color(hex: 0xF4F2EC)
    static let bgTitlebar          = Color(hex: 0xF7F5F0)
    static let bgCard              = Color(hex: 0xFFFFFF)
    static let bgInput             = Color(hex: 0xFAF9F6)
    static let borderHairline      = Color(hex: 0xE8E5DE)
    static let borderStrong        = Color(hex: 0xD8D3C8)

    // Text
    static let textPrimary         = Color(hex: 0x14213D)
    static let textSecondary       = Color(hex: 0x5C677D)
    static let textMuted           = Color(hex: 0x8A93A5)
    static let textOnAccent        = Color(hex: 0xFFFFFF)
    static let textCallout         = Color(hex: 0x4A5568)

    // Primary action: Sun Orange
    static let accentPrimary       = Color(hex: 0xF27D16)
    static let accentPrimaryHover  = Color(hex: 0xD96B0B)
    static let accentPrimaryTint   = Color(hex: 0xFFF3E6)
    static let accentPrimaryBorder = Color(hex: 0xFAD7B3)

    // Positive / active / calm: Sage Emerald
    static let semanticCalm        = Color(hex: 0x2E8B6E)
    static let semanticCalmHover   = Color(hex: 0x247158)
    static let semanticCalmTint    = Color(hex: 0xEAF6F1)
    static let semanticCalmText    = Color(hex: 0x1F6B53)
    static let semanticCalmBorder  = Color(hex: 0xC5E5D9)

    // Caution / snooze / info: Warm Amber
    static let semanticWarm        = Color(hex: 0xE09F3E)
    static let semanticWarmText    = Color(hex: 0xB87314)
    static let semanticWarmTint    = Color(hex: 0xFDF6E7)
    static let semanticWarmBorder  = Color(hex: 0xECDAB4)

    // Destructive / skip / high stress: Muted Terracotta
    static let semanticAlert       = Color(hex: 0xC85A4A)
    static let semanticAlertHover  = Color(hex: 0xB04A3B)
    static let semanticAlertTint   = Color(hex: 0xFBECE9)
    static let semanticAlertBorder = Color(hex: 0xEFC6BF)

    // Neutral / drained: Slate Blue
    static let semanticCool        = Color(hex: 0x5B7FA6)
    static let semanticCoolTint    = Color(hex: 0xEEF3F8)

    // Charts
    static let chartMeetingBand    = Color(hex: 0xEFECE5)
    static let chartStress         = Color.semanticAlert
    static let chartBodyBattery    = Color.semanticCalm
    static let chartBreakMarker    = Color.accentPrimary
}

// MARK: - AppKit bridge

extension NSColor {
    static let daylineCanvas   = NSColor(Color.bgCanvas)
    static let daylineSidebar  = NSColor(Color.bgSidebar)
    static let daylineCard     = NSColor(Color.bgCard)
    static let daylineHairline = NSColor(Color.borderHairline)
    static let daylineAccent   = NSColor(Color.accentPrimary)
    static let daylineCalm     = NSColor(Color.semanticCalm)
    static let daylineWarm     = NSColor(Color.semanticWarm)
    static let daylineAlert    = NSColor(Color.semanticAlert)
    static let daylineInk      = NSColor(Color.textPrimary)
}

// MARK: - Mood & Energy grid

enum MoodGrid {
    /// Rows top to bottom = energy 4 (high) to 1 (low).
    /// Columns left to right = mood 1 (unpleasant) to 4 (pleasant).
    static let colors: [[Color]] = [
        [Color(hex: 0xC85A4A), Color(hex: 0xDC8275), Color(hex: 0xF6A254), Color(hex: 0xF27D16)], // energy 4
        [Color(hex: 0xDC8275), Color(hex: 0xF2C9C3), Color(hex: 0xFCE0C2), Color(hex: 0xF6A254)], // energy 3
        [Color(hex: 0x83A2C2), Color(hex: 0xD2DFEC), Color(hex: 0xC7E5DA), Color(hex: 0x5EA890)], // energy 2
        [Color(hex: 0x5B7FA6), Color(hex: 0x83A2C2), Color(hex: 0x5EA890), Color(hex: 0x2E8B6E)], // energy 1
    ]

    /// energy and mood are both 1...4.
    static func color(energy: Int, mood: Int) -> Color {
        colors[4 - energy][mood - 1]
    }

    static let tileSize: CGFloat = 44
    static let tileGap: CGFloat = 6
    static let quadrantGap: CGFloat = 18
    static let tileRadius: CGFloat = 8
}

// MARK: - Layout constants

enum Radius {
    static let card: CGFloat = 12
    static let overlayCard: CGFloat = 16
    static let control: CGFloat = 8
    static let checkbox: CGFloat = 4
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Reusable styles

struct DaylineCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 1)
            )
            .shadow(color: Color.textPrimary.opacity(0.04), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func daylineCard() -> some View { modifier(DaylineCard()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.textOnAccent)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(configuration.isPressed ? Color.accentPrimaryHover : Color.accentPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(configuration.isPressed ? Color.bgCanvas : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Color.borderStrong, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct GhostDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Color.semanticAlertHover : Color.semanticAlert)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(configuration.isPressed ? Color.semanticAlertTint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct CategoryPill: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.semanticCalmText)
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
            .background(Capsule().fill(Color.semanticCalmTint))
            .overlay(Capsule().strokeBorder(Color.semanticCalmBorder, lineWidth: 1))
    }
}

// MARK: - App-wide setup

extension View {
    /// Apply once at the root of every window, popover and overlay.
    func daylineTheme() -> some View {
        self
            .preferredColorScheme(.light)
            .tint(Color.semanticCalm)
            .foregroundStyle(Color.textPrimary)
            .background(Color.bgCanvas)
    }
}
