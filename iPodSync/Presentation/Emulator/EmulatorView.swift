//
//  EmulatorView.swift
//  iPodSync
//
//  Diseño AT1 "una sola ventana de vidrio": el iPod y la biblioteca en el mismo vidrio translúcido
//  (se ve el escritorio a través). Arriba una sola barra (título, buscador, ⓘ ⟳ ⏏); a la izquierda
//  el iPod con En mi Mac | En mi iPod debajo; a la derecha la biblioteca.
//

import SwiftUI
import AppKit

struct EmulatorView: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState
    let monitor: IPodMonitor
    @AppStorage(SettingsKey.showKeyHints) private var showKeyHints = true

    private let corner = EmulatorWindow.cornerRadius

    var body: some View {
        VStack(spacing: 0) {
            SimulatorBar(simulator: simulator, library: library, monitor: monitor)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 18) {
                    IPodDeviceView(simulator: simulator)
                        .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
                        // Desconectado se ve igual de nítido; la pantalla dice "Conecta tu iPod".
                        .opacity(simulator.isConnected ? 1 : 0.9)
                        .animation(.easeInOut(duration: 0.3), value: simulator.isConnected)
                        .contextMenu { iPodMenu }

                    LibrarySourcePicker(library: library, simulator: simulator, monitor: monitor)
                        .frame(width: 270)

                    if simulator.isConnected && showKeyHints {
                        KeyHints()
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .frame(width: 330)
                .frame(maxHeight: .infinity)

                Divider()

                MacLibraryPanel(library: library, simulator: simulator, monitor: monitor)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        // Un solo vidrio para todo (con un tinte oscuro para que el texto se lea en cualquier fondo).
        .glassEffect(.regular.tint(.black.opacity(0.3)), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
        // Sin sombra de SwiftUI: se cortaba en la orilla de la ventana y se veía un rectángulo
        // oscuro alrededor. La sombra la pone macOS (EmulatorWindow.hasShadow) y sigue las esquinas.
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    /// Clic derecho sobre el iPod: la luz y la captura (antes eran botones de la barra).
    @ViewBuilder
    private var iPodMenu: some View {
        Button(simulator.backlightOn ? "Apagar la luz" : "Encender la luz",
               systemImage: simulator.backlightOn ? "lightbulb.fill" : "lightbulb") {
            simulator.toggleBacklight()
        }
        .disabled(!simulator.isConnected)
        Button("Copiar captura de la pantalla", systemImage: "camera") { copyScreenshot() }
            .disabled(!simulator.isConnected)
    }

    /// Copia la pantalla del iPod como imagen. Al portapapeles para no pedir permisos de carpetas (sandbox).
    private func copyScreenshot() {
        let renderer = ImageRenderer(content: LCDScreen(simulator: simulator).frame(width: 204, height: 152))
        renderer.scale = 3
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        NSSound(named: "Tink")?.play()
    }
}

#Preview("EmulatorView · una sola ventana de vidrio") {
    EmulatorView(simulator: IPodSimulator(), library: LibraryState(), monitor: IPodMonitor())
        .environment(BackupViewModel())
        .frame(width: EmulatorWindow.contentSize.width, height: EmulatorWindow.contentSize.height)
        .background(Wallpaper())
}
