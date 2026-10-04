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

/// De dónde viene la música que se ve en el panel.
enum LibrarySource: String, CaseIterable, Identifiable {
    case mac, iPod

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mac:  "En mi Mac"
        case .iPod: "En mi iPod"
        }
    }

    var systemImage: String {
        switch self {
        case .mac:  "laptopcomputer"
        case .iPod: "ipod"
        }
    }
}

/// Filtro por estado en "En mi Mac".
enum LibraryStatusFilter: String, CaseIterable, Identifiable {
    case all, notOnDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:         "Todas"
        case .notOnDevice: "Sin enviar"
        }
    }

    func matches(_ status: SongSyncStatus) -> Bool {
        switch self {
        case .all:         true
        case .notOnDevice: status == .notOnDevice
        }
    }
}
