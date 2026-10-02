//
//  AppSettings.swift
//  iPodSync
//
//  Llaves de las preferencias que la persona puede cambiar en Ajustes (⌘,).
//

import Foundation

enum SettingsKey {
    static let rowDensity   = "rowDensity"     // "regular" | "compact"
    static let lcdTint      = "lcdTint"        // "green" | "blue" | "amber"
    static let showKeyHints = "showKeyHints"   // Bool
}
