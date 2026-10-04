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
    private var index: [UInt64: ArtworkDBReader.Thumbnail]?
    private var cache: [UInt64: CGImage] = [:]
    private var missing: Set<UInt64> = []

    init(volume: URL) {
        self.volume = volume
    }

    /// Cuántas portadas hay en el iPod (lee el índice si hace falta).
    func count() -> Int {
        loadIndexIfNeeded().count
    }

    func image(for dbid: UInt64) -> CGImage? {
        guard dbid != 0 else { return nil }
        if let cached = cache[dbid] { return cached }
        if missing.contains(dbid) { return nil }

        guard let thumbnail = loadIndexIfNeeded()[dbid],
              let image = ArtworkDBReader.loadImage(volume: volume, thumbnail: thumbnail) else {
            missing.insert(dbid)
            return nil
        }
        if cache.count > 2_000 { cache.removeAll(keepingCapacity: true) }   // límite simple de memoria
        cache[dbid] = image
        return image
    }

    private func loadIndexIfNeeded() -> [UInt64: ArtworkDBReader.Thumbnail] {
        if let index { return index }
        let loaded = (try? ArtworkDBReader.readIndex(volume: volume)) ?? [:]
        index = loaded
        return loaded
    }
}
