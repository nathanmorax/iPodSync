//
//  ContentView.swift
//  iPodSync
//
//  Created by Satori Tech 341 on 01/10/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    let simulator: IPodSimulator
    @Bindable var library: LibraryState

    var body: some View {
        HStack(spacing: 0) {
            LibraryPane(library: library, simulator: simulator)
                .frame(minWidth: 420, maxWidth: .infinity)

            Divider()

            DevicePane(simulator: simulator)
                .frame(minWidth: 400, maxWidth: .infinity)
        }
        .frame(minWidth: 860, minHeight: 600)
        .navigationTitle(library.scope.title)
        .navigationSubtitle(subtitle)
        .toolbar(id: "main") { toolbarContent }
        .toolbarRole(.editor)
        .searchable(text: $library.query, placement: .toolbar, prompt: "Buscar canción o artista")
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
            // Evita que el buscador tome el foco al abrir y se quede con las flechas.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
    }

    private var subtitle: String {
        let shown = library.filter(simulator.songs)
        let count: String = switch library.scope {
        case .songs:   "\(shown.count) canciones"
        case .artists: "\(Set(shown.map(\.artist)).count) artistas"
        case .albums:  "\(shown.count) álbumes"
        }
        return "\(count) · \(simulator.onDeviceSongs.count) en el iPod"
    }

    private var sendableSelection: [Song.ID] {
        simulator.songs.filter { library.selection.contains($0.id) && simulator.canSend($0) }.map(\.id)
    }

    // MARK: Barra de herramientas (personalizable con clic derecho › Personalizar barra de herramientas…)

    @ToolbarContentBuilder
    private var toolbarContent: some CustomizableToolbarContent {
        ToolbarItem(id: "scope", placement: .navigation) {
            Picker("Ver por", selection: $library.scope) {
                ForEach(LibraryScope.allCases) { scope in
                    Label(scope.title, systemImage: scope.systemImage).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .help("Cambiar vista (⌘1, ⌘2, ⌘3)")
        }

        ToolbarItem(id: "add", placement: .primaryAction, showsByDefault: false) {
            Button {
                library.isImporting = true
            } label: {
                Label("Agregar", systemImage: "plus")
            }
            .help("Agregar canciones a la biblioteca (⌘O)")
        }

        ToolbarItem(id: "send", placement: .primaryAction) {
            Button {
                simulator.sendAll(sendableSelection)
                library.clearSelection()
            } label: {
                Label("Enviar selección", systemImage: "arrow.up.circle")
            }
            .disabled(sendableSelection.isEmpty)
            .help(sendableSelection.isEmpty
                  ? "Selecciona canciones para enviarlas"
                  : "Enviar \(sendableSelection.count) al iPod (⌘↩)")
        }

        ToolbarItem(id: "cancel", placement: .primaryAction, showsByDefault: false) {
            Button {
                simulator.cancelTransfers()
            } label: {
                Label("Cancelar envíos", systemImage: "xmark.circle")
            }
            .disabled(!simulator.isTransferring)
            .help("Cancelar envíos (⌘.)")
        }

        ToolbarItem(id: "light", placement: .primaryAction, showsByDefault: false) {
            Button {
                simulator.toggleBacklight()
            } label: {
                Label("Luz", systemImage: simulator.backlightOn ? "lightbulb.fill" : "lightbulb")
            }
            .disabled(!simulator.isConnected)
            .help("Luz de la pantalla (⇧⌘L)")
        }

        ToolbarItem(id: "eject", placement: .primaryAction) {
            Button {
                withAnimation { simulator.isConnected ? simulator.eject() : simulator.connect() }
            } label: {
                Label(simulator.isConnected ? "Expulsar" : "Conectar",
                      systemImage: simulator.isConnected ? "eject" : "cable.connector")
            }
            .help(simulator.isConnected ? "Expulsar el iPod (⌘E)" : "Volver a conectar el iPod")
        }
    }
}

#Preview {
    ContentView(simulator: IPodSimulator(), library: LibraryState())
        .frame(width: 1060, height: 680)
}
