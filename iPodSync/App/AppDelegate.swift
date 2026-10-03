//
//  AppDelegate.swift
//  iPodSync
//
//  Menú del Dock y cierre de la app al cerrar su única ventana.
//

import SwiftUI
import AppKit

/// Menú del Dock (clic derecho en el ícono) y cierre de la app al cerrar su única ventana.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var simulator: IPodSimulator?
    var library: LibraryState?
    var monitor: IPodMonitor?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let simulator, let library, let monitor else { return nil }
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
        if simulator.isConnected {
            menu.addItem(ActionMenuItem(title: "Expulsar iPod") { monitor.eject() })
        } else if simulator.isSimulated {
            menu.addItem(ActionMenuItem(title: "Conectar iPod de prueba") { monitor.connectSimulated() })
        }
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
