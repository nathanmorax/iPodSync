//
//  TransparentWindow.swift
//  iPodSync
//
//  Hace la ventana transparente, como un emulador: solo se ven el iPod y los paneles,
//  sin fondo detrás. Los botones de cerrar/minimizar se dibujan en la barra del simulador.
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
        guard let window else { return }

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
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.isMovable = true
        window.isMovableByWindowBackground = false
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
    }
}

/// Semáforo de la ventana dibujado dentro de la barra del simulador.
struct WindowTrafficLights: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            light(Color(hex: 0xFF5F57), symbol: "xmark", label: "Cerrar") {
                NSApp.keyWindow?.close()
            }
            light(Color(hex: 0xFEBC2E), symbol: "minus", label: "Minimizar") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            // La ventana tiene tamaño fijo, así que el botón verde va apagado (como en otras utilidades de macOS).
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
        .onHover { isHovering = $0 }
    }

    private func light(_ color: Color, symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay {
                    if isHovering {
                        Image(systemName: symbol)
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Arrastrar la ventana

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
