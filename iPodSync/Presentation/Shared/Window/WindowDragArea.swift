//
//  WindowDragArea.swift
//  iPodSync
//
//  Zona desde la que se arrastra la ventana (no tiene barra de título).
//

import SwiftUI
import AppKit

/// Zona desde la que se arrastra la ventana (la ventana no tiene barra de título).
/// Se pone de fondo en la barra del simulador y en el encabezado del panel; los botones encima siguen funcionando.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Mueve la ventana a mano (posición del mouse en pantalla), así funciona aunque la ventana
    /// sin marco tenga desactivado el arrastre de AppKit.
    final class DragView: NSView {
        private var startMouse: NSPoint = .zero
        private var startOrigin: NSPoint = .zero

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                window.miniaturize(nil)      // doble clic, como en la barra de título
                return
            }
            startMouse = NSEvent.mouseLocation
            startOrigin = window.frame.origin
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: startOrigin.x + (now.x - startMouse.x),
                                          y: startOrigin.y + (now.y - startMouse.y)))
        }
    }
}
