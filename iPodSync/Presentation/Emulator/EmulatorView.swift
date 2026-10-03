//
//  EmulatorView.swift
//  iPodSync
//
//  Ventana estilo emulador, sin fondo: el iPod a la izquierda y el panel "En tu Mac" a la derecha.
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

#Preview("EmulatorView · emulador (iPod + En tu Mac)") {
    EmulatorView(simulator: IPodSimulator(), library: LibraryState(), monitor: IPodMonitor())
        .frame(width: 800, height: 760)
        .background(Wallpaper())
}
