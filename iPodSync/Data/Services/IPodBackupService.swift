//
//  IPodBackupService.swift
//  iPodSync
//
//  Respaldo y restauración de la música del iPod.
//
//  Respaldo: copia TODA la carpeta iPod_Control (canciones, base de datos, portadas) tal cual a una
//  carpeta de la Mac, revisa que cada archivo llegó completo y al final escribe respaldo-ipodsync.json.
//  Un respaldo sin ese archivo está incompleto y no se ofrece para restaurar.
//
//  Restaurar: regresa la base de datos (iTunes/) y las portadas (Artwork/) del respaldo, y copia las
//  canciones que falten o hayan cambiado. No toca iPod_Control/Device (datos del aparato).
//
//  Se ejecuta fuera del hilo principal; se puede cancelar entre archivo y archivo.
//

import Foundation

nonisolated enum IPodBackupService {
    static let manifestName = "respaldo-ipodsync.json"

    struct FileEntry: Sendable {
        let path: String      // relativo a la raíz, p. ej. "iPod_Control/Music/F03/ABCD.mp3"
        let size: Int64
    }

    struct Plan: Sendable {
        let files: [FileEntry]
        let totalBytes: Int64
    }

    struct Progress: Sendable {
        var copiedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var filesDone = 0
        var filesTotal = 0
        var currentFile = ""

        var fraction: Double { totalBytes > 0 ? Double(copiedBytes) / Double(totalBytes) : 0 }
    }

    struct Manifest: Codable, Sendable {
        var deviceName: String
        var modelName: String?
        var date: Date
        var trackCount: Int
        var fileCount: Int
        var totalBytes: Int64
        var appVersion: String
    }

    enum Mode: Sendable { case backup, restore }

    enum BackupError: LocalizedError {
        case missingControlFolder
        case notEnoughSpace(needed: Int64, available: Int64)
        case notABackup
        case incomplete(Int)

        var errorDescription: String? {
            switch self {
            case .missingControlFolder:
                return "No se encontró la carpeta iPod_Control. ¿El iPod sigue conectado?"
            case .notEnoughSpace(let needed, let available):
                let f = ByteCountFormatter()
                return "No hay espacio suficiente: se necesitan \(f.string(fromByteCount: needed)) y hay \(f.string(fromByteCount: available)) libres."
            case .notABackup:
                return "Esa carpeta no es un respaldo completo de iPodSync (falta \(IPodBackupService.manifestName))."
            case .incomplete(let count):
                return "\(count) archivos no se copiaron completos. El respaldo no es confiable; vuelve a intentarlo."
            }
        }
    }

    // MARK: - Plan

    /// Lista de archivos dentro de root/iPod_Control y su tamaño total.
    static func plan(root: URL) throws -> Plan {
        let control = root.appendingPathComponent("iPod_Control", isDirectory: true)
        guard FileManager.default.fileExists(atPath: control.path) else { throw BackupError.missingControlFolder }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: control,
                                                              includingPropertiesForKeys: keys,
                                                              options: [],
                                                              errorHandler: { _, _ in true }) else {
            throw BackupError.missingControlFolder
        }

        let rootDepth = root.standardizedFileURL.pathComponents.count
        var files: [FileEntry] = []
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let relative = url.standardizedFileURL.pathComponents.dropFirst(rootDepth).joined(separator: "/")
            guard relative.hasPrefix("iPod_Control/") else { continue }
            let size = Int64(values?.fileSize ?? 0)
            files.append(FileEntry(path: relative, size: size))
            total += size
        }
        return Plan(files: files, totalBytes: total)
    }

    static func checkSpace(for plan: Plan, at folder: URL) throws {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        let needed = plan.totalBytes + 200_000_000      // margen
        if available < needed { throw BackupError.notEnoughSpace(needed: needed, available: available) }
    }

    // MARK: - Copiar

    static func copy(_ plan: Plan, from source: URL, to destination: URL, mode: Mode,
                     progress: (Progress) -> Void) throws {
        let fm = FileManager.default
        var state = Progress(totalBytes: plan.totalBytes, filesTotal: plan.files.count)

        for entry in plan.files {
            try Task.checkCancellation()
            state.currentFile = (entry.path as NSString).lastPathComponent
            progress(state)

            let from = source.appendingPathComponent(entry.path)
            let to = destination.appendingPathComponent(entry.path)

            if mode == .restore, shouldSkipOnRestore(entry, existing: to) {
                // Ya está igual en el iPod.
            } else {
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: to.path) {
                    // Reemplazo seguro: copiar a un temporal y luego cambiarlo por el original.
                    let temp = to.deletingLastPathComponent()
                        .appendingPathComponent(".\(to.lastPathComponent).ipodsync-tmp")
                    try? fm.removeItem(at: temp)
                    try fm.copyItem(at: from, to: temp)
                    try fm.removeItem(at: to)
                    try fm.moveItem(at: temp, to: to)
                } else {
                    try fm.copyItem(at: from, to: to)
                }
            }

            state.copiedBytes += entry.size
            state.filesDone += 1
        }
        state.currentFile = ""
        progress(state)
    }

    /// Al restaurar: la información del aparato nunca se toca; las canciones iguales no se vuelven a copiar.
    private static func shouldSkipOnRestore(_ entry: FileEntry, existing: URL) -> Bool {
        if entry.path.hasPrefix("iPod_Control/Device/") { return true }
        guard entry.path.hasPrefix("iPod_Control/Music/") else { return false }
        let size = (try? existing.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size.map(Int64.init) == entry.size
    }

    // MARK: - Revisar

    /// Cuántos archivos no llegaron o llegaron con otro tamaño.
    static func verify(_ plan: Plan, at destination: URL) -> Int {
        plan.files.reduce(0) { bad, entry in
            let url = destination.appendingPathComponent(entry.path)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            return size.map(Int64.init) == entry.size ? bad : bad + 1
        }
    }

    // MARK: - Manifiesto

    static func writeManifest(_ manifest: Manifest, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(manifestName), options: .atomic)
    }

    static func readManifest(in folder: URL) throws -> Manifest {
        let url = folder.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: url) else { throw BackupError.notABackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: data)
    }
}
