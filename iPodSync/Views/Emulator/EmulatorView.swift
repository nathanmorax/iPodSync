//
//  EmulatorView.swift
//  iPodSync
//
//  Ventana estilo emulador, sin fondo (se ve el escritorio): el iPod a la izquierda (barra del simulador
//  y dispositivo; el progreso se ve en su pantalla) y el panel flotante "En tu Mac" a la derecha.
//

import SwiftUI
import AppKit

struct EmulatorView: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState
    let monitor: IPodMonitor
    @AppStorage(SettingsKey.showKeyHints) private var showKeyHints = true

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(spacing: 20) {
                SimulatorBar(simulator: simulator, monitor: monitor)

                IPodDeviceView(simulator: simulator)
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
                    .opacity(simulator.isConnected ? 1 : 0.55)
                    .saturation(simulator.isConnected ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: simulator.isConnected)

                if simulator.isConnected && showKeyHints {
                    KeyHints()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .transition(.opacity)
                }
            }
            .frame(width: 300)

            MacLibraryPanel(library: library, simulator: simulator, monitor: monitor)
                .frame(width: 384)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .ignoresSafeArea()
    }
}

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

#Preview("EmulatorView · emulador (iPod + En tu Mac)") {
    EmulatorView(simulator: IPodSimulator(), library: LibraryState(), monitor: IPodMonitor())
        .frame(width: 800, height: 760)
        .background(Wallpaper())
}

#Preview("Wallpaper · fondo solo para Previews") {
    Wallpaper()
        .frame(width: 400, height: 260)
}
