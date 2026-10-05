//
//  VolumeAccess.swift
//  iPodSync
//
//  Permiso del sandbox para entrar al disco del iPod. La persona elige el iPod una vez en un
//  diálogo; guardamos un "security-scoped bookmark" para no volver a preguntar.
//

import Foundation

enum VolumeAccess {
    private static let defaultsKey = SettingsKey.iPodVolumeBookmarks

    private static var all: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static func hasBookmark(for volumeID: String) -> Bool {
        all[volumeID] != nil
    }

    /// Guarda el permiso para la carpeta que la persona eligió (debe ser la raíz del iPod).
    static func save(_ url: URL, for volumeID: String) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        all[volumeID] = data
    }

    static func forget(_ volumeID: String) {
        all[volumeID] = nil
    }

    /// URL con permiso para el iPod, o nil si no hay permiso guardado (o ya no sirve).
    /// No intenta montar el disco si no está conectado.
    static func resolve(for volumeID: String) -> URL? {
        guard let data = all[volumeID] else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope, .withoutMounting],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            // El sistema pide renovarlo de vez en cuando; se hace en silencio.
            let didAccess = url.startAccessingSecurityScopedResource()
            try? save(url, for: volumeID)
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }
}
