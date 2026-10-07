//
//  SimulatorBar.swift
//  iPodSync
//
//  Barra de arriba de la ventana de vidrio (diseño AT1): semáforo, "iPodSync · estado",
//  buscador y los botones ⓘ información, ⟳ enviar lo que falta y ⏏ expulsar.
//  La luz y la captura de la pantalla están en el clic derecho del iPod (y la luz en ⇧⌘L).
//

import SwiftUI
import AppKit

struct SimulatorBar: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState
    let monitor: IPodMonitor

    @State private var showsInfo = false

    var body: some View {
        HStack(spacing: 12) {
            WindowTrafficLights()

            HStack(spacing: 6) {
                Text("iPodSync")
                    .font(.system(size: 13, weight: .semibold))
                Text("· \(status)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if needsChooser {
                    Button("Elegir iPod…") { monitor.requestAccess() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .help("Si no se detecta solo al conectar el cable, elígelo a mano")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: status)

            Spacer(minLength: 12)

            LibrarySearchField(library: library)
                .frame(width: 260)

            HStack(spacing: 2) {
                infoButton
                sendButton
                ejectButton
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 52)
        // Se arrastra la ventana desde la barra (va debajo de los botones).
        .background(WindowDragArea())
    }

    // MARK: Estado

    private var status: String {
        if monitor.isEjecting { return "Expulsando…" }
        guard simulator.isConnected else {
            return simulator.isSimulated ? "iPod de prueba desconectado" : "Conecta tu iPod"
        }
        return "\(simulator.deviceName) · \(simulator.freeSpaceText)"
    }

    private var needsChooser: Bool {
        !simulator.isSimulated && !simulator.isConnected && monitor.device == nil
    }

    // MARK: Botones

    private var infoButton: some View {
        barButton("Información del iPod", systemImage: "info.circle", help: "Información del iPod") {
            showsInfo.toggle()
        }
        .disabled(!simulator.isConnected)
        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
            IPodInfoPopover(simulator: simulator, monitor: monitor) { showsInfo = false }
        }
    }

    /// ⟳ Envía todo lo que falta (con cuántas son en un globito azul).
    private var sendButton: some View {
        let pending = simulator.songs.filter { simulator.status(of: $0) == .notOnDevice }
        return barButton("Enviar lo que falta (\(pending.count))",
                         systemImage: "arrow.triangle.2.circlepath",
                         help: pending.isEmpty ? "Todo está en el iPod" : "Enviar al iPod las \(pending.count) canciones que faltan") {
            simulator.sendAll(pending.map(\.id))
        }
        .disabled(!simulator.isConnected || pending.isEmpty)
        .overlay(alignment: .topTrailing) {
            if !pending.isEmpty {
                Text(pending.count > 99 ? "99+" : "\(pending.count)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: 4, y: -3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// ⓘ Lo esencial del iPod (diseño AN1): nombre y modelo, espacio, canciones, último respaldo,
/// versión del software, y dos acciones: Mostrar en Finder y Respaldar…
struct IPodInfoPopover: View {
    let simulator: IPodSimulator
    let monitor: IPodMonitor
    let onClose: () -> Void

    @Environment(BackupViewModel.self) private var backup
    @State private var info = IPodInfoReader.Info()

    private var songCount: Int {
        simulator.isSimulated ? simulator.onDeviceSongs.count : monitor.tracks.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "ipod")
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.black.opacity(0.8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.name ?? simulator.deviceName)
                        .font(.headline)
                    Text([info.modelName ?? "iPod", "\(gb(simulator.capacityGB, digits: 0)) GB"].joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ALMACENAMIENTO")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(gb(simulator.freeGB, digits: 1)) GB libres de \(gb(simulator.capacityGB, digits: 0))")
                        .font(.caption)
                        .monospacedDigit()
                }
                CapacityBar(other: simulator.usedOtherFraction, music: simulator.usedMusicFraction, pending: 0)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                row("Canciones", "\(songCount) · \(gb(simulator.musicGB, digits: 1)) GB")
                row("Último respaldo", lastBackup)
                if let version = info.softwareVersion { row("Software", version) }
            }
            .font(.callout)

            HStack {
                Spacer()
                if let url = monitor.device?.volumeURL {
                    Button("Mostrar en Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                if !simulator.isSimulated {
                    Button("Respaldar…") {
                        onClose()
                        backup.showBackup()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(monitor.accessibleVolumeURL == nil)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .task {
            guard let volume = monitor.accessibleVolumeURL else { return }
            info = IPodInfoReader.read(volume: volume)   // archivos chicos del iPod
        }
    }

    private var lastBackup: String {
        guard !simulator.isSimulated else { return "—" }
        guard let id = monitor.device?.id, let date = backup.lastBackupDate(for: id) else { return "Nunca" }
        return date.formatted(.relative(presentation: .named))
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func gb(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }
}
