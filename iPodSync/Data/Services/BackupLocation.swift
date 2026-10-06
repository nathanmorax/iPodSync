//
//  BackupLocation.swift
//  iPodSync
//
//  Dónde está la carpeta de respaldo de cada iPod. Se guarda un permiso (security-scoped
//  bookmark) para que la siguiente vez la app ya sepa dónde está y solo copie lo nuevo.
//

import Foundation

@MainActor
enum BackupLocation {
    private static let defaultsKey = SettingsKey.backupFolders

    private static var all: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Carpetas a las que ya se pidió acceso en esta sesión (se dejan abiertas hasta cerrar la app).
    private static var opened: [String: URL] = [:]

    static func save(_ folder: URL, for deviceID: String) throws {
        all[deviceID] = try folder.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        if let old = opened[deviceID], old != folder { old.stopAccessingSecurityScopedResource() }
        opened[deviceID] = folder
    }

    /// La carpeta de respaldo de ese iPod con permiso de entrar, o nil si no hay o ya no existe.
    static func folder(for deviceID: String) -> URL? {
        if let url = opened[deviceID] { return FileManager.default.fileExists(atPath: url.path) ? url : nil }
        guard let data = all[deviceID] else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if isStale { try? save(url, for: deviceID) }
        opened[deviceID] = url
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
