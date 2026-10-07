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
    /// Una sola ventana de vidrio (diseño AT1). RootView usa este mismo tamaño.
    static let contentSize = NSSize(width: 1000, height: 640)
    /// Mismo radio que el vidrio de EmulatorView.
    static let cornerRadius: CGFloat = 24

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
        // Recortar las esquinas de la ventana igual que el vidrio (radio 24). Sin esto, macOS
        // calcula la sombra con el rectángulo completo y se ve un marco cuadrado alrededor.
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Self.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        setContentSize(size)
        isOpaque = false
        backgroundColor = .clear
        // Sombra de macOS: sigue la forma redondeada del vidrio (la parte transparente no la tiene).
        hasShadow = true
        isReleasedWhenClosed = false
        isRestorable = false
        isMovable = true
        isMovableByWindowBackground = false
        title = "iPodSync"
        collectionBehavior.insert(.fullScreenNone)
        center()
        // La sombra se calcula con lo que ya está dibujado: recalcularla cuando SwiftUI pinte.
        DispatchQueue.main.async { [weak self] in self?.invalidateShadow() }
    }

    override func becomeKey() {
        super.becomeKey()
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Sin marco, macOS no sabe minimizar ni cerrar con ⌘W por sí solo: se hace a mano.
    override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
    override func performClose(_ sender: Any?) { close() }
}
