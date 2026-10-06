//
//  ITunesDBReader.swift
//  iPodSync
//
//  Lee las canciones del iPod desde iPod_Control/iTunes/iTunesDB (solo lectura).
//
//  Formato (little‑endian), lo mínimo que necesitamos:
//    mhbd  base de datos  → varios mhsd (secciones)
//    mhsd  tipo 1 = canciones → mhlt (lista) → mhit (una por canción)
//    mhit  datos numéricos (tamaño, duración, reproducciones…) + mhod (textos)
//    mhod  tipo 1 título, 2 ruta, 3 álbum, 4 artista, 5 género
//

import Foundation

nonisolated enum ITunesDBReader {
    enum ReadError: LocalizedError {
        case notFound
        case unreadable(String)
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .notFound:          "El iPod no tiene base de datos de música (iTunesDB)."
            case .unreadable(let m): "No se pudo leer la base de datos del iPod: \(m)"
            case .invalidFormat:     "La base de datos del iPod tiene un formato que no reconocemos."
            }
        }
    }

    /// Lee todas las canciones. Se puede llamar fuera del hilo principal.
    static func readTracks(volume: URL) throws -> [IPodTrack] {
        try readTracks(databaseURL: volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB"))
    }

    /// Lee las canciones de un archivo iTunesDB suelto (p. ej. el de un día guardado en el respaldo).
    static func readTracks(databaseURL url: URL) throws -> [IPodTrack] {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ReadError.notFound }

        let db: Data
        do {
            // Lectura normal (sin mapear): mapear un disco que se puede desconectar truena la app.
            db = try Data(contentsOf: url)
        } catch {
            throw ReadError.unreadable(error.localizedDescription)
        }
        guard tag(db, 0) == "mhbd" else { throw ReadError.invalidFormat }

        var offset = Int(u32(db, 4))
        while offset + 16 <= db.count, tag(db, offset) == "mhsd" {
            let sectionLength = Int(u32(db, offset + 8))
            if u32(db, offset + 12) == 1 {
                return try tracks(in: db, section: offset)
            }
            guard sectionLength > 0 else { break }
            offset += sectionLength
        }
        throw ReadError.invalidFormat
    }

    private static func tracks(in db: Data, section: Int) throws -> [IPodTrack] {
        let list = section + Int(u32(db, section + 4))        // mhlt
        guard tag(db, list) == "mhlt" else { throw ReadError.invalidFormat }
        let count = Int(u32(db, list + 8))

        var result: [IPodTrack] = []
        result.reserveCapacity(count)
        var offset = list + Int(u32(db, list + 4))
        for _ in 0..<count {
            guard tag(db, offset) == "mhit" else { break }
            let headerLength = Int(u32(db, offset + 4))
            let totalLength = Int(u32(db, offset + 8))
            guard totalLength > 0 else { break }

            let strings = mhodStrings(db, from: offset + headerLength,
                                      count: Int(u32(db, offset + 12)),
                                      end: offset + totalLength)
            let location = strings[2] ?? ""
            let fallbackTitle = location.split(separator: ":").last.map(String.init) ?? "Sin título"

            result.append(IPodTrack(
                id: u32(db, offset + 16),
                title: strings[1] ?? fallbackTitle,
                artist: strings[4] ?? "Artista desconocido",
                album: strings[3] ?? "",
                genre: strings[5] ?? "",
                location: location,
                sizeBytes: Int64(u32(db, offset + 36)),
                durationMs: Int(u32(db, offset + 40)),
                trackNumber: Int(u32(db, offset + 44)),
                year: Int(u32(db, offset + 52)),
                playCount: Int(u32(db, offset + 80)),
                rating: Int(db.byte(at: offset + 31)) / 20
            ))
            // Enlace con la portada: dbid (0x70, 64 bits) y cuántas portadas tiene (0x7C) / su tamaño (0x80).
            result[result.count - 1].dbid = UInt64(u32(db, offset + 0x70)) | UInt64(u32(db, offset + 0x74)) << 32
            let artworkCount = Int(db.byte(at: offset + 0x7C)) | Int(db.byte(at: offset + 0x7D)) << 8
            result[result.count - 1].hasArtwork = artworkCount > 0 || u32(db, offset + 0x80) > 0
            offset += totalLength
        }
        return result
    }

    /// Textos de una canción por tipo de mhod.
    private static func mhodStrings(_ db: Data, from start: Int, count: Int, end: Int) -> [UInt32: String] {
        var strings: [UInt32: String] = [:]
        var offset = start
        for _ in 0..<count {
            guard offset + 24 <= min(end, db.count), tag(db, offset) == "mhod" else { break }
            let length = Int(u32(db, offset + 8))
            let type = u32(db, offset + 12)
            if (1...5).contains(type), offset + 40 <= db.count {
                let encoding = u32(db, offset + 24)          // 2 = UTF‑8; si no, UTF‑16
                let byteCount = Int(u32(db, offset + 28))
                let textStart = offset + 40
                if byteCount > 0, textStart + byteCount <= db.count {
                    let bytes = db.subdata(in: (db.startIndex + textStart)..<(db.startIndex + textStart + byteCount))
                    let text = String(data: bytes, encoding: encoding == 2 ? .utf8 : .utf16LittleEndian)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let text, !text.isEmpty { strings[type] = text }
                }
            }
            guard length > 0 else { break }
            offset += length
        }
        return strings
    }

    // MARK: - Utilidades

    private static func tag(_ data: Data, _ offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let start = data.startIndex + offset
        return String(data: data.subdata(in: start..<(start + 4)), encoding: .ascii)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(data.byte(at: offset + i)) << (8 * i) }
        return value
    }
}

nonisolated private extension Data {
    func byte(at offset: Int) -> UInt8 {
        guard offset >= 0, offset < count else { return 0 }
        return self[startIndex + offset]
    }
}
