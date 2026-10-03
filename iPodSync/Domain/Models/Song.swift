//
//  Song.swift
//  iPodSync
//
//  Canción de la biblioteca y su estado de sincronización.
//

import SwiftUI

struct Song: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let sizeMB: Double
    let artworkHue: Double
    var isOnDevice: Bool

    /// Mientras no haya metadatos reales, cada canción es su propio sencillo.
    var album: String { title }

    var sizeText: String {
        String(format: "%.1f MB", sizeMB).replacingOccurrences(of: ".", with: ",")
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

    static func initials(of text: String) -> String {
        let words = text.filter { $0.isLetter || $0 == " " }.split(separator: " ")
        if words.count > 1, let a = words.first?.first, let b = words.last?.first {
            return String([a, b]).uppercased()
        }
        return String(text.prefix(2)).uppercased()
    }
}

/// Estado de sincronización de una canción, para la fila de la biblioteca.
enum SongSyncStatus: Equatable {
    case notOnDevice
    case queued
    case sending(Double)
    case onDevice
}
