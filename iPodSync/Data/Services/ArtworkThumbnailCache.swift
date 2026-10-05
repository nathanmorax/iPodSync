//
//  ArtworkThumbnailCache.swift
//  iPodSync
//
//  Miniaturas de portadas (de la Mac) reducidas al tamaño en que se muestran, fuera del hilo
//  principal y guardadas en caché. Antes cada fila hacía NSImage(data:) en `body`: decodificaba
//  la portada completa (600 px o más) en cada redibujado, aunque se viera de 30 pt.
//

import Foundation
import CoreGraphics
import ImageIO

actor ArtworkThumbnailCache {
    static let shared = ArtworkThumbnailCache()

    nonisolated struct Key: Hashable, Sendable {
        /// Identifica la imagen (cambia si cambia la portada).
        let image: Int
        /// Tamaño redondeado hacia arriba a múltiplos de 64 px para reutilizar miniaturas.
        let pixels: Int
    }

    private var cache: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let limit = 800

    /// Llave para una portada: tamaño + primeros bytes (barato y cambia si la imagen cambia).
    nonisolated static func imageID(for data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data)
        return hasher.finalize()
    }

    func thumbnail(for data: Data, imageID: Int, maxPixels: Int) -> CGImage? {
        let bucket = max(64, ((maxPixels + 63) / 64) * 64)
        let key = Key(image: imageID, pixels: bucket)
        if let hit = cache[key] { return hit }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        cache[key] = image
        order.append(key)
        if order.count > limit {
            // Se olvidan las más viejas.
            for old in order.prefix(limit / 4) { cache[old] = nil }
            order.removeFirst(limit / 4)
        }
        return image
    }
}
