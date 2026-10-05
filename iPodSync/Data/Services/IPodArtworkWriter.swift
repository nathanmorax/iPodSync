//
//  IPodArtworkWriter.swift
//  iPodSync
//
//  Pone la portada de una canción en el iPod (5.ª generación):
//   1. Convierte la imagen a cada tamaño que usa el iPod (los dice ArtworkDB: 100×100 y 200×200
//      en el de 5.ª gen.) en píxeles RGB565 y los agrega al final de su archivo .ithmb.
//   2. Agrega una imagen (mhii) a ArtworkDB que apunta a esos píxeles y a la canción (song_id = dbid).
//   3. Marca la canción en iTunesDB como "con portada" (solo cambia unos bytes de su mhit).
//  Igual que con las canciones: guarda la base anterior, escribe aparte y comprueba al final.
//

import Foundation
import CoreGraphics
import ImageIO

nonisolated enum IPodArtworkWriter {
    enum ArtworkError: LocalizedError {
        case noArtworkDatabase
        case unsupported(String)
        case badImage
        case trackNotFound
        case verifyFailed

        var errorDescription: String? {
            switch self {
            case .noArtworkDatabase: "Este iPod todavía no tiene base de portadas (ArtworkDB)."
            case .unsupported(let d): "La base de portadas del iPod tiene un formato que no reconocemos (\(d))."
            case .badImage:          "No se pudo leer la imagen de la portada."
            case .trackNotFound:     "No se encontró la canción en la base del iPod."
            case .verifyFailed:      "La portada no quedó registrada; se regresó la base anterior."
            }
        }
    }

    /// Pone la portada para la canción con ese dbid (si ya tenía una, la reemplaza).
    /// `imageData`: JPEG/PNG de la portada.
    static func addArtwork(volume: URL, dbid: UInt64, imageData: Data) throws {
        let fm = FileManager.default
        let control = volume.appendingPathComponent("iPod_Control")
        let artDir = control.appendingPathComponent("Artwork")
        let artDB = artDir.appendingPathComponent("ArtworkDB")
        guard fm.fileExists(atPath: artDB.path) else { throw ArtworkError.noArtworkDatabase }
        guard let image = decode(imageData) else { throw ArtworkError.badImage }

        let original = try Data(contentsOf: artDB)
        var db = [UInt8](original)
        guard tag(db, 0) == "mhfd" else { throw ArtworkError.unsupported("sin mhfd") }

        // Secciones de ArtworkDB.
        let headerLength = Int(u32(db, 4))
        var sections: [(offset: Int, length: Int, type: UInt16)] = []
        var offset = headerLength
        while offset + 16 <= db.count, tag(db, offset) == "mhsd" {
            let length = Int(u32(db, offset + 8))
            guard length > 0, offset + length <= db.count else { throw ArtworkError.unsupported("mhsd dañado") }
            sections.append((offset, length, u16(db, offset + 0x0C)))
            offset += length
        }
        guard let images = sections.first(where: { $0.type == 1 }),
              let files = sections.first(where: { $0.type == 3 }) else {
            throw ArtworkError.unsupported("faltan secciones")
        }

        // Tamaños que usa este iPod (mhif: formato + bytes por imagen). Solo cuadrados RGB565.
        let formats = imageFormats(db, section: files.offset)
        guard !formats.isEmpty else { throw ArtworkError.unsupported("sin formatos de imagen") }

        // ID nuevo de imagen.
        let maxID = maxImageID(db, section: images.offset)
        let imageID = max(u32(db, 0x1C), maxID + 1)

        // 1. Píxeles al final de cada .ithmb.
        var thumbs: [(format: UInt32, file: String, offset: UInt32, size: UInt32, side: Int)] = []
        for format in formats {
            let pixels = rgb565(image, side: format.side)
            let name = ithmbName(in: artDir, format: format.id)
            let url = artDir.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            let start = try handle.seekToEnd()
            try handle.write(contentsOf: pixels)
            try handle.synchronize()
            try handle.close()
            thumbs.append((format.id, name, UInt32(start), UInt32(pixels.count), format.side))
        }

        // 2. mhii nueva al final de la lista de imágenes.
        let mhii = makeImage(id: imageID, dbid: dbid, originalSize: UInt32(imageData.count), thumbs: thumbs)
        var output = Array(db[0..<headerLength])
        for section in sections {
            var bytes = Array(db[section.offset..<(section.offset + section.length)])
            if section.type == 1 {
                let list = Int(u32(bytes, 4))
                guard tag(bytes, list) == "mhli" else { throw ArtworkError.unsupported("sin mhli") }
                let count = Int(u32(bytes, list + 8))
                let listHeader = Int(u32(bytes, list + 4))

                // Si la canción ya tenía portada, se quita su imagen vieja (mhii con el mismo song_id)
                // para que el iPod muestre la nueva. Sus píxeles viejos quedan sin usar en el .ithmb.
                var kept: [UInt8] = []
                var keptCount = 0
                var entry = list + listHeader
                for _ in 0..<count {
                    guard tag(bytes, entry) == "mhii" else { throw ArtworkError.unsupported("mhii dañado") }
                    let total = Int(u32(bytes, entry + 8))
                    guard total > 0, entry + total <= bytes.count else { throw ArtworkError.unsupported("mhii dañado") }
                    if u64(bytes, entry + 0x14) != dbid {
                        kept += bytes[entry..<(entry + total)]
                        keptCount += 1
                    }
                    entry += total
                }
                let tail = Array(bytes[entry...])

                var rebuilt = Array(bytes[0..<(list + listHeader)])
                put32(&rebuilt, list + 8, UInt32(keptCount + 1))
                rebuilt += kept
                rebuilt += mhii
                rebuilt += tail
                put32(&rebuilt, 8, UInt32(rebuilt.count))
                bytes = rebuilt
            }
            output += bytes
        }
        if offset < db.count { output += db[offset...] }
        put32(&output, 8, UInt32(output.count))
        put32(&output, 0x1C, imageID + 1)                       // siguiente id libre
        db = output

        try replace(artDB, with: Data(db), keeping: original)

        // 3. Marcar la canción en iTunesDB.
        let tunesDB = volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB")
        let tunesOriginal: Data
        do {
            tunesOriginal = try markTrack(volume: volume, dbid: dbid, imageID: imageID,
                                          imageSize: UInt32(imageData.count))
        } catch {
            try? original.write(to: artDB, options: .atomic)     // dejar todo como estaba
            throw error
        }

        // Comprobar. Si falla se regresan LAS DOS bases: antes solo ArtworkDB, y iTunesDB quedaba
        // diciendo "tiene portada" con una imagen que ya no existía.
        guard (try? ArtworkDBReader.readIndex(volume: volume))?[dbid] != nil else {
            try? original.write(to: artDB, options: .atomic)
            try? tunesOriginal.write(to: tunesDB, options: .atomic)
            throw ArtworkError.verifyFailed
        }
    }

    // MARK: - iTunesDB: marcar la canción

    /// Devuelve la iTunesDB como estaba antes, para poder regresarla si algo falla después.
    @discardableResult
    private static func markTrack(volume: URL, dbid: UInt64, imageID: UInt32, imageSize: UInt32) throws -> Data {
        let url = volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB")
        let original = try Data(contentsOf: url)
        var db = [UInt8](original)
        guard tag(db, 0) == "mhbd" else { throw ArtworkError.trackNotFound }

        var offset = Int(u32(db, 4))
        var found = false
        while offset + 16 <= db.count, tag(db, offset) == "mhsd" {
            let length = Int(u32(db, offset + 8))
            if u32(db, offset + 12) == 1 {
                let list = offset + Int(u32(db, offset + 4))
                let count = Int(u32(db, list + 8))
                var track = list + Int(u32(db, list + 4))
                for _ in 0..<count {
                    guard tag(db, track) == "mhit" else { break }
                    let header = Int(u32(db, track + 4))
                    let id = UInt64(u32(db, track + 0x70)) | UInt64(u32(db, track + 0x74)) << 32
                    if id == dbid {
                        put16(&db, track + 0x7C, 1)                     // cantidad de portadas
                        put32(&db, track + 0x80, imageSize)             // tamaño de la imagen original
                        if header >= 0xA5 { db[track + 0xA4] = 0x01 }   // tiene portada
                        if header >= 0x164 { put32(&db, track + 0x160, imageID) }  // enlace (iPods más nuevos)
                        found = true
                        break
                    }
                    let total = Int(u32(db, track + 8))
                    guard total > 0 else { break }
                    track += total
                }
            }
            guard length > 0, !found else { break }
            offset += length
        }
        guard found else { throw ArtworkError.trackNotFound }
        try replace(url, with: Data(db), keeping: original)
        return original
    }

    // MARK: - Lectura de ArtworkDB

    private static func imageFormats(_ db: [UInt8], section: Int) -> [(id: UInt32, side: Int)] {
        let list = section + Int(u32(db, section + 4))          // mhlf
        guard tag(db, list) == "mhlf" else { return [] }
        let count = Int(u32(db, list + 8))
        var offset = list + Int(u32(db, list + 4))
        var result: [(id: UInt32, side: Int)] = []
        for _ in 0..<count {
            guard tag(db, offset) == "mhif" else { break }
            let id = u32(db, offset + 0x10)
            let size = Int(u32(db, offset + 0x14))
            let side = Int(Double(size / 2).squareRoot())
            if side > 0, side * side * 2 == size { result.append((id: id, side: side)) }
            let total = Int(u32(db, offset + 8))
            guard total > 0 else { break }
            offset += total
        }
        return result
    }

    private static func maxImageID(_ db: [UInt8], section: Int) -> UInt32 {
        let list = section + Int(u32(db, section + 4))          // mhli
        let count = Int(u32(db, list + 8))
        var offset = list + Int(u32(db, list + 4))
        var maxID: UInt32 = 0
        for _ in 0..<count {
            guard tag(db, offset) == "mhii" else { break }
            maxID = max(maxID, u32(db, offset + 0x10))
            let total = Int(u32(db, offset + 8))
            guard total > 0 else { break }
            offset += total
        }
        return maxID
    }

    /// El .ithmb más nuevo de ese formato (F1029_3.ithmb), o _1 si todavía no hay.
    private static func ithmbName(in dir: URL, format: UInt32) -> String {
        let prefix = "F\(format)_"
        let numbers = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".ithmb") }
            .compactMap { Int($0.dropFirst(prefix.count).dropLast(".ithmb".count)) }
        return "\(prefix)\(numbers.max() ?? 1).ithmb"
    }

    // MARK: - Registros nuevos

    private static func makeImage(id: UInt32, dbid: UInt64, originalSize: UInt32,
                                  thumbs: [(format: UInt32, file: String, offset: UInt32, size: UInt32, side: Int)]) -> [UInt8] {
        var children: [UInt8] = []
        for t in thumbs {
            // mhod tipo 3: nombre del archivo, en UTF‑16, rellenado a múltiplo de 4.
            var name: [UInt8] = []
            for unit in ":\(t.file)".utf16 { name += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
            let padded = name + [UInt8](repeating: 0, count: (4 - name.count % 4) % 4)
            var fileMhod = [UInt8](repeating: 0, count: 0x24)
            putTag(&fileMhod, 0, "mhod")
            put32(&fileMhod, 4, 0x18)
            put32(&fileMhod, 8, UInt32(0x24 + padded.count))
            put16(&fileMhod, 0x0C, 3)
            put32(&fileMhod, 0x18, UInt32(name.count))
            put32(&fileMhod, 0x1C, 2)                         // UTF‑16
            fileMhod += padded

            var mhni = [UInt8](repeating: 0, count: 0x4C)
            putTag(&mhni, 0, "mhni")
            put32(&mhni, 4, 0x4C)
            put32(&mhni, 8, UInt32(0x4C + fileMhod.count))
            put32(&mhni, 0x0C, 1)
            put32(&mhni, 0x10, t.format)
            put32(&mhni, 0x14, t.offset)
            put32(&mhni, 0x18, t.size)
            put16(&mhni, 0x20, UInt16(t.side))                // alto
            put16(&mhni, 0x22, UInt16(t.side))                // ancho
            mhni += fileMhod

            var container = [UInt8](repeating: 0, count: 0x18)
            putTag(&container, 0, "mhod")
            put32(&container, 4, 0x18)
            put32(&container, 8, UInt32(0x18 + mhni.count))
            put16(&container, 0x0C, 2)
            children += container + mhni
        }

        var mhii = [UInt8](repeating: 0, count: 0x98)
        putTag(&mhii, 0, "mhii")
        put32(&mhii, 4, 0x98)
        put32(&mhii, 8, UInt32(0x98 + children.count))
        put32(&mhii, 0x0C, UInt32(thumbs.count))
        put32(&mhii, 0x10, id)
        put64(&mhii, 0x14, dbid)
        put32(&mhii, 0x30, originalSize)
        return mhii + children
    }

    // MARK: - Imagen → RGB565

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Recorta al centro (cuadrada), escala a side×side y convierte a RGB565 little‑endian.
    private static func rgb565(_ image: CGImage, side: Int) -> Data {
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            context.interpolationQuality = .high
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let scale = CGFloat(side) / min(w, h)
            let drawW = w * scale, drawH = h * scale
            context.draw(image, in: CGRect(x: (CGFloat(side) - drawW) / 2, y: (CGFloat(side) - drawH) / 2,
                                           width: drawW, height: drawH))
        }
        var out = [UInt8](repeating: 0, count: side * side * 2)
        for i in 0..<(side * side) {
            let r = UInt16(rgba[i * 4]) >> 3, g = UInt16(rgba[i * 4 + 1]) >> 2, b = UInt16(rgba[i * 4 + 2]) >> 3
            let value = (r << 11) | (g << 5) | b
            out[i * 2] = UInt8(value & 0xFF)
            out[i * 2 + 1] = UInt8(value >> 8)
        }
        return Data(out)
    }

    // MARK: - Escritura segura

    /// Guarda la versión anterior (.ipodsync-anterior), escribe aparte y reemplaza.
    private static func replace(_ url: URL, with data: Data, keeping original: Data) throws {
        let fm = FileManager.default
        let previous = url.appendingPathExtension("ipodsync-anterior")
        let temp = url.appendingPathExtension("ipodsync-nuevo")
        try? fm.removeItem(at: previous)
        try original.write(to: previous)
        try data.write(to: temp)
        do {
            try fm.removeItem(at: url)
            try fm.moveItem(at: temp, to: url)
        } catch {
            if !fm.fileExists(atPath: url.path) { try? original.write(to: url) }
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    // MARK: - Bytes

    private static func tag(_ b: [UInt8], _ o: Int) -> String? {
        guard o >= 0, o + 4 <= b.count else { return nil }
        return String(bytes: b[o..<(o + 4)], encoding: .ascii)
    }
    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        guard o >= 0, o + 2 <= b.count else { return 0 }
        return UInt16(b[o]) | UInt16(b[o + 1]) << 8
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
    private static func u64(_ b: [UInt8], _ o: Int) -> UInt64 {
        UInt64(u32(b, o)) | UInt64(u32(b, o + 4)) << 32
    }

    private static func put64(_ b: inout [UInt8], _ o: Int, _ v: UInt64) {
        guard o + 8 <= b.count else { return }
        for i in 0..<8 { b[o + i] = UInt8((v >> (8 * UInt64(i))) & 0xFF) }
    }
}
