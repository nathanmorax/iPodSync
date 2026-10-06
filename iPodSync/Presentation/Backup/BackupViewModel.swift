//
//  BackupViewModel.swift
//  iPodSync
//
//  Estado de la ventana de Respaldo.
//
//  Un respaldo por iPod que se actualiza: la primera vez se copia todo a "<iPod> – Respaldo";
//  las siguientes solo lo nuevo. Cada vez se guarda la base del iPod de ese día (Días/), así
//  se puede regresar el iPod a cualquier día respaldado. La música nunca se borra del respaldo
//  (salvo con "Limpiar…", cuando tú quieras).
//
//  Los respaldos viejos (una carpeta por fecha) se siguen pudiendo restaurar con "Otro respaldo…".
//

import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class BackupViewModel {
    enum Mode { case backup, restore }

    enum Phase {
        case loading                                 // revisando qué hay que copiar
        case ready                                   // resumen y botón Respaldar / Actualizar
        case chooseDay                               // elegir a qué día regresar el iPod
        case confirmRestore(IPodBackupService.Manifest, URL)   // respaldo viejo (carpeta con fecha)
        case preparing                               // contando archivos
        case copying
        case verifying
        case restoring                               // copiando al iPod
        case done(String)                            // mensaje final
        case failed(String)
    }

    var isPresented = false
    private(set) var mode: Mode = .backup
    private(set) var phase: Phase = .ready
    private(set) var progress = IPodBackupService.Progress()
    /// Cambia cada vez que se abre la ventana: la vista vuelve a revisar qué hay que copiar.
    private(set) var loadToken = 0

    /// Carpeta de respaldo de este iPod (nil = todavía no hay).
    private(set) var folder: URL?
    private(set) var preview: IPodBackupService.UpdatePreview?
    /// Día elegido para regresar el iPod, y qué pasaría.
    private(set) var selectedDay: IPodBackupService.Day?
    private(set) var dayPreview: IPodBackupService.DayPreview?
    private(set) var dayPreviewError: String?
    /// Carpeta del último respaldo (para "Mostrar en Finder").
    private(set) var lastBackupFolder: URL?

    @ObservationIgnored private var worker: Task<String, Error>?
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private weak var monitor: IPodMonitor?

    var isRunning: Bool {
        switch phase {
        case .preparing, .copying, .verifying, .restoring: return true
        default: return false
        }
    }

    var days: [IPodBackupService.Day] { preview?.days ?? [] }

    // MARK: - Último respaldo (se recuerda por iPod)

    private static let lastBackupKey = SettingsKey.lastIPodBackups

    func lastBackupDate(for deviceID: String) -> Date? {
        let all = UserDefaults.standard.dictionary(forKey: Self.lastBackupKey) as? [String: Date]
        return all?[deviceID]
    }

    private func rememberBackup(for deviceID: String) {
        var all = UserDefaults.standard.dictionary(forKey: Self.lastBackupKey) as? [String: Date] ?? [:]
        all[deviceID] = Date()
        UserDefaults.standard.set(all, forKey: Self.lastBackupKey)
    }

    // MARK: - Abrir y cerrar

    func showBackup() { open(.backup) }
    func showRestore() { open(.restore) }

    private func open(_ newMode: Mode) {
        guard !isRunning else { isPresented = true; return }
        mode = newMode
        folder = nil
        preview = nil
        selectedDay = nil
        dayPreview = nil
        phase = .loading
        loadToken += 1
        isPresented = true
    }

    func close() {
        guard !isRunning else { return }
        isPresented = false
    }

    /// Revisa la carpeta de respaldo de este iPod y qué falta copiar (fuera del hilo principal).
    func load(monitor: IPodMonitor) async {
        self.monitor = monitor
        guard case .loading = phase else { return }
        guard let volume = monitor.accessibleVolumeURL, let device = monitor.device else {
            phase = .ready          // la vista dice "Conecta el iPod y dale acceso"
            return
        }
        if folder == nil { folder = BackupLocation.folder(for: device.id) }
        guard let folder else {
            phase = .ready          // sin respaldo todavía
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try IPodBackupService.preview(volume: volume, backup: folder) }
        }.value
        guard case .loading = phase else { return }
        switch result {
        case .success(let value):
            preview = value
            if mode == .restore, let newest = value.days.first {
                select(newest)
                phase = .chooseDay
            } else {
                phase = .ready
            }
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
    }

    private func reload() {
        guard let monitor else { return }
        phase = .loading
        Task { await load(monitor: monitor) }
    }

    // MARK: - Respaldar / actualizar

    /// Botón principal: la primera vez pide dónde guardarlo; después solo copia lo nuevo.
    func backUp(monitor: IPodMonitor) {
        if folder == nil {
            chooseFolder(monitor: monitor) { [weak self] in self?.runUpdate(monitor: monitor) }
        } else {
            runUpdate(monitor: monitor)
        }
    }

    /// "Cambiar…": usar otra carpeta (si eliges un respaldo que ya existe, se sigue actualizando ese).
    func changeFolder(monitor: IPodMonitor) {
        chooseFolder(monitor: monitor) { [weak self] in self?.reload() }
    }

    private func chooseFolder(monitor: IPodMonitor, then next: @escaping () -> Void) {
        guard let device = monitor.device else { return }
        let name = Self.safeName(device.name)
        let panel = NSOpenPanel()
        panel.title = "¿Dónde guardar el respaldo?"
        panel.message = "Se crea la carpeta “\(name) – Respaldo”. Las siguientes veces solo se copia lo nuevo. También puedes elegir un respaldo que ya tengas."
        panel.prompt = "Guardar aquí"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let last = UserDefaults.standard.string(forKey: "lastBackupParent") {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        panel.begin { [weak self] response in
            guard response == .OK, let picked = panel.url, let self else { return }
            // ¿Elegiste un respaldo que ya existe? Se sigue usando ese. Si no, se crea uno adentro.
            let manifest = try? IPodBackupService.readManifest(in: picked)
            if manifest != nil, manifest?.days == nil {
                // Un respaldo de los de antes (una carpeta por fecha): solo tenemos permiso para esa
                // carpeta, no para la de afuera. Que elija la de afuera.
                self.phase = .failed("Esa es una carpeta de un respaldo de antes. Elige la carpeta donde quieres guardar el respaldo nuevo (por ejemplo, la que contiene a esa).")
                return
            }
            let isBackup = manifest?.days != nil
            let folder = isBackup ? picked : picked.appendingPathComponent("\(name) – Respaldo", isDirectory: true)
            UserDefaults.standard.set((isBackup ? picked.deletingLastPathComponent() : picked).path,
                                      forKey: "lastBackupParent")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try BackupLocation.save(folder, for: device.id)
                self.folder = folder
                next()
            } catch {
                self.phase = .failed("No se pudo usar esa carpeta: \(error.localizedDescription)")
            }
        }
    }

    private func runUpdate(monitor: IPodMonitor) {
        guard let volume = monitor.accessibleVolumeURL, let device = monitor.device, let folder else {
            phase = .failed("Conecta el iPod y dale acceso antes de respaldar.")
            return
        }
        let deviceID = device.id
        let deviceName = device.name
        let appVersion = Self.appVersion
        let isFirst = preview?.isFirst ?? true

        start { report in
            let result = try IPodBackupService.update(
                volume: volume, backup: folder, deviceName: deviceName, deviceID: deviceID,
                appVersion: appVersion,
                copying: { report(.copying) }, verifying: { report(.verifying) },
                progress: { report(.progress($0)) })
            let size = ByteCountFormatter.string(fromByteCount: result.copiedBytes, countStyle: .file)
            if isFirst {
                return "Respaldo listo: \(result.copiedSongs) canciones (\(size)) de “\(deviceName)”. La próxima vez solo se copia lo nuevo."
            }
            return result.copiedSongs == 0
                ? "El respaldo ya estaba al día. Se guardó la base del iPod de hoy."
                : "Respaldo actualizado: \(result.copiedSongs) canciones nuevas (\(size)). Se guardó la base del iPod de hoy."
        } onSuccess: { [weak self] in
            self?.lastBackupFolder = folder
            self?.rememberBackup(for: deviceID)
        }
    }

    // MARK: - Limpiar

    /// Quita del respaldo la música que ya no está en el iPod (pregunta antes).
    func cleanGoneSongs(monitor: IPodMonitor) {
        guard let preview, preview.goneSongs > 0, let folder,
              let volume = monitor.accessibleVolumeURL else { return }
        let size = ByteCountFormatter.string(fromByteCount: preview.goneBytes, countStyle: .file)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "¿Quitar del respaldo \(preview.goneSongs) canciones que ya no están en el iPod?"
        alert.informativeText = "Liberas \(size) en tu Mac. Ya no podrás recuperarlas desde el respaldo, ni regresando el iPod a un día anterior."
        let remove = alert.addButton(withTitle: "Quitar del respaldo")
        remove.hasDestructiveAction = true
        remove.keyEquivalent = ""
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        start { _ in
            let result = try IPodBackupService.removeGoneSongs(volume: volume, backup: folder)
            let freed = ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)
            return "Se quitaron \(result.count) canciones del respaldo (\(freed) liberados)."
        } onSuccess: {}
    }

    // MARK: - Regresar el iPod a un día

    func showDays() {
        guard let newest = days.first else { return }
        if selectedDay == nil { select(newest) }
        phase = .chooseDay
    }

    func backToSummary() {
        phase = .ready
    }

    func select(_ day: IPodBackupService.Day) {
        selectedDay = day
        dayPreview = nil
        dayPreviewError = nil
        guard let folder, let monitor else { return }
        do {
            dayPreview = try IPodBackupService.dayPreview(day, backup: folder, current: monitor.tracks)
        } catch {
            dayPreviewError = "No se pudo leer ese día del respaldo: \(error.localizedDescription)"
        }
    }

    func restoreSelectedDay(monitor: IPodMonitor) {
        guard let day = selectedDay, let folder,
              let volume = monitor.accessibleVolumeURL, let device = monitor.device else { return }
        let deviceID = device.id
        let deviceName = device.name
        let appVersion = Self.appVersion
        let when = day.date.formatted(date: .long, time: .shortened)

        start { report in
            // 1. Primero se guarda lo de hoy en el respaldo: así nada se pierde.
            _ = try IPodBackupService.update(
                volume: volume, backup: folder, deviceName: deviceName, deviceID: deviceID,
                appVersion: appVersion,
                copying: { report(.copying) }, verifying: { report(.verifying) },
                progress: { report(.progress($0)) })
            // 2. Regresar el iPod a ese día.
            report(.restoring)
            try IPodBackupService.restore(day: day, backup: folder, volume: volume) { report(.progress($0)) }
            return "“\(deviceName)” quedó como el \(when). Expulsa el iPod para que lo note."
        } onSuccess: { [weak self] in
            self?.lastBackupFolder = folder
            self?.rememberBackup(for: deviceID)
            monitor.reloadTracks()
        }
    }

    // MARK: - Respaldos viejos (una carpeta por fecha)

    func chooseBackupToRestore() {
        let panel = NSOpenPanel()
        panel.title = "Restaurar el iPod desde un respaldo"
        panel.message = "Elige la carpeta del respaldo."
        panel.prompt = "Elegir respaldo"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let last = UserDefaults.standard.string(forKey: "lastBackupParent") {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let manifest = try IPodBackupService.readManifest(in: url)
                if manifest.days?.isEmpty == false {
                    // Respaldo nuevo (con días): elegir el día.
                    self.folder = url
                    self.mode = .restore
                    self.selectedDay = nil
                    self.reload()
                } else {
                    self.phase = .confirmRestore(manifest, url)
                }
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func restore(from backup: URL, monitor: IPodMonitor) {
        guard let volume = monitor.accessibleVolumeURL, let device = monitor.device else {
            phase = .failed("Conecta el iPod y dale acceso antes de restaurar.")
            return
        }
        let deviceName = device.name
        start { report in
            let plan = try IPodBackupService.plan(root: backup)
            report(.restoring)
            try IPodBackupService.copy(plan, from: backup, to: volume, mode: .restore) { report(.progress($0)) }
            return "“\(deviceName)” quedó como en el respaldo. Expulsa el iPod para que lo note."
        } onSuccess: {
            monitor.reloadTracks()
        }
    }

    // MARK: - Cancelar

    func cancel() {
        cancelRequested = true
        worker?.cancel()
    }

    // MARK: - Motor común

    /// Lo que el trabajo en segundo plano le avisa a la ventana.
    nonisolated enum Event: Sendable {
        case copying
        case verifying
        case restoring
        case progress(IPodBackupService.Progress)
    }

    typealias Report = @Sendable (Event) -> Void

    /// Corre `job` fuera del hilo principal y va actualizando la ventana.
    private func start(_ job: @escaping @Sendable (Report) throws -> String,
                       onSuccess: @escaping () -> Void) {
        cancelRequested = false
        progress = IPodBackupService.Progress()
        phase = .preparing

        let (events, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(8))

        // Que la Mac no se duerma a media copia.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Copiando la música del iPod")

        let task = Task.detached(priority: .userInitiated) { () throws -> String in
            defer { continuation.finish() }
            return try job { continuation.yield($0) }
        }
        worker = task

        Task { [weak self] in
            for await event in events {
                guard let self else { break }
                switch event {
                case .copying:           self.phase = .copying
                case .verifying:         self.phase = .verifying
                case .restoring:         self.phase = .restoring; self.progress = IPodBackupService.Progress()
                case .progress(let p):   self.progress = p
                }
            }
            let result = await task.result
            ProcessInfo.processInfo.endActivity(activity)
            guard let self else { return }
            self.worker = nil

            switch result {
            case .success(let message):
                onSuccess()
                self.phase = .done(message)
            case .failure(let error):
                if self.cancelRequested || error is CancellationError {
                    self.phase = .failed(self.mode == .backup
                        ? "Respaldo cancelado. Lo que ya se copió se queda; la próxima vez sigue desde ahí."
                        : "Restauración cancelada. El iPod puede haber quedado a medias: vuelve a restaurar antes de expulsarlo.")
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Utilidades

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
