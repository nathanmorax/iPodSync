//
//  IPodTrack.swift
//  iPodSync
//
//  Una canción que ya está en el iPod, leída de su base de datos (iTunesDB).
//

import Foundation

nonisolated struct IPodTrack: Identifiable, Hashable, Sendable {
    /// ID interno del iPod (único dentro de su iTunesDB).
    let id: UInt32
    /// ID de 64 bits de la canción; une la canción con su portada en ArtworkDB.
    var dbid: UInt64 = 0
    /// El iPod dice que esta canción tiene portada.
    var hasArtwork = false
    let title: String
    let artist: String
    let album: String
    let genre: String
    /// Ruta en el iPod con ":" como separador, p. ej. ":iPod_Control:Music:F03:ABCD.mp3".
    let location: String
    let sizeBytes: Int64
    let durationMs: Int
    let trackNumber: Int
    let year: Int
    let playCount: Int
    /// 0 a 5 estrellas.
    let rating: Int

    var durationText: String {
        let seconds = durationMs / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var sizeText: String {
        String(format: "%.1f MB", Double(sizeBytes) / 1_048_576).replacingOccurrences(of: ".", with: ",")
    }

    /// Color estable para la portada de relleno (todavía no leemos las portadas del iPod).
    var artworkHue: Double {
        let key = album.isEmpty ? artist : album
        let hash = key.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Double(hash % 360) / 360
    }
}
