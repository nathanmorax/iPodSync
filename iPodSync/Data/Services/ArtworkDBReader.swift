//
//  ArtworkDBReader.swift
//  iPodSync
//
//  Lee las portadas del iPod (solo lectura).
//
//  - iPod_Control/Artwork/ArtworkDB: índice. Cada imagen (mhii) dice a qué canción pertenece
//    (song_id = dbid de la canción en iTunesDB) y en qué archivo .ithmb está cada tamaño (mhni).
//  - iPod_Control/Artwork/F1029_1.ithmb, etc.: los píxeles en crudo, RGB565 little‑endian.
//    iPod (5.ª gen): 1028 = 100×100, 1029 = 200×200. iPod classic: 1055/1068 = 128×128, 1060 = 320×320, 1061 = 56×56.
//

import Foundation
import CoreGraphics

nonisolated enum ArtworkDBReader {
    /// Dónde está una portada dentro de un archivo .ithmb.
    struct Thumbnail: Sendable, Hashable {
        let file: String           // "F1029_1.ithmb"
        let formatID: Int
        let offset: Int
        let size: Int
        let width: Int
        let height: Int
        let horizontalPadding: Int
        let verticalPadding: Int
    }

    /// Para mostrar en listas (30–60 pt) preferimos una portada de al menos este ancho.
    static let preferredMinWidth = 90

    /// Índice dbid de la canción → mejor miniatura disponible.
    static func readIndex(volume: URL) throws -> [UInt64: Thumbnail] {
        try readAllSizes(volume: volume).compactMapValues { pick($0) }
    }

    /// Índice dbid de la canción → todos los tamaños guardados de su portada (100×100, 200×200…).
    static func readAllSizes(volume: URL) throws -> [UInt64: [Thumbnail]] {
        let url = volume.appendingPathComponent("iPod_Control/Artwork/ArtworkDB")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        // Lectura normal (sin mapear): mapear un disco que se puede desconectar truena la app.
        let db = try Data(contentsOf: url)
        guard tag(db, 0) == "mhfd" else { return [:] }

        var index: [UInt64: [Thumbnail]] = [:]
        let sectionCount = Int(u32(db, 0x14))
        var offset = Int(u32(db, 4))
        for _ in 0..<max(sectionCount, 1) {
            guard tag(db, offset) == "mhsd" else { break }
            let sectionLength = Int(u32(db, offset + 8))
            if u16(db, offset + 0x0C) == 1 {
                readImages(db, section: offset, into: &index)
            }
            guard sectionLength > 0 else { break }
            offset += sectionLength
        }
        return index
    }

    private static func readImages(_ db: Data, section: Int, into index: inout [UInt64: [Thumbnail]]) {
        let list = section + Int(u32(db, section + 4))          // mhli
        guard tag(db, list) == "mhli" else { return }
        let count = Int(u32(db, list + 8))
        var offset = list + Int(u32(db, list + 4))
        for _ in 0..<count {
            guard tag(db, offset) == "mhii" else { return }
            let total = Int(u32(db, offset + 8))
            guard total > 0 else { return }
            let songID = UInt64(u32(db, offset + 0x14)) | UInt64(u32(db, offset + 0x18)) << 32
            let thumbs = thumbnails(db, image: offset)
            let usable = thumbs.filter { $0.size > 0 && $0.width > 0 && $0.height > 0 }
            if songID != 0, !usable.isEmpty { index[songID] = usable }
            offset += total
        }
    }

    /// Las miniaturas (mhni) de una imagen (mhii).
    private static func thumbnails(_ db: Data, image: Int) -> [Thumbnail] {
        var result: [Thumbnail] = []
        let children = Int(u32(db, image + 0x0C))
        let end = image + Int(u32(db, image + 8))
        var offset = image + Int(u32(db, image + 4))
        for _ in 0..<children {
            guard offset < end, tag(db, offset) == "mhod" else { break }
            let length = Int(u32(db, offset + 8))
            let type = u16(db, offset + 0x0C)
            let child = offset + Int(u32(db, offset + 4))
            if (type == 2 || type == 5), tag(db, child) == "mhni" {
                let formatID = Int(u32(db, child + 0x10))
                let name = fileName(db, mhni: child) ?? "F\(formatID)_1.ithmb"
                result.append(Thumbnail(
                    file: name,
                    formatID: formatID,
                    offset: Int(u32(db, child + 0x14)),
                    size: Int(u32(db, child + 0x18)),
                    width: Int(u16(db, child + 0x22)),
                    height: Int(u16(db, child + 0x20)),
                    horizontalPadding: Int(Int16(bitPattern: u16(db, child + 0x1E))),
                    verticalPadding: Int(Int16(bitPattern: u16(db, child + 0x1C)))
                ))
            }
            guard length > 0 else { break }
            offset += length
        }
        return result
    }

    /// Nombre del .ithmb (mhod tipo 3 dentro del mhni), p. ej. ":F1029_1.ithmb" → "F1029_1.ithmb".
    private static func fileName(_ db: Data, mhni: Int) -> String? {
        let children = Int(u32(db, mhni + 0x0C))
        guard children > 0 else { return nil }
        let mhod = mhni + Int(u32(db, mhni + 4))
        guard tag(db, mhod) == "mhod", u16(db, mhod + 0x0C) == 3 else { return nil }
        let length = Int(u32(db, mhod + 0x18))
        let encoding = db.byte(at: mhod + 0x1C)               // 2 = UTF‑16; si no, UTF‑8
        let start = mhod + 0x24
        guard length > 0, start + length <= db.count else { return nil }
        let bytes = db.subdata(in: (db.startIndex + start)..<(db.startIndex + start + length))
        let text = String(data: bytes, encoding: encoding == 2 ? .utf16LittleEndian : .utf8)
        return text?.split(separator: ":").last.map(String.init)
    }

    /// La más chica que todavía se vea nítida a `minWidth` píxeles; si ninguna llega, la más grande.
    static func pick(_ thumbs: [Thumbnail], minWidth: Int = preferredMinWidth) -> Thumbnail? {
        let usable = thumbs.filter { $0.size > 0 && $0.width > 0 && $0.height > 0 }
        return usable.filter { $0.width >= minWidth }.min { $0.width < $1.width }
            ?? usable.max { $0.width < $1.width }
    }

    // MARK: - Píxeles

    /// Lee y decodifica una portada del .ithmb (RGB565 little‑endian).
    static func loadImage(volume: URL, thumbnail t: Thumbnail) -> CGImage? {
        let url = volume.appendingPathComponent("iPod_Control/Artwork").appendingPathComponent(t.file)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(t.offset))) != nil,
              let raw = try? handle.read(upToCount: t.size), raw.count == t.size else { return nil }

        // Tamaño guardado: el de la imagen si cuadra; si no, el cuadro completo del formato (con relleno).
        let pixels = t.size / 2
        var storedWidth = t.width
        var storedHeight = t.height
        if storedWidth * storedHeight != pixels {
            let side = Int(Double(pixels).squareRoot())
            guard side * side == pixels else { return nil }
            storedWidth = side
            storedHeight = side
        }

        var rgba = [UInt8](repeating: 255, count: storedWidth * storedHeight * 4)
        raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            for i in 0..<(storedWidth * storedHeight) {
                let value = UInt16(src[i * 2]) | UInt16(src[i * 2 + 1]) << 8
                let r = UInt8((value >> 11) & 0x1F), g = UInt8((value >> 5) & 0x3F), b = UInt8(value & 0x1F)
                rgba[i * 4]     = (r << 3) | (r >> 2)
                rgba[i * 4 + 1] = (g << 2) | (g >> 4)
                rgba[i * 4 + 2] = (b << 3) | (b >> 2)
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: storedWidth, height: storedHeight,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: storedWidth * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }

        // Quita el relleno si la imagen real es más chica que el cuadro guardado.
        if storedWidth != t.width || storedHeight != t.height,
           t.width > 0, t.height > 0,
           t.horizontalPadding >= 0, t.verticalPadding >= 0,
           t.horizontalPadding + t.width <= storedWidth, t.verticalPadding + t.height <= storedHeight {
            return image.cropping(to: CGRect(x: t.horizontalPadding, y: t.verticalPadding,
                                             width: t.width, height: t.height)) ?? image
        }
        return image
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

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data.byte(at: offset)) | UInt16(data.byte(at: offset + 1)) << 8
    }
}

nonisolated private extension Data {
    func byte(at offset: Int) -> UInt8 {
        guard offset >= 0, offset < count else { return 0 }
        return self[startIndex + offset]
    }
}
