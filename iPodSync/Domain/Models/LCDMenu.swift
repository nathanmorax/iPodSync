//
//  LCDMenu.swift
//  iPodSync
//
//  Pantallas y filas del menú del LCD del iPod.
//

import SwiftUI
import Observation

enum LCDScreenID: Equatable {
    case main, recents, songs, artists, storage, settings

    var title: String {
        switch self {
        case .main:     "TONO"
        case .recents:  "RECIENTES"
        case .songs:    "CANCIONES"
        case .artists:  "ARTISTAS"
        case .storage:  "ESPACIO"
        case .settings: "AJUSTES"
        }
    }
}

enum LCDRowAction: Equatable {
    case open(LCDScreenID)
    case toggleBacklight
}

struct LCDRow: Identifiable, Equatable {
    let id: String
    let title: String
    var value: String? = nil
    var action: LCDRowAction? = nil
}
