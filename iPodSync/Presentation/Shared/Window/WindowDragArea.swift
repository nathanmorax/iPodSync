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

    /// Arrastra la ventana con el mecanismo del sistema (`performDrag`): respeta la barra de menús,
    /// el acomodo de ventanas en los bordes y Mission Control. Antes se movía a mano.
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                // Doble clic como en una barra de título, según Ajustes del Sistema ›
                // Escritorio y Dock › "Doble clic en la barra de título de una ventana para".
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "None":
                    break
                default:
                    // "Minimize" y "Maximize": la ventana es de tamaño fijo, así que se minimiza.
                    window.miniaturize(nil)
                }
                return
            }
            window.performDrag(with: event)
        }
    }
}
