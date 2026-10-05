//
//  WindowTrafficLights.swift
//  iPodSync
//
//  Semáforo de la ventana dibujado dentro de la barra del simulador.
//

import SwiftUI
import AppKit

/// Semáforo de la ventana dibujado dentro de la barra del simulador.
struct WindowTrafficLights: View {
    @State private var isHovering = false
    /// Como los semáforos de macOS: grises cuando la ventana no está activa.
    @Environment(\.appearsActive) private var appearsActive

    /// La ventana del emulador (no "la activa": con Ajustes adelante, cerraba Ajustes).
    private var emulatorWindow: NSWindow? {
        NSApp.windows.first { $0 is EmulatorWindow }
    }

    var body: some View {
        HStack(spacing: 8) {
            light(Color(hex: 0xFF5F57), symbol: "xmark", label: "Cerrar") {
                emulatorWindow?.close()
            }
            light(Color(hex: 0xFEBC2E), symbol: "minus", label: "Minimizar") {
                emulatorWindow?.miniaturize(nil)
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
                .fill(appearsActive || isHovering ? color : Color.white.opacity(0.22))
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

#Preview("WindowTrafficLights · semáforo de la ventana") {
    WindowTrafficLights()
        .padding()
        .background(Color.black.opacity(0.8))
}
