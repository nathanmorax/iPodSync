//
//  Theme.swift
//  iPodSync
//
//  Colores del sistema donde existen (se adaptan a modo claro/oscuro, acento y contraste)
//  y colores propios solo para el "objeto" iPod y su pantalla LCD.
//

import SwiftUI
import AppKit

enum Theme {
    // MARK: Biblioteca (semánticos / adaptativos)
    static let libraryBackground = Color.dynamic(light: 0xF5F5F7, dark: 0x232326)
    static let card              = Color(nsColor: .controlBackgroundColor)
    static let cardStroke        = Color(nsColor: .separatorColor)
    static let groupHeader       = Color.dynamic(light: 0xFAFAFA, dark: 0x2B2B2E)
    static let searchBackground  = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    /// "Ya está en el iPod": verde menta suave (antes 0x4CC26F, muy chillón sobre el panel oscuro).
    static let onDeviceGreen     = Color.dynamic(light: 0x2E8B6E, dark: 0x8ED9BC)

    // MARK: Escenario del iPod
    static let stage      = Color.dynamic(light: 0xF1F0EC, dark: 0x19191B)
    static let ipodBody   = Color.dynamic(light: 0xE9E8E3, dark: 0x2C2C2F)
    static let ipodRing   = Color.dynamic(light: 0xD6D5CF, dark: 0x3A3A3D)
    static let wheel      = Color.dynamic(light: 0xF7F6F2, dark: 0x232326)
    static let wheelLabel = Color.dynamic(light: 0x8F8E87, dark: 0x9A9AA0)

    // MARK: LCD (siempre igual: es la pantalla física)
    static let lcdBackground = Color(hex: 0xD9DCD0)
    static let lcdBacklight  = Color(hex: 0xC6E0C0)
    static let lcdOff        = Color(hex: 0x9DA094)
    static let lcdInk        = Color(hex: 0x22261F)
    static let lcdBezel      = Color(hex: 0x9EA195)

    /// Color de la luz del LCD elegido en Ajustes.
    static func lcdBacklight(for tint: String) -> Color {
        switch tint {
        case "blue":  Color(hex: 0xBFD6E6)
        case "amber": Color(hex: 0xEED9AE)
        default:      lcdBacklight
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Color que cambia con la apariencia del sistema (claro / oscuro).
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Font {
    /// Tipografía monoespaciada de la pantalla LCD.
    static func lcd(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
