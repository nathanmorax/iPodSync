//
//  BackupViewModel.swift
//  iPodSync
//
//  Estado del respaldo / restauración del iPod para la hoja BackupSheet.
//

import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class BackupViewModel {
    enum Mode { case backup, restore }

    enum Phase {
        case ready                                   // explicación y botón para elegir carpeta
        case confirmRestore(IPodBackupService.Manifest, URL)
        case preparing                               // contando archivos
        case copying
        case verifying
        case done(String)                            // mensaje final
        case failed(String)
    }

    var isPresented = false
    private(set) var mode: Mode = .backup
    private(set) var phase: Phase = .ready
    private(set) var progress = IPodBackupService.Progress()
    /// Carpeta del último respaldo hecho en esta sesión (para "Mostrar en Finder").
    private(set) var lastBackupFolder: URL?

    @ObservationIgnored private var worker: Task<String, Error>?
    @ObservationIgnored private var cancelRequested = false

    var isRunning: Bool {
        switch phase {
        case .preparing, .copying, .verifying: return true
        default: return false
        }
    }

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

    // MARK: - Abrir la hoja

    func showBackup() {
        guard !isRunning else { isPresented = true; return }
        mode = .backup
        phase = .ready
        isPresented = true
    }

    func showRestore() {
        guard !isRunning else { isPresented = true; return }
        mode = .restore
        phase = .ready
        isPresented = true
    }

    func close() {
        guard !isRunning else { return }
        isPresented = false
    }

    // MARK: - Respaldar

    func chooseFolderAndBackup(monitor: IPodMonitor) {
        let panel = NSOpenPanel()
        panel.title = "Respaldar la música del iPod"
        panel.message = "Elige dónde guardar el respaldo. Se creará una carpeta nueva con la fecha."
        panel.prompt = "Respaldar aquí"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let last = UserDefaults.standard.string(forKey: "lastBackupParent") {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: "lastBackupParent")
            self?.runBackup(into: url, monitor: monitor)
        }
    }

    private func runBackup(into parent: URL, monitor: IPodMonitor) {
        guard let volume = monitor.accessibleVolumeURL, let device = monitor.device else {
            phase = .failed("Conecta el iPod y dale acceso antes de respaldar.")
            return
        }
        let deviceID = device.id
        let deviceName = device.name
        let trackCount = monitor.tracks.count
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let folder = parent.appendingPathComponent("\(Self.safeName(deviceName)) – Respaldo \(Self.stamp())",
                                                   isDirectory: true)

        start { report in
            let plan = try IPodBackupService.plan(root: volume)
            try IPodBackupService.checkSpace(for: plan, at: parent)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                report(.copying)
                try IPodBackupService.copy(plan, from: volume, to: folder, mode: .backup) { report(.progress($0)) }
                report(.verifying)
                let bad = IPodBackupService.verify(plan, at: folder)
                guard bad == 0 else { throw IPodBackupService.BackupError.incomplete(bad) }
                try IPodBackupService.writeManifest(.init(deviceName: deviceName,
                                                          modelName: nil,
                                                          date: Date(),
                                                          trackCount: trackCount,
                                                          fileCount: plan.files.count,
                                                          totalBytes: plan.totalBytes,
                                                          appVersion: appVersion),
                                                    to: folder)
            } catch {
                // Un respaldo a medias no sirve: se borra para no confundirlo con uno bueno.
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            let size = ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)
            return "Respaldo listo: \(plan.files.count) archivos (\(size)) de “\(deviceName)”."
        } onSuccess: { [weak self] in
            self?.lastBackupFolder = folder
            self?.rememberBackup(for: deviceID)
        }
    }

    // MARK: - Restaurar

    func chooseBackupToRestore() {
        let panel = NSOpenPanel()
        panel.title = "Restaurar el iPod desde un respaldo"
        panel.message = "Elige la carpeta del respaldo (la que dice “Respaldo” y la fecha)."
        panel.prompt = "Elegir respaldo"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let last = UserDefaults.standard.string(forKey: "lastBackupParent") {
            panel.directoryURL = URL(fileURLWithPath: last, isDirectory: true)
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let manifest = try IPodBackupService.readManifest(in: url)
                self?.phase = .confirmRestore(manifest, url)
            } catch {
                self?.phase = .failed(error.localizedDescription)
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
            report(.copying)
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

    /// Lo que el trabajo en segundo plano le avisa a la hoja.
    nonisolated enum Event: Sendable {
        case copying
        case verifying
        case progress(IPodBackupService.Progress)
    }

    typealias Report = @Sendable (Event) -> Void

    /// Corre `job` fuera del hilo principal y va actualizando la hoja.
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
                        ? "Respaldo cancelado. No se guardó nada a medias."
                        : "Restauración cancelada. El iPod puede haber quedado a medias: vuelve a restaurar antes de expulsarlo.")
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Utilidades

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f.string(from: Date())
    }

    private static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
