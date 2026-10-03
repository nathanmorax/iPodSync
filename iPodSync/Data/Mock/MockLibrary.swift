//
//  MockLibrary.swift
//  iPodSync
//

import Foundation

enum MockLibrary {
    static let songs: [Song] = [
        Song(title: "Luz de día",         artist: "Los Enanitos Verdes", sizeMB: 9.6,  artworkHue: 0.60, isOnDevice: true),
        Song(title: "Nocturno",           artist: "Ximena Sariñana",     sizeMB: 8.7,  artworkHue: 0.73, isOnDevice: false),
        Song(title: "Mar adentro",        artist: "Natalia Lafourcade",  sizeMB: 11.4, artworkHue: 0.84, isOnDevice: false),
        Song(title: "Espejos",            artist: "Caifanes",            sizeMB: 10.5, artworkHue: 0.98, isOnDevice: true),
        Song(title: "Paracaídas",         artist: "Porter",              sizeMB: 9.1,  artworkHue: 0.10, isOnDevice: false),
        Song(title: "Ciudad dormida",     artist: "Zoé",                 sizeMB: 10.2, artworkHue: 0.22, isOnDevice: false),
        Song(title: "Polvo de estrellas", artist: "Carla Morrison",      sizeMB: 8.1,  artworkHue: 0.33, isOnDevice: false),
        Song(title: "Aguacero",           artist: "Bengala",             sizeMB: 9.3,  artworkHue: 0.48, isOnDevice: true),
        Song(title: "Norte",              artist: "Hello Seahorse!",     sizeMB: 8.8,  artworkHue: 0.63, isOnDevice: false),
        Song(title: "Marea alta",         artist: "Little Jesus",        sizeMB: 7.9,  artworkHue: 0.55, isOnDevice: false),
        Song(title: "Desierto",           artist: "Siddhartha",          sizeMB: 10.8, artworkHue: 0.06, isOnDevice: false)
    ]

    /// Capacidad del iPod y espacio libre inicial (mock).
    static let capacityGB: Double = 160
    static let initialFreeGB: Double = 65.3
}
