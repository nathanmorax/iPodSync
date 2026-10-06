//
//  IPodTrackWriter.swift
//  iPodSync
//
//  Agrega UNA canción al iPod de verdad (iPod de 5.ª generación):
//   1. Copia el archivo a iPod_Control/Music/Fxx/XXXX.mp3 (nombre corto, como iTunes).
//   2. Agrega la canción al final de la base de datos (iTunesDB): un mhit en la lista de canciones
//      y un mhip en la lista maestra. Agregar al final no mueve el orden de las demás canciones
//      (el iPod guarda reproducciones por posición).
//   3. Guarda la base anterior como iTunesDB.ipodsync-anterior, escribe la nueva y la vuelve a leer.
//      Si la canción no aparece, regresa la base anterior y borra el archivo copiado.
//
//  Los iPod classic (6.ª gen en adelante) exigen una firma en la base; esos se rechazan antes.
//

import Foundation

nonisolated enum IPodTrackWriter {
    struct NewTrack: Sendable {
        var title: String
        var artist: String
        var album: String?
        var genre: String?
        var trackNumber: Int?
        var year: Int?
        var durationMs: Int
        var sizeBytes: Int64
        var fileExtension: String
    }

    enum WriteError: LocalizedError {
        case noDatabase
        case unsupportedDatabase(String)
        case sourceMissing(String)
        case verifyFailed

        var errorDescription: String? {
            switch self {
            case .noDatabase:
                return "El iPod no tiene base de datos (iTunesDB). Restaura el iPod o sincronízalo una vez con el Finder."
            case .unsupportedDatabase(let detail):
                return "La base de datos del iPod tiene un formato que no reconocemos (\(detail)). No se cambió nada."
            case .sourceMissing(let name):
                return "No se encontró el archivo “\(name)” en tu Mac."
            case .verifyFailed:
                return "Después de escribir, la canción no apareció en la base del iPod. Se regresó la base anterior; tu música está como antes."
            }
        }
    }

    struct AddedTrack: Sendable {
        /// Ruta en el iPod, p. ej. ":iPod_Control:Music:F03:ABCD.mp3".
        let location: String
        /// ID de 64 bits de la canción (une la canción con su portada).
        let dbid: UInt64
    }

    /// Copia el archivo y agrega la canción a la base del iPod.
    @discardableResult
    static func add(source: URL, track: NewTrack, volume: URL, progress: (Double) -> Void) throws -> AddedTrack {
        let fm = FileManager.default
        let control = volume.appendingPathComponent("iPod_Control")
        let dbURL = control.appendingPathComponent("iTunes/iTunesDB")
        guard fm.fileExists(atPath: dbURL.path) else { throw WriteError.noDatabase }
        guard fm.fileExists(atPath: source.path) else { throw WriteError.sourceMissing(source.lastPathComponent) }

        // Revisar la base ANTES de copiar nada.
        let original = try Data(contentsOf: dbURL)
        _ = try inserting(track: track, location: ":iPod_Control:Music:F00:TEST.mp3", dbid: 1, into: original)

        let dbid = UInt64.random(in: 1...UInt64.max)

        // 1. Copiar el archivo.
        let (fileURL, location) = try destination(in: control, ext: track.fileExtension)
        do {
            try copy(from: source, to: fileURL, total: track.sizeBytes) { progress($0 * 0.9) }
        } catch {
            try? fm.removeItem(at: fileURL)
            throw error
        }

        // 2. Escribir la base nueva (guardando la anterior).
        let previous = control.appendingPathComponent("iTunes/iTunesDB.ipodsync-anterior")
        let temp = control.appendingPathComponent("iTunes/iTunesDB.ipodsync-nuevo")
        do {
            let updated = try inserting(track: track, location: location, dbid: dbid, into: original)
            try? fm.removeItem(at: previous)
            try original.write(to: previous)
            try updated.write(to: temp)
            try fm.removeItem(at: dbURL)
            try fm.moveItem(at: temp, to: dbURL)
        } catch {
            try? fm.removeItem(at: temp)
            if !fm.fileExists(atPath: dbURL.path) { try? original.write(to: dbURL) }
            try? fm.removeItem(at: fileURL)
            throw error
        }
        progress(0.95)

        // 3. Volver a leer y confirmar.
        let tracks = (try? ITunesDBReader.readTracks(volume: volume)) ?? []
        guard tracks.contains(where: { $0.location == location }) else {
            try? fm.removeItem(at: dbURL)
            try? original.write(to: dbURL)
            try? fm.removeItem(at: fileURL)
            throw WriteError.verifyFailed
        }
        progress(1)
        return AddedTrack(location: location, dbid: dbid)
    }

    // MARK: - Archivo

    /// Carpeta Fxx al azar (como iTunes) y nombre de 4 letras que no exista.
    private static func destination(in control: URL, ext: String) throws -> (URL, String) {
        let fm = FileManager.default
        let music = control.appendingPathComponent("Music")
        let folders = ((try? fm.contentsOfDirectory(atPath: music.path)) ?? [])
            .filter { $0.count == 3 && $0.hasPrefix("F") && Int($0.dropFirst()) != nil }
            .sorted()
        let folder = folders.randomElement() ?? "F00"
        try fm.createDirectory(at: music.appendingPathComponent(folder), withIntermediateDirectories: true)

        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for _ in 0..<200 {
            let name = String((0..<4).map { _ in letters.randomElement()! }) + "." + ext.lowercased()
            let url = music.appendingPathComponent(folder).appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) {
                return (url, ":iPod_Control:Music:\(folder):\(name)")
            }
        }
        throw WriteError.unsupportedDatabase("sin nombres libres en \(folder)")
    }

    private static func copy(from source: URL, to destination: URL, total: Int64, progress: (Double) -> Void) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        // Sin caché: si no, macOS "copia" los primeros MB a memoria al instante (la barra saltaba
        // a ~75 %) y luego se queda esperando a que de verdad se escriban en el iPod.
        _ = fcntl(output.fileDescriptor, F_NOCACHE, 1)

        var copied: Int64 = 0
        // Pedazos de 256 KB: en una canción de 4 MB son 16 avances y no 4.
        while let chunk = try input.read(upToCount: 1 << 18), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            progress(total > 0 ? min(1, Double(copied) / Double(total)) : 0)
        }
        try output.synchronize()
    }

    // MARK: - Base de datos

    /// Devuelve la base con la canción agregada (o lanza un error sin tocar nada).
    static func inserting(track: NewTrack, location: String, dbid: UInt64, into data: Data) throws -> Data {
        let db = [UInt8](data)
        guard tag(db, 0) == "mhbd" else { throw WriteError.unsupportedDatabase("sin mhbd") }
        let headerLength = Int(u32(db, 4))

        // Recorrer secciones: id más alto y tamaño de encabezado de las canciones existentes.
        var sections: [(offset: Int, length: Int, type: UInt32)] = []
        var offset = headerLength
        while offset + 16 <= db.count, tag(db, offset) == "mhsd" {
            let length = Int(u32(db, offset + 8))
            guard length > 0, offset + length <= db.count else { throw WriteError.unsupportedDatabase("mhsd dañado") }
            sections.append((offset, length, u32(db, offset + 12)))
            offset += length
        }
        guard let trackSection = sections.first(where: { $0.type == 1 }) else {
            throw WriteError.unsupportedDatabase("sin lista de canciones")
        }
        guard sections.contains(where: { $0.type == 2 }) else {
            throw WriteError.unsupportedDatabase("sin listas")
        }

        let (maxID, mhitHeader) = scanTracks(db, section: trackSection.offset)
        let newID = maxID + 1
        let now = macTime()

        let mhit = makeTrack(id: newID, dbid: dbid, headerLength: mhitHeader,
                             track: track, location: location, now: now)
        let mhip = makePlaylistItem(trackID: newID, now: now)

        var output = Array(db[0..<headerLength])
        for section in sections {
            var bytes = Array(db[section.offset..<(section.offset + section.length)])
            switch section.type {
            case 1:
                bytes = try appendTrack(mhit, to: bytes)
            case 2:
                bytes = try appendToMaster(mhip, in: bytes)
            case 3:
                bytes = (try? appendToMaster(mhip, in: bytes)) ?? bytes
            default:
                break
            }
            output += bytes
        }
        if offset < db.count { output += db[offset...] }
        put32(&output, 8, UInt32(output.count))
        return Data(output)
    }

    private static func scanTracks(_ db: [UInt8], section: Int) -> (maxID: UInt32, headerLength: Int) {
        let list = section + Int(u32(db, section + 4))
        let count = Int(u32(db, list + 8))
        var offset = list + Int(u32(db, list + 4))
        var maxID: UInt32 = 0
        var header = 0
        for _ in 0..<count {
            guard tag(db, offset) == "mhit" else { break }
            maxID = max(maxID, u32(db, offset + 0x10))
            if header == 0 { header = Int(u32(db, offset + 4)) }
            let total = Int(u32(db, offset + 8))
            guard total > 0 else { break }
            offset += total
        }
        // Si el iPod está vacío, usamos el tamaño de encabezado de la época del iPod de 5.ª generación.
        return (maxID, header >= 0x9C ? header : 0x184)
    }

    private static func appendTrack(_ mhit: [UInt8], to section: [UInt8]) throws -> [UInt8] {
        var bytes = section
        let list = Int(u32(bytes, 4))
        guard tag(bytes, list) == "mhlt" else { throw WriteError.unsupportedDatabase("sin mhlt") }
        put32(&bytes, list + 8, u32(bytes, list + 8) + 1)
        bytes += mhit
        put32(&bytes, 8, UInt32(bytes.count))
        return bytes
    }

    private static func appendToMaster(_ mhip: [UInt8], in section: [UInt8]) throws -> [UInt8] {
        var bytes = section
        let list = Int(u32(bytes, 4))
        guard tag(bytes, list) == "mhlp" else { throw WriteError.unsupportedDatabase("sin mhlp") }
        let playlists = Int(u32(bytes, list + 8))

        // La lista maestra tiene la marca 1 en el byte 20; normalmente es la primera.
        var offset = list + Int(u32(bytes, list + 4))
        var master: Int?
        for _ in 0..<playlists {
            guard tag(bytes, offset) == "mhyp" else { break }
            if bytes[offset + 20] == 1 { master = offset; break }
            let total = Int(u32(bytes, offset + 8))
            guard total > 0 else { break }
            offset += total
        }
        guard let start = master else { throw WriteError.unsupportedDatabase("sin lista maestra") }

        let total = Int(u32(bytes, start + 8))
        let items = u32(bytes, start + 16)
        var item = mhip
        put32(&item, 76 + 24, items)                 // posición dentro de la lista
        bytes.insert(contentsOf: item, at: start + total)
        put32(&bytes, start + 8, UInt32(total + item.count))
        put32(&bytes, start + 16, items + 1)
        put32(&bytes, 8, UInt32(bytes.count))
        return bytes
    }

    // MARK: - Registros nuevos

    private static func makeTrack(id: UInt32, dbid: UInt64, headerLength: Int,
                                  track: NewTrack, location: String, now: UInt32) -> [UInt8] {
        let ext = track.fileExtension.lowercased()
        let isMP3 = ext == "mp3"
        let fileType: (marker: UInt32, description: String) = switch ext {
        case "mp3":         (0x4D50_3320, "MPEG audio file")       // "MP3 "
        case "wav":         (0x5741_5620, "WAV audio file")        // "WAV "
        case "aif", "aiff": (0x4149_4646, "AIFF audio file")       // "AIFF"
        default:            (0x4D34_4120, "AAC audio file")        // "M4A "
        }

        var mhods: [UInt8] = []
        var count: UInt32 = 0
        func add(_ type: UInt32, _ text: String?) {
            guard let text, !text.isEmpty else { return }
            mhods += stringMhod(type: type, text)
            count += 1
        }
        add(1, track.title)
        add(2, location)
        add(3, track.album)
        add(4, track.artist)
        add(5, track.genre)
        add(6, fileType.description)

        let seconds = max(1, Double(track.durationMs) / 1000)
        let bitrate = UInt32(max(32, min(1411, Double(track.sizeBytes) * 8 / seconds / 1000)))
        let sampleRate: UInt32 = 44_100

        var h = [UInt8](repeating: 0, count: headerLength)
        putTag(&h, 0, "mhit")
        put32(&h, 0x04, UInt32(headerLength))
        put32(&h, 0x08, UInt32(headerLength + mhods.count))
        put32(&h, 0x0C, count)
        put32(&h, 0x10, id)
        put32(&h, 0x14, 1)                                   // visible
        put32(&h, 0x18, fileType.marker)
        h[0x1D] = isMP3 ? 1 : 0
        put32(&h, 0x20, now)                                 // modificado
        put32(&h, 0x24, UInt32(clamping: track.sizeBytes))
        put32(&h, 0x28, UInt32(clamping: track.durationMs))
        put32(&h, 0x2C, UInt32(clamping: track.trackNumber ?? 0))
        put32(&h, 0x34, UInt32(clamping: track.year ?? 0))
        put32(&h, 0x38, bitrate)
        put16(&h, 0x3E, UInt16(sampleRate))
        put32(&h, 0x68, now)                                 // agregado
        put64(&h, 0x70, dbid)
        put16(&h, 0x7E, 0xFFFF)
        if headerLength >= 0x8C { put32(&h, 0x88, Float(sampleRate).bitPattern) }
        if headerLength >= 0x92 { put16(&h, 0x90, isMP3 ? 0x000C : 0x0033) }
        if headerLength >= 0xA5 { h[0xA4] = 0x02 }           // sin portada
        if headerLength >= 0xB0 { put64(&h, 0xA8, dbid) }
        if headerLength >= 0xD4 { put32(&h, 0xD0, 1) }       // tipo: audio
        return h + mhods
    }

    private static func stringMhod(type: UInt32, _ text: String) -> [UInt8] {
        var utf16: [UInt8] = []
        for unit in text.utf16 { utf16 += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
        var m = [UInt8](repeating: 0, count: 40)
        putTag(&m, 0, "mhod")
        put32(&m, 4, 24)
        put32(&m, 8, UInt32(40 + utf16.count))
        put32(&m, 12, type)
        put32(&m, 24, 1)                                     // UTF‑16
        put32(&m, 28, UInt32(utf16.count))
        return m + utf16
    }

    private static func makePlaylistItem(trackID: UInt32, now: UInt32) -> [UInt8] {
        var item = [UInt8](repeating: 0, count: 76)
        putTag(&item, 0, "mhip")
        put32(&item, 4, 76)
        put32(&item, 8, 76 + 44)
        put32(&item, 12, 1)
        put32(&item, 20, trackID)                            // id del elemento
        put32(&item, 24, trackID)                            // canción
        put32(&item, 28, now)
        var position = [UInt8](repeating: 0, count: 44)
        putTag(&position, 0, "mhod")
        put32(&position, 4, 24)
        put32(&position, 8, 44)
        put32(&position, 12, 100)
        return item + position
    }

    /// Segundos desde 1904 (así cuenta el iPod).
    private static func macTime() -> UInt32 {
        UInt32(clamping: Int(Date().timeIntervalSince1970) + 2_082_844_800)
    }

    // MARK: - Bytes

    private static func tag(_ b: [UInt8], _ o: Int) -> String? {
        guard o >= 0, o + 4 <= b.count else { return nil }
        return String(bytes: b[o..<(o + 4)], encoding: .ascii)
    }
    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    private static func putTag(_ b: inout [UInt8], _ o: Int, _ s: String) {
        for (i, c) in s.utf8.prefix(4).enumerated() { b[o + i] = c }
    }
    private static func put16(_ b: inout [UInt8], _ o: Int, _ v: UInt16) {
        guard o + 2 <= b.count else { return }
        b[o] = UInt8(v & 0xFF); b[o + 1] = UInt8(v >> 8)
    }
    private static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        guard o + 4 <= b.count else { return }
        for i in 0..<4 { b[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xFF) }
    }
    private static func put64(_ b: inout [UInt8], _ o: Int, _ v: UInt64) {
        guard o + 8 <= b.count else { return }
        for i in 0..<8 { b[o + i] = UInt8((v >> (8 * UInt64(i))) & 0xFF) }
    }
}

