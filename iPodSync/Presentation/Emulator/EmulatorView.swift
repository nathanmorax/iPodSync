//
//  EmulatorView.swift
//  iPodSync
//
//  Diseño AT1 "una sola ventana de vidrio": el iPod y la biblioteca en el mismo vidrio translúcido
//  (se ve el escritorio a través). Arriba una sola barra (título, buscador, ⓘ ⟳ ⏏); a la izquierda
//  el iPod con En mi Mac | En mi iPod debajo; a la derecha la biblioteca.
//  BO3: el iPod vive en un dock blanco; sin iPod el dock se ve vacío y al conectarlo el iPod baja a su lugar.
//

import SwiftUI
import AppKit

struct EmulatorView: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState
    let monitor: IPodMonitor
    @AppStorage(SettingsKey.showKeyHints) private var showKeyHints = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let corner = EmulatorWindow.cornerRadius
    /// El iPod un poco más chico para que quepan el dock, el selector y las teclas.
    private let ipodScale: CGFloat = 0.84
    /// Cuánto se hunde el iPod dentro de la ranura del dock.
    private let sink: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            SimulatorBar(simulator: simulator, library: library, monitor: monitor)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    dockStage

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

    /// El dock con su brillo cálido detrás; el iPod aparece encima cuando se conecta.
    private var dockStage: some View {
        let ipodSize = CGSize(width: 236 * ipodScale, height: 392 * ipodScale)
        let height = ipodSize.height + IPodDock.size.height - sink + 8
        return ZStack(alignment: .bottom) {
            // Brillo cálido detrás (como una lámpara en el escritorio).
            RadialGradient(colors: [Color(red: 0.95, green: 0.62, blue: 0.32).opacity(0.28), .clear],
                           center: .center, startRadius: 10, endRadius: 200)
                .frame(width: 330, height: height + 40)
                .allowsHitTesting(false)

            // Cable de la orilla izquierda al dock.
            DockCable(isTransferring: simulator.isTransferring)
                .frame(width: 60, height: 40)
                .offset(x: -(IPodDock.size.width / 2 + 28), y: -6)

            if simulator.isConnected {
                IPodDeviceView(simulator: simulator)
                    .scaleEffect(ipodScale)
                    .frame(width: ipodSize.width, height: ipodSize.height)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                    .contextMenu { iPodMenu }
                    .padding(.bottom, IPodDock.size.height - sink)
                    .transition(reduceMotion ? AnyTransition.opacity
                                : AnyTransition.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            } else {
                EmptyDockMessage(simulated: simulator.isSimulated) {
                    if simulator.isSimulated { monitor.connectSimulated() } else { monitor.requestAccess() }
                }
                .padding(.bottom, IPodDock.size.height + 70)
                .transition(.opacity)
            }

            IPodDock(isTransferring: simulator.isTransferring)
                .zIndex(2)
        }
        // Espacio abajo para la sombra del dock; se recorta para que el iPod "baje" desde
        // arriba del área y no pase por encima de la barra.
        .padding(.bottom, 22)
        .frame(width: 330, height: height + 22)
        .clipped()
        .animation(reduceMotion ? Animation.easeInOut(duration: 0.2)
                   : Animation.spring(response: 0.55, dampingFraction: 0.72), value: simulator.isConnected)
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
