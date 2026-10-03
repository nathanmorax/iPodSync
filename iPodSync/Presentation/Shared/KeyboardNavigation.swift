//
//  KeyboardNavigation.swift
//  iPodSync
//
//  Flechas del teclado → navegación del iPod (cuando no se está escribiendo en un campo de texto).
//

import SwiftUI
import AppKit

struct KeyboardNavigation: ViewModifier {
    let simulator: IPodSimulator
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    MainActor.assumeIsolated {
                        handle(event) ? nil : event
                    }
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    /// Devuelve `true` si la tecla se consumió.
    private func handle(_ event: NSEvent) -> Bool {
        // Si el usuario está escribiendo (p. ej. en el buscador), no interceptar.
        if event.window?.firstResponder is NSText { return false }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }

        switch event.keyCode {
        case 126:             simulator.moveUp()            // ↑
        case 125:             simulator.moveDown()          // ↓
        case 124, 36, 76:     simulator.select()            // → / Return / Enter
        case 123, 53, 51:     simulator.back()              // ← / Esc / Delete
        default:              return false
        }
        return true
    }
}

extension View {
    func iPodKeyboardNavigation(_ simulator: IPodSimulator) -> some View {
        modifier(KeyboardNavigation(simulator: simulator))
    }
}
