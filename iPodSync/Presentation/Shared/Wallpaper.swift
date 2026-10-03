//
//  Wallpaper.swift
//  iPodSync
//
//  Fondo de escritorio solo para los Previews de Xcode (la app real es transparente).
//

import SwiftUI
import AppKit

/// Fondo de escritorio solo para los Previews de Xcode (la app real es transparente).
struct Wallpaper: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2<Float>(0, 0),   SIMD2<Float>(0.5, 0),    SIMD2<Float>(1, 0),
                SIMD2<Float>(0, 0.5), SIMD2<Float>(0.55, 0.45), SIMD2<Float>(1, 0.5),
                SIMD2<Float>(0, 1),   SIMD2<Float>(0.5, 1),    SIMD2<Float>(1, 1)
            ],
            colors: [
                Color(hex: 0x2E2A5C), Color(hex: 0x3B3A86), Color(hex: 0x7A3E8E),
                Color(hex: 0x23407F), Color(hex: 0x1F3F86), Color(hex: 0x5A3E8E),
                Color(hex: 0x2C8A4A), Color(hex: 0x1E5E6A), Color(hex: 0x1F4F7A)
            ]
        )
        .accessibilityHidden(true)
    }
}

#Preview("Wallpaper · fondo solo para Previews") {
    Wallpaper()
        .frame(width: 400, height: 260)
}