// MARK: - Eliminar canciones

nonisolated extension IPodTrackWriter {
    struct RemovedTracks: Sendable {
        let count: Int
        /// Bytes de los archivos que se borraron del iPod.
        let freedBytes: Int64
        /// Archivos que no se pudieron borrar (la canción ya no está en la base; solo ocupan espacio).
        let leftoverFiles: Int
    }

    enum RemoveError: LocalizedError {
        case notFound

        var errorDescription: String? {
            "Esas canciones ya no están en el iPod. Vuelve a leer la música del iPod."
        }
    }

    /// Quita canciones del iPod:
    ///  1. Las quita de la base (lista de canciones y todas las listas), guardando la base anterior.
    ///  2. Vuelve a leer la base y confirma: si algo no cuadra, regresa la anterior y no borra nada.
    ///  3. Ajusta los archivos del iPod que cuentan canciones por posición (Play Counts, On‑The‑Go).
    ///  4. Borra los archivos de música, uno por uno (`progress(posición, título)`).
    static func remove(trackIDs: Set<UInt32>, volume: URL,
                       progress: (_ position: Int, _ title: String) -> Void) throws -> RemovedTracks {
        let fm = FileManager.default
        let control = volume.appendingPathComponent("iPod_Control")
        let dbURL = control.appendingPathComponent("iTunes/iTunesDB")
        guard fm.fileExists(atPath: dbURL.path) else { throw WriteError.noDatabase }

        // Lista en el orden de la base: la posición importa para Play Counts y On‑The‑Go.
        let before = try ITunesDBReader.readTracks(volume: volume)
        let removedIndices = Set(before.indices.filter { trackIDs.contains(before[$0].id) })
        let targets = removedIndices.sorted().map { before[$0] }
        guard !targets.isEmpty else { throw RemoveError.notFound }

        // 1. Base nueva sin esas canciones.
        let original = try Data(contentsOf: dbURL)
        let updated = try removing(trackIDs: trackIDs, from: original)
        let previous = control.appendingPathComponent("iTunes/iTunesDB.ipodsync-anterior")
        let temp = control.appendingPathComponent("iTunes/iTunesDB.ipodsync-nuevo")
        do {
            try? fm.removeItem(at: previous)
            try original.write(to: previous)
            try updated.write(to: temp)
            try fm.removeItem(at: dbURL)
            try fm.moveItem(at: temp, to: dbURL)
        } catch {
            try? fm.removeItem(at: temp)
            if !fm.fileExists(atPath: dbURL.path) { try? original.write(to: dbURL) }
            throw error
        }

        // 2. Confirmar: ninguna de las quitadas sigue ahí y las demás están todas.
        let after = (try? ITunesDBReader.readTracks(volume: volume)) ?? []
        let afterIDs = Set(after.map(\.id))
        guard after.count == before.count - targets.count, afterIDs.isDisjoint(with: trackIDs) else {
            try? fm.removeItem(at: dbURL)
            try? original.write(to: dbURL)
            throw WriteError.verifyFailed
        }

        // 3. Archivos que guardan datos por posición de canción (si no se ajustan, las
        //    reproducciones o la lista On‑The‑Go quedarían en canciones equivocadas).
        let iTunes = control.appendingPathComponent("iTunes")
        fixPositions(in: iTunes.appendingPathComponent("Play Counts"), magic: "mhdp",
                     trackCount: before.count, removed: removedIndices, entriesAreIndices: false)
        let otg = ((try? fm.contentsOfDirectory(atPath: iTunes.path)) ?? []).filter { $0.hasPrefix("OTGPlaylistInfo") }
        for name in otg {
            fixPositions(in: iTunes.appendingPathComponent(name), magic: "mhpo",
                         trackCount: before.count, removed: removedIndices, entriesAreIndices: true)
        }

        // 4. Borrar la música. Si un archivo no se puede borrar, la canción ya no está en el iPod
        //    (solo queda ocupando espacio); no vale la pena deshacer todo por eso.
        var freed: Int64 = 0
        var leftovers = 0
        for (index, track) in targets.enumerated() {
            progress(index + 1, track.title)
            guard let file = fileURL(for: track.location, volume: volume) else { continue }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? track.sizeBytes
            do {
                try fm.removeItem(at: file)
                freed += size
            } catch {
                if fm.fileExists(atPath: file.path) { leftovers += 1 }
            }
        }
        return RemovedTracks(count: targets.count, freedBytes: freed, leftoverFiles: leftovers)
    }

    /// ":iPod_Control:Music:F03:ABCD.mp3" → archivo en el disco del iPod.
    /// Solo dentro de iPod_Control/Music (nunca se borra otra cosa).
    static func fileURL(for location: String, volume: URL) -> URL? {
        let parts = location.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "iPod_Control", parts[1] == "Music",
              !parts.contains(".."), !parts.contains(".") else { return nil }
        return parts.reduce(volume) { $0.appendingPathComponent($1) }
    }

    /// Devuelve la base sin esas canciones (o lanza un error sin tocar nada).
    static func removing(trackIDs: Set<UInt32>, from data: Data) throws -> Data {
        let db = [UInt8](data)
        guard tag(db, 0) == "mhbd" else { throw WriteError.unsupportedDatabase("sin mhbd") }
        let headerLength = Int(u32(db, 4))

        var output = Array(db[0..<headerLength])
        var offset = headerLength
        var sawTracks = false
        while offset + 16 <= db.count, tag(db, offset) == "mhsd" {
            let length = Int(u32(db, offset + 8))
            guard length > 0, offset + length <= db.count else { throw WriteError.unsupportedDatabase("mhsd dañado") }
            var bytes = Array(db[offset..<(offset + length)])
            switch u32(db, offset + 12) {
            case 1:
                bytes = try removeTracks(trackIDs, from: bytes)
                sawTracks = true
            case 2, 3:
                // Todas las listas (la maestra, las tuyas y la de podcasts) pierden esas canciones.
                bytes = try removeItems(trackIDs, from: bytes)
            default:
                break
            }
            output += bytes
            offset += length
        }
        guard sawTracks else { throw WriteError.unsupportedDatabase("sin lista de canciones") }
        if offset < db.count { output += db[offset...] }
        put32(&output, 8, UInt32(output.count))
        return Data(output)
    }

    private static func removeTracks(_ ids: Set<UInt32>, from section: [UInt8]) throws -> [UInt8] {
        let list = Int(u32(section, 4))
        guard tag(section, list) == "mhlt" else { throw WriteError.unsupportedDatabase("sin mhlt") }
        let count = Int(u32(section, list + 8))
        var offset = list + Int(u32(section, list + 4))
        var kept = Array(section[0..<offset])
        var removed = 0
        for _ in 0..<count {
            guard tag(section, offset) == "mhit" else { throw WriteError.unsupportedDatabase("mhit dañado") }
            let total = Int(u32(section, offset + 8))
            guard total > 0, offset + total <= section.count else { throw WriteError.unsupportedDatabase("mhit dañado") }
            if ids.contains(u32(section, offset + 0x10)) {
                removed += 1
            } else {
                kept += section[offset..<(offset + total)]
            }
            offset += total
        }
        if offset < section.count { kept += section[offset...] }
        put32(&kept, list + 8, UInt32(count - removed))
        put32(&kept, 8, UInt32(kept.count))
        return kept
    }

    private static func removeItems(_ ids: Set<UInt32>, from section: [UInt8]) throws -> [UInt8] {
        let list = Int(u32(section, 4))
        guard tag(section, list) == "mhlp" else { throw WriteError.unsupportedDatabase("sin mhlp") }
        let playlists = Int(u32(section, list + 8))
        var offset = list + Int(u32(section, list + 4))
        var output = Array(section[0..<offset])
        for _ in 0..<playlists {
            guard tag(section, offset) == "mhyp" else { throw WriteError.unsupportedDatabase("mhyp dañado") }
            let total = Int(u32(section, offset + 8))
            guard total > 0, offset + total <= section.count else { throw WriteError.unsupportedDatabase("mhyp dañado") }
            output += try removeItems(ids, fromPlaylist: Array(section[offset..<(offset + total)]))
            offset += total
        }
        if offset < section.count { output += section[offset...] }
        put32(&output, 8, UInt32(output.count))
        return output
    }

    /// Una lista (mhyp): encabezado, sus mhod y luego un mhip por canción.
    private static func removeItems(_ ids: Set<UInt32>, fromPlaylist playlist: [UInt8]) throws -> [UInt8] {
        let header = Int(u32(playlist, 4))
        let objects = Int(u32(playlist, 12))
        let items = Int(u32(playlist, 16))
        var offset = header
        var output = Array(playlist[0..<header])
        for _ in 0..<objects {
            guard tag(playlist, offset) == "mhod" else { throw WriteError.unsupportedDatabase("mhod de lista dañado") }
            let length = Int(u32(playlist, offset + 8))
            guard length > 0, offset + length <= playlist.count else { throw WriteError.unsupportedDatabase("mhod de lista dañado") }
            output += playlist[offset..<(offset + length)]
            offset += length
        }
        var kept: UInt32 = 0
        for _ in 0..<items {
            guard tag(playlist, offset) == "mhip" else { throw WriteError.unsupportedDatabase("mhip dañado") }
            let length = Int(u32(playlist, offset + 8))
            guard length > 0, offset + length <= playlist.count else { throw WriteError.unsupportedDatabase("mhip dañado") }
            if !ids.contains(u32(playlist, offset + 24)) {
                output += playlist[offset..<(offset + length)]
                kept += 1
            }
            offset += length
        }
        if offset < playlist.count { output += playlist[offset...] }
        put32(&output, 8, UInt32(output.count))
        put32(&output, 16, kept)
        return output
    }

    /// Play Counts (una entrada por canción, en orden) y On‑The‑Go (lista de posiciones):
    /// quita lo de las canciones borradas y recorre las posiciones. Si el archivo no cuadra
    /// con la base, no se toca.
    private static func fixPositions(in url: URL, magic: String, trackCount: Int,
                                     removed: Set<Int>, entriesAreIndices: Bool) {
        guard let data = try? Data(contentsOf: url) else { return }
        var bytes = [UInt8](data)
        guard tag(bytes, 0) == magic else { return }
        let header = Int(u32(bytes, 4))
        let entryLength = Int(u32(bytes, 8))
        let count = Int(u32(bytes, 12))
        guard header >= 16, entryLength > 0, header + count * entryLength <= bytes.count else { return }

        var output = Array(bytes[0..<header])
        var kept = 0
        let sortedRemoved = removed.sorted()
        for index in 0..<count {
            let start = header + index * entryLength
            var entry = Array(bytes[start..<(start + entryLength)])
            if entriesAreIndices {
                let position = Int(u32(entry, 0))
                if removed.contains(position) { continue }
                let shift = sortedRemoved.prefix { $0 < position }.count
                put32(&entry, 0, UInt32(position - shift))
            } else {
                guard count == trackCount else { return }   // no cuadra: mejor no tocarlo
                if removed.contains(index) { continue }
            }
            output += entry
            kept += 1
        }
        put32(&output, 12, UInt32(kept))
        bytes = output
        try? Data(bytes).write(to: url, options: .atomic)
    }
}

