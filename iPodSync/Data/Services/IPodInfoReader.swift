//
//  IPodInfoReader.swift
//  iPodSync
//
//  Lee del propio iPod lo que muestra el Finder: el nombre ("iNathan"), el modelo
//  ("iPod (quinta generación)") y la versión de software. Necesita el permiso de acceso al disco.
//
//  - Nombre: título de la lista maestra en iPod_Control/iTunes/iTunesDB (lo que cambia el Finder
//    al renombrar el iPod). Si no se puede, iPod_Control/iTunes/DeviceInfo.
//  - Modelo y software: iPod_Control/Device/SysInfo (texto "clave: valor").
//

import Foundation

enum IPodInfoReader {
    struct Info {
        var name: String?
        var modelName: String?
        var softwareVersion: String?
    }

    static func read(volume: URL) -> Info {
        let control = volume.appendingPathComponent("iPod_Control")
        let sysInfo = readSysInfo(control.appendingPathComponent("Device/SysInfo"))

        let name = masterPlaylistName(control.appendingPathComponent("iTunes/iTunesDB"))
            ?? deviceInfoName(control.appendingPathComponent("iTunes/DeviceInfo"))

        return Info(name: name,
                    modelName: modelName(forModelNumber: sysInfo["ModelNumStr"]),
                    softwareVersion: softwareVersion(sysInfo["visibleBuildID"]))
    }

    // MARK: - SysInfo

    private static func readSysInfo(_ url: URL) -> [String: String] {
        guard let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    /// "visibleBuildID: 0x01308000 (1.3)" → "1.3"
    private static func softwareVersion(_ raw: String?) -> String? {
        guard let raw, let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"),
              open < close else { return nil }
        return String(raw[raw.index(after: open)..<close])
    }

    /// El número de modelo viene como "xA002" o "MA002"; nos fijamos en los últimos 4 caracteres.
    static func modelName(forModelNumber raw: String?) -> String? {
        guard let raw, raw.count >= 4 else { return nil }
        let key = String(raw.suffix(4)).uppercased()
        let fifth: Set<String> = ["A002", "A003", "A146", "A147", "A452",           // 5.ª generación
                                  "A444", "A446", "A448", "A450", "A664"]           // 5.ª (finales de 2006)
        let classic: Set<String> = ["B029", "B147", "B145", "B150",                // classic 80/160 GB
                                    "B562", "B565",                                 // classic 120 GB
                                    "C293", "C297"]                                 // classic 160 GB (2009)
        let fourth: Set<String> = ["9282", "9787", "9268", "9830", "9585", "9586",  // 4.ª y photo
                                   "9829", "A079", "A127"]
        if fifth.contains(key) { return "iPod (quinta generación)" }
        if classic.contains(key) { return "iPod classic" }
        if fourth.contains(key) { return "iPod (cuarta generación)" }
        return "iPod"
    }

    // MARK: - DeviceInfo

    /// 2 bytes con la cantidad de caracteres y luego el nombre en UTF‑16 little‑endian.
    private static func deviceInfoName(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count > 2 else { return nil }
        let count = Int(data[0]) | Int(data[1]) << 8
        let end = min(data.count, 2 + count * 2)
        guard count > 0, end > 2 else { return nil }
        return clean(String(data: data[2..<end], encoding: .utf16LittleEndian))
    }

    // MARK: - iTunesDB (solo el nombre de la lista maestra)

    private static func masterPlaylistName(_ url: URL) -> String? {
        guard let db = try? Data(contentsOf: url, options: .alwaysMapped),
              tag(db, 0) == "mhbd" else { return nil }

        // mhbd → varios mhsd; el de tipo 2 (o 3) trae las listas; la primera lista es la maestra.
        var offset = Int(u32(db, 4))
        while offset + 16 <= db.count, tag(db, offset) == "mhsd" {
            let sectionLength = Int(u32(db, offset + 8))
            let type = u32(db, offset + 12)
            if type == 2 || type == 3 {
                let listHeader = offset + Int(u32(db, offset + 4))       // mhlp
                guard tag(db, listHeader) == "mhlp" else { return nil }
                let playlist = listHeader + Int(u32(db, listHeader + 4)) // primer mhyp
                guard tag(db, playlist) == "mhyp" else { return nil }
                return playlistTitle(db, at: playlist)
            }
            guard sectionLength > 0 else { return nil }
            offset += sectionLength
        }
        return nil
    }

    private static func playlistTitle(_ db: Data, at playlist: Int) -> String? {
        let mhodCount = Int(u32(db, playlist + 12))
        var offset = playlist + Int(u32(db, playlist + 4))
        for _ in 0..<mhodCount {
            guard offset + 40 <= db.count, tag(db, offset) == "mhod" else { return nil }
            let length = Int(u32(db, offset + 8))
            if u32(db, offset + 12) == 1 {                    // tipo 1 = título
                let encoding = u32(db, offset + 24)          // 1 = UTF‑16, 2 = UTF‑8
                let byteCount = Int(u32(db, offset + 28))
                let start = offset + 40
                guard start + byteCount <= db.count else { return nil }
                let bytes = db[start..<(start + byteCount)]
                return clean(String(data: bytes, encoding: encoding == 2 ? .utf8 : .utf16LittleEndian))
            }
            guard length > 0 else { return nil }
            offset += length
        }
        return nil
    }

    // MARK: - Utilidades

    private static func tag(_ data: Data, _ offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return String(data: data[offset..<(offset + 4)], encoding: .ascii)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(data[data.startIndex + offset + i]) << (8 * i) }
        return value
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
