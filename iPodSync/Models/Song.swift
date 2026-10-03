//
//  Song.swift
//  iPodSync
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

enum LibraryScope: String, CaseIterable, Identifiable {
    case songs, artists, albums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs:   "Canciones"
        case .artists: "Artistas"
        case .albums:  "Álbumes"
        }
    }

    var systemImage: String {
        switch self {
        case .songs:   "music.note"
        case .artists: "music.mic"
        case .albums:  "square.stack"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .songs:   "1"
        case .artists: "2"
        case .albums:  "3"
        }
    }
}

/// Filtro por estado de sincronización en el panel "En tu Mac".
enum LibraryStatusFilter: String, CaseIterable, Identifiable {
    case all, notOnDevice, onDevice, inQueue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:         "Todas"
        case .notOnDevice: "Sin enviar"
        case .onDevice:    "En el iPod"
        case .inQueue:     "En cola"
        }
    }

    func matches(_ status: SongSyncStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .notOnDevice:
            return status == .notOnDevice
        case .onDevice:
            return status == .onDevice
        case .inQueue:
            switch status {
            case .queued, .sending: return true
            default:                return false
            }
        }
    }
}

/// Estado de sincronización de una canción, para la fila de la biblioteca.
enum SongSyncStatus: Equatable {
    case notOnDevice
    case queued
    case sending(Double)
    case onDevice
}
