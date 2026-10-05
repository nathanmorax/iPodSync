//
//  AppSettings.swift
//  iPodSync
//
//  Todas las llaves de UserDefaults de la app en un solo lugar.
//

import Foundation

nonisolated enum SettingsKey {
    // MARK: Ajustes (⌘,)

    static let rowDensity   = "rowDensity"     // "regular" | "compact"
    static let lcdTint      = "lcdTint"        // "green" | "blue" | "amber"
    static let showKeyHints = "showKeyHints"   // Bool
    static let simulateIPod = "simulateIPod"   // Bool: usar el iPod de prueba en vez del real
    static let albumColumns = "albumColumns"   // Int: 2 o 3 columnas en Álbumes

    // MARK: Estado interno (no aparece en Ajustes)
    static let libraryScope = "libraryScope"           // Canciones / Artistas / Álbumes
    static let lastIPodBackups = "lastIPodBackups"     // [id del iPod: fecha del último respaldo]
    static let iPodVolumeBookmarks = "iPodVolumeBookmarks" // acceso guardado a cada iPod
}
