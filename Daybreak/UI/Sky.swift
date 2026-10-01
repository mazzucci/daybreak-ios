import SwiftUI

/// The handful of looks the UI distinguishes, collapsed from WMO weather codes.
enum Sky {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, storm, unknown

    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55, 56, 57: self = .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 99: self = .storm
        default: self = .unknown
        }
    }

    /// Top and bottom colours of the hero gradient, as on Android. Every one keeps white text at 4.5:1 or more. Dark
    /// mode pulls the day skies towards the dark surface so the hero doesn't glow against the rest of the screen.
    func gradient(night: Bool, dark: Bool) -> [Color] {
        let (top, bottom): (UInt32, UInt32)
        if night {
            switch self {
            case .clear: (top, bottom) = (0x0B1B3A, 0x233A6A)
            case .partlyCloudy: (top, bottom) = (0x15223C, 0x2A3B5C)
            case .cloudy, .fog, .unknown: (top, bottom) = (0x1E2A3A, 0x2E3C50)
            case .drizzle, .rain: (top, bottom) = (0x18232F, 0x283848)
            case .snow: (top, bottom) = (0x28344A, 0x3E4C64)
            case .storm: (top, bottom) = (0x12192A, 0x262F45)
            }
        } else {
            switch self {
            case .clear: (top, bottom) = (0x0D47A1, 0x1976D2)
            case .partlyCloudy: (top, bottom) = (0x245C96, 0x3878AE)
            case .cloudy, .fog: (top, bottom) = (0x4A5F70, 0x5E7587)
            case .drizzle, .rain: (top, bottom) = (0x2F4A63, 0x4B6A86)
            case .snow: (top, bottom) = (0x4C6688, 0x587696)
            case .storm: (top, bottom) = (0x22304A, 0x354566)
            case .unknown: (top, bottom) = (0x3A5570, 0x557390)
            }
        }
        let colors = [top, bottom]
        guard dark && !night else { return colors.map { Color(hex: $0) } }
        return colors.map { Color(hex: lerp($0, 0x0B101B, 0.35)) }
    }

    /// The backdrop while there's no forecast yet (loading, errors).
    static func neutral(dark: Bool) -> [Color] { Sky.unknown.gradient(night: false, dark: dark) }
}

private func lerp(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
        let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
        return UInt32((x + (y - x) * t).rounded()) << shift
    }
    return channel(16) | channel(8) | channel(0)
}
