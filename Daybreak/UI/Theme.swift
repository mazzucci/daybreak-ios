import SwiftUI
import UIKit

/// Android's "Open sky" palette as dynamic colours (light and dark), so the two apps look like one: cool blue-greys
/// for surfaces, one sky blue as the primary, warm amber for the sun. Text and background pairs were checked for
/// WCAG AA on Android.
enum Palette {
    static let primary = Color(light: 0x1565C0, dark: 0x8AB4F8)
    static let primaryContainer = Color(light: 0xD6E6FB, dark: 0x1F3B63)
    static let onPrimaryContainer = Color(light: 0x0B2E5C, dark: 0xD6E6FB)
    static let background = Color(light: 0xF2F5F9, dark: 0x0F1522)
    static let onSurface = Color(light: 0x16202B, dark: 0xE4ECF5)
    static let onSurfaceVariant = Color(light: 0x5A6878, dark: 0xAAB6C6)
    /// Cards.
    static let surfaceContainer = Color(light: 0xFFFFFF, dark: 0x1A2233)
    /// The range bar's track.
    static let surfaceContainerHigh = Color(light: 0xEAF0F7, dark: 0x212B3F)
    static let surfaceContainerHighest = Color(light: 0xE1E8F1, dark: 0x29344A)
    /// The "Saved" pill in search results.
    static let secondaryContainer = Color(light: 0xE1E9F2, dark: 0x2A3648)
    static let onSecondaryContainer = Color(light: 0x1C2937, dark: 0xE1E9F2)
    static let outline = Color(light: 0x7F8EA3, dark: 0x7F8EA3)
    static let outlineVariant = Color(light: 0xD9E2EC, dark: 0x344056)
    static let error = Color(light: 0xB3261E, dark: 0xFFB4AB)

    /// Sun disc in icons, and the warm end of the range bar.
    static let sun = Color(light: 0xF59E0B, dark: 0xFFB74D)
    /// Cloud body in icons drawn on cards (on the hero they're white).
    static let cloud = Color(light: 0x7F8EA3, dark: 0xAAB6C6)
    /// Rain and snow marks, rain chances from 40%, and the cool end of the range bar.
    static let rain = Color(light: 0x1E6FC0, dark: 0x8AB4F8)
    /// A rain bar at the chart's cap (4 mm an hour): the rain blue, 35% towards black, or 45% towards white in dark.
    static let rainHeavy = Color(light: 0x14487D, dark: 0xBFD6FB)
    static let success = Color(light: 0x2E7D32, dark: 0x5BC38A)
    /// "This week"'s bars: a great day, a good one, and the rest (meh or stay in).
    static let outlookGreat = Color(light: 0x2E7D32, dark: 0x5BC38A)
    static let outlookGood = Color(light: 0x4F9A55, dark: 0x45996E)
    static let outlookRest = Color(light: 0x7F8EA3, dark: 0x7F8EA3)
    /// Text that asks for attention without being an error (a stale forecast).
    static let attention = Color(light: 0xB45309, dark: 0xFFB74D)
    /// Skeleton blocks while loading, and the picture slot before it fades in.
    static let skeleton = Color(light: 0xDCE4EE, dark: 0x29344A)

    /// The deep blue of the app icon and the neutral sky.
    static let brandBlue = Color(hex: 0x0D47A1)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Spacing and shapes shared by every screen, as on Android.
enum Metrics {
    /// The side margin of every section.
    static let pageMargin: CGFloat = 20
    /// Cards' corners (Material's medium shape).
    static let cardCorner: CGFloat = 16
    /// The sky's bottom corners.
    static let heroCorner: CGFloat = 28
    /// The widest the content gets on an iPad, so lines and cards stay a comfortable size.
    static let readableWidth: CGFloat = 680
}

/// Android's type scale on the system font, through Dynamic Type text styles so everything grows with the
/// phone's text size.
extension Font {
    /// headlineLarge (30 semibold): the place and the greeting.
    static let headline1 = Font.system(.title, weight: .semibold)
    /// titleLarge (20 semibold).
    static let titleLarge = Font.system(.title3, weight: .semibold)
    /// titleMedium (16 semibold): section headings, card titles, pill values.
    static let titleMedium = Font.system(.headline)
    /// titleSmall (14 semibold): highs in the 10-day list.
    static let titleSmall = Font.system(.subheadline, weight: .semibold)
    /// bodyLarge (17).
    static let bodyLarge = Font.system(.body)
    /// bodyMedium (15).
    static let bodyMedium = Font.system(.subheadline)
    /// bodySmall (13).
    static let bodySmall = Font.system(.footnote)
    /// labelLarge (14 semibold).
    static let labelLarge = Font.system(.subheadline, weight: .semibold)
    /// labelMedium (13 medium): tile labels, the "updated" line.
    static let labelMedium = Font.system(.footnote, weight: .medium)
    /// labelSmall (11 medium): the other unit, rain chances, detail lines.
    static let labelSmall = Font.system(.caption2, weight: .medium)
}

/// The white card every section sits on.
struct CardBackground: ViewModifier {
    var color: Color = Palette.surfaceContainer
    func body(content: Content) -> some View {
        content.background(color, in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
    }
}

extension View {
    func card(_ color: Color = Palette.surfaceContainer) -> some View { modifier(CardBackground(color: color)) }

    /// Centres the content and keeps it to a readable width on an iPad.
    func readableWidth() -> some View {
        frame(maxWidth: Metrics.readableWidth).frame(maxWidth: .infinity)
    }
}
