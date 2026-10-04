//
//  IPodArtworkStore.swift
//  iPodSync
//
//  Portadas del iPod con caché. Lee el índice (ArtworkDB) una vez y decodifica cada portada
//  solo cuando una fila la necesita, fuera del hilo principal.
//

import Foundation
import CoreGraphics

actor IPodArtworkStore {
    private let volume: URL
    private var index: [UInt64: [ArtworkDBReader.Thumbnail]]?
    /// Caché por canción y tamaño (la de 100 px para listas, la de 200 px para la cuadrícula).
    private var cache: [String: CGImage] = [:]
    private var missing: Set<UInt64> = []

    init(volume: URL) {
        self.volume = volume
    }

    /// Cuántas portadas hay en el iPod (lee el índice si hace falta).
    func count() -> Int {
        loadIndexIfNeeded().count
    }

    /// Portada para mostrarse a `minPixels` de ancho: usa el tamaño guardado más chico que alcance
    /// (o el más grande que haya; el iPod de 5.ª gen. guarda hasta 200×200).
    func image(for dbid: UInt64, minPixels: Int = ArtworkDBReader.preferredMinWidth) -> CGImage? {
        guard dbid != 0, !missing.contains(dbid) else { return nil }
        guard let sizes = loadIndexIfNeeded()[dbid],
              let thumbnail = ArtworkDBReader.pick(sizes, minWidth: minPixels) else {
            missing.insert(dbid)
            return nil
        }
        let key = "\(dbid)-\(thumbnail.formatID)"
        if let cached = cache[key] { return cached }
        guard let image = ArtworkDBReader.loadImage(volume: volume, thumbnail: thumbnail) else {
            missing.insert(dbid)
            return nil
        }
        if cache.count > 2_000 { cache.removeAll(keepingCapacity: true) }   // límite simple de memoria
        cache[key] = image
        return image
    }

    private func loadIndexIfNeeded() -> [UInt64: [ArtworkDBReader.Thumbnail]] {
        if let index { return index }
        let loaded = (try? ArtworkDBReader.readAllSizes(volume: volume)) ?? [:]
        index = loaded
        return loaded
    }
}
