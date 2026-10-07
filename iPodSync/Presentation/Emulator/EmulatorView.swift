//
//  EmulatorView.swift
//  iPodSync
//
//  Ventana estilo emulador, sin fondo (diseño AT2 "iPod protagonista"): el iPod flota solo y más
//  grande, con una cápsula de vidrio arriba (semáforo y botones) y otra abajo (estado). A la derecha,
//  el panel de vidrio de la biblioteca.
//

import SwiftUI
import AppKit

struct EmulatorView: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState
    let monitor: IPodMonitor
    @AppStorage(SettingsKey.showKeyHints) private var showKeyHints = true

    var body: some View {
        HStack(alignment: .top, spacing: 44) {
            VStack(spacing: 16) {
                SimulatorBar(simulator: simulator, monitor: monitor)

                // Más grande que antes (1,15×): el iPod es lo principal de la ventana.
                IPodDeviceView(simulator: simulator)
                    .scaleEffect(Self.iPodScale)
                    .frame(width: 236 * Self.iPodScale, height: 392 * Self.iPodScale)
                    .shadow(color: .black.opacity(0.32), radius: 30, y: 20)
                    // Desconectado se ve igual de nítido; la pantalla dice "Conecta tu iPod".
                    .opacity(simulator.isConnected ? 1 : 0.9)
                    .animation(.easeInOut(duration: 0.3), value: simulator.isConnected)

                IPodStatusPill(simulator: simulator, monitor: monitor)

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
                .frame(width: 396)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .ignoresSafeArea()
    }

    private static let iPodScale: CGFloat = 1.15
}

#Preview("EmulatorView · emulador (iPod + En tu Mac)") {
    EmulatorView(simulator: IPodSimulator(), library: LibraryState(), monitor: IPodMonitor())
        .environment(BackupViewModel())
        .frame(width: 800, height: 760)
        .background(Wallpaper())
}
