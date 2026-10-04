//
//  RootView.swift
//  iPodSync
//
//  Created by Satori Tech 341 on 01/10/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Raíz de la ventana: estilo emulador (iPod + panel "En tu Mac").
/// Enviar, cancelar, luz y expulsar siguen en la barra de menús con sus atajos.
struct RootView: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState
    @Bindable var monitor: IPodMonitor
    @AppStorage(SettingsKey.simulateIPod) private var simulateIPod = false
    @Environment(BackupViewModel.self) private var backup

    var body: some View {
        EmulatorView(simulator: simulator, library: library, monitor: monitor)
            .frame(width: 800, height: 760)
            .navigationTitle("iPodSync")
            // Sin fondo de ventana: solo flotan el iPod y los paneles sobre el escritorio.
            .containerBackground(.clear, for: .window)
            .background(TransparentWindow())
            .fileImporter(isPresented: $library.isImporting,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { await simulator.importFiles(urls) }
            }
            .iPodKeyboardNavigation(simulator)
            .onChange(of: simulator.pendingCount, initial: true) { _, pending in
                // Insignia en el Dock con las canciones pendientes.
                NSApp.dockTile.badgeLabel = pending > 0 ? "\(pending)" : nil
            }
            // Empieza a detectar el iPod real (o usa el de prueba según Ajustes).
            .task { monitor.start(simulator: simulator) }
            .onChange(of: simulateIPod) { monitor.rescan() }
            .alert("iPodSync",
                   isPresented: Binding(get: { monitor.alertMessage != nil },
                                        set: { if !$0 { monitor.alertMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(monitor.alertMessage ?? "")
            }
            .alert("No se pudo enviar al iPod",
                   isPresented: Binding(get: { simulator.sendMessage != nil },
                                        set: { if !$0 { simulator.sendMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(simulator.sendMessage ?? "")
            }
            .alert("Algunos archivos no se agregaron",
                   isPresented: Binding(get: { simulator.importMessage != nil },
                                        set: { if !$0 { simulator.importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(simulator.importMessage ?? "")
            }
            .sheet(isPresented: Binding(get: { backup.isPresented },
                                        set: { if !$0 { backup.close() } })) {
                BackupSheet(viewModel: backup, monitor: monitor)
            }
            .onAppear {
                // Que las flechas del teclado vayan al iPod al abrir, no al buscador.
                DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            }
    }
}

#Preview("RootView · ventana completa") {
    RootView(simulator: IPodSimulator(), library: LibraryState(), monitor: IPodMonitor())
        .environment(BackupViewModel())
        .frame(width: 800, height: 760)
        .background(Wallpaper())
}
