//
//  SimulatorBar.swift
//  iPodSync
//
//  Barra sobre el iPod (como la de un simulador): nombre y espacio, luz, captura y expulsar.
//

import SwiftUI
import AppKit

struct SimulatorBar: View {
    let simulator: IPodSimulator
    let monitor: IPodMonitor
    @State private var copiedShot = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack {
                    WindowTrafficLights()
                    Spacer()
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .padding(.leading, 56)
            }

            HStack(spacing: 4) {
                barButton(simulator.backlightOn ? "Apagar la luz" : "Encender la luz",
                          systemImage: simulator.backlightOn ? "lightbulb.fill" : "lightbulb",
                          help: "Luz de la pantalla (⇧⌘L)") {
                    simulator.toggleBacklight()
                }
                .disabled(!simulator.isConnected)

                barButton("Copiar captura de la pantalla",
                          systemImage: "camera",
                          help: "Copiar la pantalla del iPod al portapapeles") {
                    copyScreenshot()
                }
                .disabled(!simulator.isConnected)

                ejectButton
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(width: 300)
        // Se arrastra la ventana desde esta barra, como en un simulador (va debajo del vidrio).
        .background(WindowDragArea())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// Expulsar el iPod. Desconectado: con el simulado se puede "conectar"; con el real, hay que usar el cable.
    @ViewBuilder
    private var ejectButton: some View {
        if simulator.isConnected {
            barButton(monitor.isEjecting ? "Expulsando…" : "Expulsar",
                      systemImage: "eject",
                      help: "Expulsar el iPod (⌘E)") {
                monitor.eject()
            }
            .disabled(monitor.isEjecting)
        } else {
            barButton("Conectar",
                      systemImage: "cable.connector",
                      help: simulator.isSimulated ? "Volver a conectar el iPod de prueba" : "Conecta tu iPod con el cable USB") {
                monitor.connectSimulated()
            }
            .disabled(!simulator.isSimulated)
        }
    }

    private var title: String {
        if copiedShot { return "Captura copiada" }
        if monitor.isEjecting { return "Expulsando…" }
        guard simulator.isConnected else {
            return simulator.isSimulated ? "iPod de prueba · desconectado" : "Conecta tu iPod"
        }
        return "\(simulator.deviceName) · \(simulator.freeSpaceText)"
    }

    private func barButton(_ title: String,
                           systemImage: String,
                           help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 14))
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    /// Copia la pantalla del iPod como imagen. Al portapapeles para no pedir permisos de carpetas (sandbox).
    private func copyScreenshot() {
        let renderer = ImageRenderer(content: LCDScreen(simulator: simulator).frame(width: 204, height: 152))
        renderer.scale = 3
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        NSSound(named: "Tink")?.play()

        withAnimation { copiedShot = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { copiedShot = false }
        }
    }
}

#Preview("SimulatorBar · barra del simulador") {
    SimulatorBar(simulator: IPodSimulator(), monitor: IPodMonitor())
        .padding(30)
        .background(Wallpaper())
}

#Preview("SimulatorBar · desconectado") {
    let sim = IPodSimulator()
    sim.eject()
    return SimulatorBar(simulator: sim, monitor: IPodMonitor())
        .padding(30)
        .background(Wallpaper())
}
