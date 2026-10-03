//
//  iPodSyncApp.swift
//  iPodSync
//
//  Punto de entrada: la ventana del emulador y la de Ajustes.
//

import SwiftUI
import AppKit

@main
struct iPodSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var simulator = IPodSimulator()
    @State private var library = LibraryState()
    @State private var monitor = IPodMonitor()

    var body: some Scene {
        // Ventana estándar: se puede mover, cambiar de tamaño, minimizar y poner en pantalla completa.
        // macOS recuerda su tamaño y posición entre aperturas.
        Window("iPodSync", id: "main") {
            RootView(simulator: simulator, library: library, monitor: monitor)
                .task {
                    appDelegate.simulator = simulator
                    appDelegate.library = library
                    appDelegate.monitor = monitor
                }
        }
        // Ventana sin marco ni barra de título (tipo emulador). Transparente gracias a
        // .containerBackground(.clear, for: .window) en RootView; se arrastra desde la barra del simulador.
        .windowStyle(.plain)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .commands {
            IPodSyncCommands(simulator: simulator, library: library, monitor: monitor)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Barra de menús
