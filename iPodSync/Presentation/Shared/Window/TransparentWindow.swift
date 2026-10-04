//
//  TransparentWindow.swift
//  iPodSync
//
//  Hace la ventana transparente, como un emulador: solo se ven el iPod y los paneles.
//

import SwiftUI
import AppKit

struct TransparentWindow: NSViewRepresentable {
    final class Coordinator {
        var didPlaceWindow = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, context.coordinator) }
    }

    private func configure(_ window: NSWindow?, _ coordinator: Coordinator) {
        // La ventana del emulador ya viene sin marco y transparente.
        guard let window, !(window is EmulatorWindow) else { return }

        // Una ventana sin marco no usa la posición por defecto de SwiftUI y aparecía pegada abajo.
        // Al abrir: centrada en la pantalla donde está (macOS la deja un poco arriba del centro).
        if !coordinator.didPlaceWindow {
            coordinator.didPlaceWindow = true
            window.isRestorable = false
            window.center()
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false                 // cada panel tiene su propia sombra
        // Por si el estilo de la ventana todavía trae barra de título: que no dibuje nada.
        // Ventana con estilo "titulado" (para que pueda ser la ventana activa y el buscador reciba
        // texto) pero sin nada visible: contenido hasta arriba, barra transparente y sin botones.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.isMovable = true
        window.isMovableByWindowBackground = false
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        // La barra de título (aunque sea transparente) dibuja una línea clara arriba de la ventana.
        // Se esconde todo su contenedor; los semáforos propios están en SimulatorBar.
        window.toolbar = nil
        window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true
    }
}
