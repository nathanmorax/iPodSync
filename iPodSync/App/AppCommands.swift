//
//  AppCommands.swift
//  iPodSync
//
//  Barra de menús: todo lo que se hace con botones también está aquí, con atajos.
//

import SwiftUI
import AppKit

/// Todo lo que se puede hacer con botones también está en la barra de menús, con atajos.
struct IPodSyncCommands: Commands {
    let simulator: IPodSimulator
    let library: LibraryState
    let monitor: IPodMonitor

    var body: some Commands {
        // Archivo
        CommandGroup(replacing: .newItem) {
            Button("Agregar a la biblioteca…") { library.isImporting = true }
                .keyboardShortcut("o", modifiers: .command)
        }

        // Edición › Buscar
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Buscar en la biblioteca") { library.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: .command)
        }

        // Visualización
        CommandGroup(before: .toolbar) {
            ForEach(LibraryScope.allCases) { scope in
                Toggle(scope.title, isOn: Binding(
                    get: { library.scope == scope },
                    set: { if $0 { library.scope = scope } }
                ))
                .keyboardShortcut(scope.shortcut, modifiers: .command)
            }
            Divider()
        }

        // iPod
        CommandMenu("iPod") {
            Button("Enviar selección") {
                let ids = simulator.songs.filter { library.selection.contains($0.id) && simulator.canSend($0) }.map(\.id)
                simulator.sendAll(ids)
                library.clearSelection()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(library.selection.isEmpty || !simulator.isConnected)

            Button("Cancelar envíos") { simulator.cancelTransfers() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!simulator.isTransferring)

            Divider()

            Toggle("Luz de la pantalla", isOn: Binding(
                get: { simulator.backlightOn },
                set: { _ in simulator.toggleBacklight() }
            ))
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!simulator.isConnected)

            Divider()

            Button("Expulsar") { monitor.eject() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!monitor.canEject)
            if simulator.isSimulated {
                Button("Conectar iPod de prueba") { monitor.connectSimulated() }
                    .disabled(simulator.isConnected)
            } else {
                // Por si el iPod no se detecta solo: elegirlo a mano también lo registra.
                Button(monitor.hasAccess ? "Cambiar acceso al iPod…" : "Elegir iPod y dar acceso…") { monitor.requestAccess() }
            }
        }
    }
}

// MARK: - Dock
