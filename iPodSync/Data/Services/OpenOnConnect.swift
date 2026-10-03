//
//  OpenOnConnect.swift
//  iPodSync
//
//  "Abrir iPodSync al conectar el iPod": registra o quita el ayudante (iPodSyncLauncher)
//  con SMAppService. macOS pide aprobarlo en Ajustes del Sistema › General › Ítems de inicio.
//

import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class OpenOnConnect {
    static let plistName = "com.mora.iPodSync.launcher.plist"

    private(set) var status: SMAppService.Status = .notRegistered
    var errorMessage: String?

    private let service = SMAppService.agent(plistName: OpenOnConnect.plistName)

    init() { refresh() }

    func refresh() {
        status = service.status
    }

    /// Encendido = registrado (aunque falte la aprobación en Ajustes del Sistema).
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        if enabled && status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Texto bajo el interruptor en Ajustes.
    var statusText: String {
        switch status {
        case .enabled:
            return "Listo. Al conectar el iPod, iPodSync se abre solo."
        case .requiresApproval:
            return "Falta aprobarlo en Ajustes del Sistema › General › Ítems de inicio."
        case .notFound:
            return "No se encontró el ayudante dentro de la app. Revisa que el target iPodSyncLauncher esté incluido."
        case .notRegistered:
            return "Apagado."
        @unknown default:
            return ""
        }
    }
}
