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
    @State private var backup = BackupViewModel()

    var body: some Scene {
        // Ventana estándar: se puede mover, cambiar de tamaño, minimizar y poner en pantalla completa.
        // macOS recuerda su tamaño y posición entre aperturas.
        Window("iPodSync", id: "main") {
            RootView(simulator: simulator, library: library, monitor: monitor)
                .environment(backup)
                .task {
                    appDelegate.simulator = simulator
                    appDelegate.library = library
                    appDelegate.monitor = monitor
                }
        }
        // Ventana transparente tipo emulador. Usa .hiddenTitleBar (no .plain) porque una ventana
        // sin marco no puede ser la ventana activa y entonces el buscador no recibe lo que escribes.
        // TransparentWindow quita el fondo, la barra y los botones; se arrastra desde la barra del simulador.
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .commands {
            IPodSyncCommands(simulator: simulator, library: library, monitor: monitor, backup: backup)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Barra de menús
