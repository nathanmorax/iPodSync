//
//  main.swift
//  iPodSyncLauncher
//
//  Ayudante mínimo: macOS lo despierta cuando se conecta el iPod (LaunchEvents del plist),
//  abre iPodSync y se cierra. No tiene ventana ni ícono en el Dock.
//

import AppKit
import XPC
import os

let log = Logger(subsystem: "com.mora.iPodSync.launcher", category: "launcher")

/// iPodSync.app: el ayudante vive en iPodSync.app/Contents/MacOS/iPodSyncLauncher.
func mainAppURL() -> URL? {
    if let exe = Bundle.main.executableURL {
        let app = exe.deletingLastPathComponent()   // MacOS
            .deletingLastPathComponent()            // Contents
            .deletingLastPathComponent()            // iPodSync.app
        if app.pathExtension == "app" { return app }
    }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mora.iPodSync")
}

func openMainApp() {
    guard let url = mainAppURL() else {
        log.error("No se encontró iPodSync.app")
        exit(1)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        if let error { log.error("No se pudo abrir iPodSync: \(error.localizedDescription, privacy: .public)") }
        else { log.info("iPodSync abierto porque se conectó el iPod") }
        exit(error == nil ? 0 : 1)
    }
}

// launchd entrega el aviso de "se conectó el USB" por este canal. Hay que recibirlo
// (si no, launchd vuelve a lanzar el ayudante una y otra vez).
xpc_set_event_stream_handler("com.apple.iokit.matching", DispatchQueue.main) { event in
    let name = xpc_dictionary_get_string(event, "XPCEventName").map { String(cString: $0) } ?? "?"
    log.info("iPod conectado (\(name, privacy: .public))")
    openMainApp()
}

// Si después de unos segundos no llegó ningún aviso, no hay nada que hacer.
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(0) }

dispatchMain()
