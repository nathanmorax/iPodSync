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
        var modified: Date? = nil

        var isMusic: Bool { path.hasPrefix("iPod_Control/Music/") }
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
        /// Respaldo que se actualiza (uno por iPod). nil en los respaldos viejos (una carpeta por fecha).
        var deviceID: String? = nil
        /// La base del iPod de cada vez que se respaldó (carpeta Días/).
        var days: [Day]? = nil
    }

    /// Un día guardado: copia de iPod_Control/iTunes y del ArtworkDB de ese momento (pesan poco).
    struct Day: Codable, Sendable, Hashable, Identifiable {
        var folder: String        // nombre dentro de Días/, p. ej. "2026-10-06 14.30.05"
        var date: Date
        var trackCount: Int
        var id: String { folder }
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

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
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
            files.append(FileEntry(path: relative, size: size, modified: values?.contentModificationDate))
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

    // MARK: - Respaldo que se actualiza (una carpeta por iPod)
    //
    //  <iPod> – Respaldo/
    //    iPod_Control/          la música como en el iPod. La música SOLO crece: al actualizar se
    //                           agregan las canciones nuevas y nunca se borra ni se sobrescribe una.
    //    Días/<fecha>/          la base del iPod (iTunes/ y ArtworkDB) de cada respaldo: pesa poco y
    //                           permite regresar el iPod a ese día.
    //    Reemplazadas/<fecha>/  si una canción nueva del iPod quedó con el nombre de archivo de una
    //                           vieja, la vieja se guarda aquí (no se pierde).
    //    respaldo-ipodsync.json

    static let daysFolder = "Días"
    static let replacedFolder = "Reemplazadas"

    /// Qué haría "Actualizar respaldo", sin copiar nada.
    struct UpdatePreview: Sendable {
        var isFirst: Bool
        var songsToCopy: Int
        var bytesToCopy: Int64
        var songsAlready: Int
        var songsOnIPod: Int
        var days: [Day]
        /// Lo que ocupa la música del respaldo.
        var backupBytes: Int64
        /// Canciones en el respaldo que ya no están en el iPod (las que borraste).
        var goneSongs: Int
        var goneBytes: Int64
    }

    struct UpdateResult: Sendable {
        var copiedSongs: Int
        var copiedBytes: Int64
        var day: Day
    }

    static func preview(volume: URL, backup: URL) throws -> UpdatePreview {
        let plan = try Self.plan(root: volume)
        let manifest = try? readManifest(in: backup)
        let pending = changes(plan, at: backup)
        let music = plan.files.filter(\.isMusic)
        let pendingMusic = pending.filter(\.isMusic)
        let gone = goneMusic(plan, at: backup)
        let backupMusic = musicFiles(at: backup)
        return UpdatePreview(
            isFirst: manifest == nil,
            songsToCopy: pendingMusic.count,
            bytesToCopy: pending.reduce(0) { $0 + $1.size },
            songsAlready: music.count - pendingMusic.count,
            songsOnIPod: music.count,
            days: (manifest?.days ?? []).sorted { $0.date > $1.date },
            backupBytes: backupMusic.reduce(0) { $0 + $1.size },
            goneSongs: gone.count,
            goneBytes: gone.reduce(0) { $0 + $1.size })
    }

    /// Copia solo lo nuevo o cambiado, revisa todo y guarda la base del iPod de hoy en Días/.
    /// Si falla a medias no se borra nada: lo ya copiado sirve para la siguiente vez.
    static func update(volume: URL, backup: URL, deviceName: String, deviceID: String, appVersion: String,
                       copying: () -> Void, verifying: () -> Void,
                       progress: (Progress) -> Void) throws -> UpdateResult {
        let fm = FileManager.default
        let plan = try Self.plan(root: volume)
        let manifest = try? readManifest(in: backup)
        let pending = changes(plan, at: backup)
        let pendingPlan = Plan(files: pending, totalBytes: pending.reduce(0) { $0 + $1.size })
        try checkSpace(for: pendingPlan, at: backup)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)

        let stamp = stamp(Date())
        // Una canción nueva con el nombre de archivo de una vieja: la vieja se guarda aparte.
        for entry in pending where entry.isMusic {
            let existing = backup.appendingPathComponent(entry.path)
            guard fm.fileExists(atPath: existing.path) else { continue }
            let aside = backup.appendingPathComponent(replacedFolder).appendingPathComponent(stamp)
                .appendingPathComponent(entry.path)
            try fm.createDirectory(at: aside.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: existing, to: aside)
        }

        copying()
        try copy(pendingPlan, from: volume, to: backup, mode: .backup, progress: progress)
        verifying()
        let bad = verify(plan, at: backup)
        guard bad == 0 else { throw BackupError.incomplete(bad) }

        // La base de hoy (iTunes/ completo y ArtworkDB) en Días/<fecha>.
        let control = backup.appendingPathComponent("iPod_Control")
        let dayURL = backup.appendingPathComponent(daysFolder).appendingPathComponent(stamp)
        try fm.createDirectory(at: dayURL, withIntermediateDirectories: true)
        try fm.copyItem(at: control.appendingPathComponent("iTunes"), to: dayURL.appendingPathComponent("iTunes"))
        let artworkDB = control.appendingPathComponent("Artwork/ArtworkDB")
        if fm.fileExists(atPath: artworkDB.path) {
            try fm.createDirectory(at: dayURL.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
            try fm.copyItem(at: artworkDB, to: dayURL.appendingPathComponent("Artwork/ArtworkDB"))
        }

        let trackCount = (try? ITunesDBReader.readTracks(
            databaseURL: dayURL.appendingPathComponent("iTunes/iTunesDB")).count) ?? 0
        let day = Day(folder: stamp, date: Date(), trackCount: trackCount)
        try writeManifest(Manifest(deviceName: deviceName, modelName: manifest?.modelName, date: day.date,
                                   trackCount: trackCount, fileCount: plan.files.count,
                                   totalBytes: plan.totalBytes, appVersion: appVersion,
                                   deviceID: deviceID, days: (manifest?.days ?? []) + [day]),
                          to: backup)
        let copiedMusic = pending.filter(\.isMusic)
        return UpdateResult(copiedSongs: copiedMusic.count,
                            copiedBytes: pendingPlan.totalBytes, day: day)
    }

    /// Lo que falta copiar: música nueva (o con otro tamaño) y los demás archivos que cambiaron.
    private static func changes(_ plan: Plan, at backup: URL) -> [FileEntry] {
        plan.files.filter { entry in
            let url = backup.appendingPathComponent(entry.path)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return true }
            if Int64(size) != entry.size { return true }
            if entry.isMusic { return false }
            // Base, portadas…: mismo tamaño pero modificadas después (FAT32 guarda de 2 en 2 segundos).
            guard let source = entry.modified, let copy = values.contentModificationDate else { return true }
            return abs(source.timeIntervalSince(copy)) > 2
        }
    }

    /// Música que hay en el respaldo.
    private static func musicFiles(at backup: URL) -> [FileEntry] {
        let music = backup.appendingPathComponent("iPod_Control/Music", isDirectory: true)
        guard FileManager.default.fileExists(atPath: music.path),
              let list = try? plan(root: backup) else { return [] }
        return list.files.filter(\.isMusic)
    }

    /// Canciones del respaldo que ya no están en el iPod.
    private static func goneMusic(_ plan: Plan, at backup: URL) -> [FileEntry] {
        let onIPod = Set(plan.files.filter(\.isMusic).map(\.path))
        return musicFiles(at: backup).filter { !onIPod.contains($0.path) }
    }

    /// "Limpiar…": borra del respaldo la música que ya no está en el iPod.
    static func removeGoneSongs(volume: URL, backup: URL) throws -> (count: Int, bytes: Int64) {
        let gone = goneMusic(try plan(root: volume), at: backup)
        var count = 0
        var bytes: Int64 = 0
        for entry in gone {
            try Task.checkCancellation()
            if (try? FileManager.default.removeItem(at: backup.appendingPathComponent(entry.path))) != nil {
                count += 1
                bytes += entry.size
            }
        }
        return (count, bytes)
    }

    // MARK: - Regresar el iPod a un día guardado

    struct DayPreview: Sendable {
        /// Canciones que vuelven al iPod (no están hoy).
        var comeBack: [String]
        /// Canciones que se quitan del iPod (se agregaron después).
        var goAway: [String]
        /// Canciones de ese día cuyo archivo no está en el respaldo (no se podrían regresar).
        var missing: Int
    }

    static func dayTracks(_ day: Day, backup: URL) throws -> [IPodTrack] {
        try ITunesDBReader.readTracks(databaseURL: dayURL(day, backup: backup).appendingPathComponent("iTunes/iTunesDB"))
    }

    static func dayPreview(_ day: Day, backup: URL, current: [IPodTrack]) throws -> DayPreview {
        let then = try dayTracks(day, backup: backup)
        let nowLocations = Set(current.map(\.location))
        let thenLocations = Set(then.map(\.location))
        let missing = then.filter { track in
            guard let path = relativePath(for: track.location) else { return true }
            return !FileManager.default.fileExists(atPath: backup.appendingPathComponent(path).path)
        }.count
        return DayPreview(
            comeBack: then.filter { !nowLocations.contains($0.location) }.map(\.title),
            goAway: current.filter { !thenLocations.contains($0.location) }.map(\.title),
            missing: missing)
    }

    /// Regresa el iPod a ese día. Antes de llamar esto se actualiza el respaldo (así lo de hoy
    /// también queda guardado y nada se pierde).
    ///  1. Copia al iPod las canciones de ese día que le falten.
    ///  2. Pone la base de ese día (iTunes/ y ArtworkDB) y las portadas que falten.
    ///  3. Revisa que el iPod lea esa base.
    ///  4. Quita del iPod los archivos que esa base ya no usa, solo si están guardados en el respaldo.
    static func restore(day: Day, backup: URL, volume: URL, progress: (Progress) -> Void) throws {
        let fm = FileManager.default
        let then = try dayTracks(day, backup: backup)
        let source = dayURL(day, backup: backup)

        // 1. Canciones (las iguales no se vuelven a copiar).
        let songs: [FileEntry] = then.compactMap { track in
            guard let path = relativePath(for: track.location) else { return nil }
            let url = backup.appendingPathComponent(path)
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
            return FileEntry(path: path, size: Int64(size))
        }
        try copy(Plan(files: songs, totalBytes: songs.reduce(0) { $0 + $1.size }),
                 from: backup, to: volume, mode: .restore, progress: progress)

        // 2. La base de ese día. Los archivos que cuentan canciones por posición (Play Counts,
        //    On‑The‑Go) que no existían ese día se quitan: ya no cuadrarían con la base.
        let iTunes = volume.appendingPathComponent("iPod_Control/iTunes")
        let savedNames = Set((try? fm.contentsOfDirectory(atPath: source.appendingPathComponent("iTunes").path)) ?? [])
        for name in savedNames where !name.contains(".ipodsync-") {
            try replace(iTunes.appendingPathComponent(name), with: source.appendingPathComponent("iTunes/\(name)"))
        }
        for name in (try? fm.contentsOfDirectory(atPath: iTunes.path)) ?? []
        where !savedNames.contains(name) && (name == "Play Counts" || name.hasPrefix("OTGPlaylistInfo")) {
            try? fm.removeItem(at: iTunes.appendingPathComponent(name))
        }
        let savedArtwork = source.appendingPathComponent("Artwork/ArtworkDB")
        if fm.fileExists(atPath: savedArtwork.path) {
            let artwork = volume.appendingPathComponent("iPod_Control/Artwork")
            try fm.createDirectory(at: artwork, withIntermediateDirectories: true)
            try replace(artwork.appendingPathComponent("ArtworkDB"), with: savedArtwork)
            // Las imágenes (.ithmb) solo crecen: se copian las del respaldo si en el iPod faltan o son más chicas.
            let backupArtwork = backup.appendingPathComponent("iPod_Control/Artwork")
            for name in (try? fm.contentsOfDirectory(atPath: backupArtwork.path)) ?? [] where name.hasSuffix(".ithmb") {
                let from = backupArtwork.appendingPathComponent(name)
                let to = artwork.appendingPathComponent(name)
                let fromSize = (try? from.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let toSize = (try? to.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
                if fromSize > toSize { try replace(to, with: from) }
            }
        }

        // 3. ¿El iPod lee la base?
        let restored = try ITunesDBReader.readTracks(volume: volume)
        guard restored.count == then.count else { throw BackupError.incomplete(abs(then.count - restored.count)) }

        // 4. Archivos de música que esa base ya no usa: solo se borran si el respaldo los tiene.
        let used = Set(restored.compactMap { relativePath(for: $0.location) })
        let onIPod = try plan(root: volume).files.filter(\.isMusic)
        for entry in onIPod where !used.contains(entry.path) {
            let saved = backup.appendingPathComponent(entry.path)
            let savedSize = (try? saved.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
            if savedSize == entry.size {
                try? fm.removeItem(at: volume.appendingPathComponent(entry.path))
            }
        }
    }

    static func dayURL(_ day: Day, backup: URL) -> URL {
        backup.appendingPathComponent(daysFolder).appendingPathComponent(day.folder)
    }

    /// ":iPod_Control:Music:F03:ABCD.mp3" → "iPod_Control/Music/F03/ABCD.mp3" (solo dentro de Music).
    static func relativePath(for location: String) -> String? {
        let parts = location.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "iPod_Control", parts[1] == "Music",
              !parts.contains(".."), !parts.contains(".") else { return nil }
        return parts.joined(separator: "/")
    }

    /// Reemplazo seguro: copia a un temporal junto al destino y luego lo cambia.
    private static func replace(_ destination: URL, with source: URL) throws {
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).ipodsync-tmp")
        try? fm.removeItem(at: temp)
        try fm.copyItem(at: source, to: temp)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temp, to: destination)
    }

    /// "2026-10-06 14.30.05": con segundos, para que dos respaldos seguidos no choquen.
    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: date)
    }
}

