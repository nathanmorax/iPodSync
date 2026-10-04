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
    /// El AppDelegate es dueño de los modelos y crea la ventana del emulador (sin marco).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // La ventana principal la crea AppKit en AppDelegate: así no lleva barra de título
        // ni el borde claro que macOS dibuja en las ventanas normales.
        Settings {
            SettingsView()
        }
        .commands {
            IPodSyncCommands(simulator: appDelegate.simulator,
                             library: appDelegate.library,
                             monitor: appDelegate.monitor,
                             backup: appDelegate.backup)
        }
    }
}

// MARK: - Barra de menús
