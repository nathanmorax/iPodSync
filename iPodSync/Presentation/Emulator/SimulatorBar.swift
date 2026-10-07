//
//  SimulatorBar.swift
//  iPodSync
//
//  Diseño "iPod protagonista" (AT2): el iPod flota solo, con
//   • arriba, una cápsula de vidrio con el semáforo de la ventana y los botones (luz, captura, expulsar);
//   • abajo, una cápsula de estado: nombre y espacio, o "Esperando el cable USB… · Elegir iPod…".
//

import SwiftUI
import AppKit

struct SimulatorBar: View {
    let simulator: IPodSimulator
    let monitor: IPodMonitor
    @State private var copiedShot = false

    var body: some View {
        HStack(spacing: 4) {
            WindowTrafficLights()
            Spacer(minLength: 8)

            barButton(simulator.backlightOn ? "Apagar la luz" : "Encender la luz",
                      systemImage: simulator.backlightOn ? "lightbulb.fill" : "lightbulb",
                      help: "Luz de la pantalla (⇧⌘L)") {
                simulator.toggleBacklight()
            }
            .disabled(!simulator.isConnected)

            barButton(copiedShot ? "Captura copiada" : "Copiar captura de la pantalla",
                      systemImage: copiedShot ? "checkmark" : "camera",
                      help: "Copiar la pantalla del iPod al portapapeles") {
                copyScreenshot()
            }
            .disabled(!simulator.isConnected)

            ejectButton
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(width: 300, height: 38)
        // Se arrastra la ventana desde esta cápsula (va debajo del vidrio).
        .background(WindowDragArea())
        .glassEffect(.regular, in: Capsule())
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

    private func barButton(_ title: String,
                           systemImage: String,
                           help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 14))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 26)
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

/// Cápsula de estado debajo del iPod: nombre y espacio libre, o qué falta para conectarlo.
struct IPodStatusPill: View {
    let simulator: IPodSimulator
    let monitor: IPodMonitor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: simulator.isConnected ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 6)
            action
        }
        .padding(.horizontal, 14)
        .frame(width: 300, height: 34)
        .glassEffect(.regular, in: Capsule())
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: title)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if simulator.isConnected { return "ipod" }
        return simulator.isSimulated ? "powerplug" : "cable.connector"
    }

    private var title: String {
        if monitor.isEjecting { return "Expulsando…" }
        guard simulator.isConnected else {
            return simulator.isSimulated ? "iPod de prueba desconectado" : "Esperando el cable USB…"
        }
        return "\(simulator.deviceName) · \(simulator.freeSpaceText)"
    }

    /// Botón a la derecha: elegir el iPod a mano (real) o volver a conectar el de prueba.
    @ViewBuilder
    private var action: some View {
        if !simulator.isConnected && !monitor.isEjecting {
            Button(simulator.isSimulated ? "Conectar" : "Elegir iPod…") {
                if simulator.isSimulated { monitor.connectSimulated() } else { monitor.requestAccess() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tint)
            .help(simulator.isSimulated ? "Volver a conectar el iPod de prueba"
                                        : "Si no se detecta solo, elígelo a mano en el Finder")
        }
    }
}

#Preview("SimulatorBar · cápsula de arriba") {
    SimulatorBar(simulator: IPodSimulator(), monitor: IPodMonitor())
        .padding(30)
        .background(Wallpaper())
}

#Preview("IPodStatusPill · desconectado") {
    let sim = IPodSimulator()
    sim.eject()
    return IPodStatusPill(simulator: sim, monitor: IPodMonitor())
        .padding(30)
        .background(Wallpaper())
}
