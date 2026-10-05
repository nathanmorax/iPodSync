//
//  BackupWindow.swift
//  iPodSync
//
//  Respaldar / Restaurar en su propia ventana en lugar de una hoja.
//  Con la ventana transparente del emulador, una hoja oscurecía todo el rectángulo
//  de la ventana (se veía un fondo negro). Una ventana aparte no toca al emulador.
//

import SwiftUI
import AppKit

@MainActor
final class BackupWindow: NSObject, NSWindowDelegate {
    static let shared = BackupWindow()

    private var window: NSWindow?
    private var onClose: (() -> Void)?

    /// Muestra (o trae al frente) la ventana con el contenido de Respaldo.
    func show<Content: View>(_ content: Content, onClose: @escaping () -> Void) {
        self.onClose = onClose
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Respaldo del iPod"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// La cierra desde el código (al terminar o con "Listo").
    func hide() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
    }

    // MARK: NSWindowDelegate

    /// El botón rojo hace lo mismo que "Cancelar"/"Cerrar": el modelo decide si se puede
    /// (mientras copia, no se cierra).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return false     // la cierra `hide()` cuando el modelo pone isPresented = false
    }
}
