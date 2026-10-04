//
//  Song.swift
//  iPodSync
//
//  Canción de la biblioteca de la Mac y su estado de sincronización.
//  Las de ejemplo (MockLibrary) solo traen lo básico; las agregadas desde un archivo traen
//  sus datos reales (título, artista, álbum, duración, portada) y el permiso para leer el archivo.
//

import SwiftUI

nonisolated struct Song: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    let title: String
    let artist: String
    let sizeMB: Double
    let artworkHue: Double
    var isOnDevice: Bool

    // MARK: Datos del archivo (vacíos en las canciones de ejemplo)

    var albumName: String? = nil
    var genre: String? = nil
    var trackNumber: Int? = nil
    var year: Int? = nil
    var durationSeconds: Double? = nil
    /// "mp3", "m4a"…
    var fileFormat: String? = nil
    /// Dónde está el archivo en la Mac (se vuelve a calcular desde `bookmark` al abrir la app).
    var fileURL: URL? = nil
    /// Permiso del sandbox para volver a leer el archivo después (security‑scoped bookmark).
    var bookmark: Data? = nil
    /// Portada reducida (JPEG ~300 px) sacada del archivo.
    var artworkData: Data? = nil

    /// Álbum; las de ejemplo (y las que no traen álbum) son su propio sencillo.
    var album: String { albumName ?? title }

    var sizeText: String {
        String(format: "%.1f MB", sizeMB).replacingOccurrences(of: ".", with: ",")
    }

    var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let seconds = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "Artista · Álbum · 3:45" (o el tamaño si no se sabe la duración).
    var librarySubtitle: String {
        [artist, albumName, durationText ?? sizeText].compactMap { $0 }.joined(separator: " · ")
    }

    /// El archivo ya no está donde estaba (se movió o se borró).
    var isFileMissing: Bool {
        guard let fileURL else { return bookmark != nil }
        return !FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func initials(of text: String) -> String {
        let words = text.filter { $0.isLetter || $0 == " " }.split(separator: " ")
        if words.count > 1, let a = words.first?.first, let b = words.last?.first {
            return String([a, b]).uppercased()
        }
        return String(text.prefix(2)).uppercased()
    }
}

extension Song {
    /// Identifica el álbum: mismo nombre de álbum y mismo artista.
    var albumKey: String {
        "\(artist)|\(album)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Orden dentro de un álbum: número de pista y luego título.
    static func albumOrder(_ a: Song, _ b: Song) -> Bool {
        switch (a.trackNumber, b.trackNumber) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.title.localizedCompare(b.title) == .orderedAscending
        }
    }

    var artworkGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: artworkHue, saturation: 0.40, brightness: 0.86),
                Color(hue: artworkHue, saturation: 0.62, brightness: 0.64)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Estado de sincronización de una canción, para la fila de la biblioteca.
enum SongSyncStatus: Equatable {
    case notOnDevice
    case queued
    case sending(Double)
    case onDevice
}
