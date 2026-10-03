//
//  LibraryScope.swift
//  iPodSync
//
//  Cómo se ve la biblioteca (Canciones/Artistas/Álbumes) y el filtro por estado.
//

import SwiftUI

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
