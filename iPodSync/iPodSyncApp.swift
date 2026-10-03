//
//  iPodSyncApp.swift
//  iPodSync
//
//  Created by Satori Tech 341 on 01/10/26.
//

import SwiftUI
import AppKit

@main
struct iPodSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var simulator = IPodSimulator()
    @State private var library = LibraryState()

    var body: some Scene {
        // Ventana estándar: se puede mover, cambiar de tamaño, minimizar y poner en pantalla completa.
        // macOS recuerda su tamaño y posición entre aperturas.
        Window("iPodSync", id: "main") {
            ContentView(simulator: simulator, library: library)
                .task {
                    appDelegate.simulator = simulator
                    appDelegate.library = library
                }
        }
        // Ventana sin marco ni barra de título (tipo emulador). Transparente gracias a
        // .containerBackground(.clear, for: .window) en ContentView; se arrastra desde la barra del simulador.
        .windowStyle(.plain)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .commands {
            IPodSyncCommands(simulator: simulator, library: library)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Barra de menús

/// Todo lo que se puede hacer con botones también está en la barra de menús, con atajos.
struct IPodSyncCommands: Commands {
    let simulator: IPodSimulator
    let library: LibraryState

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

            Button("Expulsar") { simulator.eject() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!simulator.isConnected)
            Button("Conectar") { simulator.connect() }
                .disabled(simulator.isConnected)
        }
    }
}

// MARK: - Dock

/// Menú del Dock (clic derecho en el ícono) y cierre de la app al cerrar su única ventana.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var simulator: IPodSimulator?
    var library: LibraryState?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let simulator, let library else { return nil }
        let menu = NSMenu()

        for scope in LibraryScope.allCases {
            let item = ActionMenuItem(title: scope.title) {
                library.scope = scope
                NSApp.activate()
            }
            item.state = library.scope == scope ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if simulator.isTransferring {
            menu.addItem(ActionMenuItem(title: "Cancelar envíos") { simulator.cancelTransfers() })
        }
        menu.addItem(simulator.isConnected
                     ? ActionMenuItem(title: "Expulsar iPod") { simulator.eject() }
                     : ActionMenuItem(title: "Conectar iPod") { simulator.connect() })
        return menu
    }
}

/// NSMenuItem que ejecuta un closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    @objc private func run() { handler() }
}
