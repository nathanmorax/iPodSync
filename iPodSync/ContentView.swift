//
//  ContentView.swift
//  iPodSync
//
//  Created by Satori Tech 341 on 01/10/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Raíz de la ventana: estilo emulador (iPod + panel "En tu Mac").
/// Enviar, cancelar, luz y expulsar siguen en la barra de menús con sus atajos.
struct ContentView: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState

    var body: some View {
        EmulatorView(simulator: simulator, library: library)
            .frame(width: 800, height: 760)
            .navigationTitle("iPodSync")
            // Sin fondo de ventana: solo flotan el iPod y los paneles sobre el escritorio.
            .containerBackground(.clear, for: .window)
            .background(TransparentWindow())
            .fileImporter(isPresented: $library.isImporting,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                let access = urls.map { $0.startAccessingSecurityScopedResource() }
                simulator.addSongs(from: urls)
                for (url, granted) in zip(urls, access) where granted { url.stopAccessingSecurityScopedResource() }
            }
            .iPodKeyboardNavigation(simulator)
            .onChange(of: simulator.pendingCount, initial: true) { _, pending in
                // Insignia en el Dock con las canciones pendientes.
                NSApp.dockTile.badgeLabel = pending > 0 ? "\(pending)" : nil
            }
            .onAppear {
                // Que las flechas del teclado vayan al iPod al abrir, no al buscador.
                DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            }
    }
}

#Preview {
    ContentView(simulator: IPodSimulator(), library: LibraryState())
        .frame(width: 800, height: 760)
        .background(Wallpaper())
}
