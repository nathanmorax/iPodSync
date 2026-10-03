//
//  CapacityBar.swift
//  iPodSync
//
//  Barra de espacio del iPod: otros, música y por enviar.
//

import SwiftUI
import UniformTypeIdentifiers

struct CapacityBar: View {
    let other: Double
    let music: Double
    let pending: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(Color.gray.opacity(0.7))
                    .frame(width: geo.size.width * other)
                Rectangle().fill(Color.green)
                    .frame(width: max(3, geo.size.width * music))
                if pending > 0 {
                    Rectangle().fill(Color.accentColor)
                        .frame(width: max(3, geo.size.width * pending))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.1))
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: music)
        .animation(.easeOut(duration: 0.3), value: pending)
        .accessibilityElement()
        .accessibilityLabel("Espacio usado en el iPod")
    }
}

#Preview("CapacityBar · barra de espacio") {
    CapacityBar(other: 0.58, music: 0.02, pending: 0.03)
        .frame(width: 320)
        .padding()
}
