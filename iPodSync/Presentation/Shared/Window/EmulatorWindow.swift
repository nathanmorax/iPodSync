//
//  EmulatorWindow.swift
//  iPodSync
//
//  Ventana sin marco de verdad (borderless): macOS no le dibuja barra de título,
//  ni borde, ni la línea clara de arriba. Una ventana sin marco normalmente no puede
//  ser la ventana activa (y el buscador no recibiría texto); esta subclase sí puede.
//

import SwiftUI
import AppKit

final class EmulatorWindow: NSWindow {
    /// Mismo tamaño que RootView (.frame(width: 800, height: 760)).
    static let contentSize = NSSize(width: 800, height: 760)

    init<Content: View>(rootView: Content) {
        let hosting = NSHostingView(rootView: rootView)
        // Tamaño fijo: si la ventana se ajusta sola al contenido, al abrir mide 0 y
        // luego crece hacia la derecha, quedando corrida y fuera de la pantalla.
        hosting.sizingOptions = []
        let size = Self.contentSize

        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .miniaturizable, .closable],
                   backing: .buffered,
                   defer: false)

        contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        setContentSize(size)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false              // cada panel tiene su propia sombra
        isReleasedWhenClosed = false
        isRestorable = false
        isMovable = true
        isMovableByWindowBackground = false
        title = "iPodSync"
        collectionBehavior.insert(.fullScreenNone)
        center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Sin marco, macOS no sabe minimizar ni cerrar con ⌘W por sí solo: se hace a mano.
    override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
    override func performClose(_ sender: Any?) { close() }
}
