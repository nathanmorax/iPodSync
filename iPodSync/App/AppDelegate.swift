//
//  AppDelegate.swift
//  iPodSync
//
//  Dueño de los modelos y de la ventana del emulador; menú del Dock y cierre de la app.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let simulator = IPodSimulator()
    let library = LibraryState()
    let monitor = IPodMonitor()
    let backup = BackupViewModel()

    private var window: EmulatorWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
    }

    /// La ventana la crea AppKit (no SwiftUI) para que sea sin marco de verdad.
    func showMainWindow() {
        if window == nil {
            let root = RootView(simulator: simulator, library: library, monitor: monitor)
                .environment(backup)
            window = EmulatorWindow(rootView: root)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Clic en el ícono del Dock con la ventana minimizada: la vuelve a mostrar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        for scope in LibraryScope.allCases {
            let item = ActionMenuItem(title: scope.title) { [library] in
                library.scope = scope
                NSApp.activate()
            }
            item.state = library.scope == scope ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if simulator.isTransferring {
            menu.addItem(ActionMenuItem(title: "Cancelar envíos") { [simulator] in simulator.cancelTransfers() })
        }
        if simulator.isConnected {
            menu.addItem(ActionMenuItem(title: "Expulsar iPod") { [monitor] in monitor.eject() })
        } else if simulator.isSimulated {
            menu.addItem(ActionMenuItem(title: "Conectar iPod de prueba") { [monitor] in monitor.connectSimulated() })
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
