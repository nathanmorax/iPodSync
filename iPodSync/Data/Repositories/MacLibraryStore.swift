//
//  MacLibraryStore.swift
//  iPodSync
//
//  Guarda la biblioteca de la Mac (las canciones que agregaste) entre aperturas de la app,
//  en ~/Library/Containers/…/Application Support/iPodSync/library.json.
//

import Foundation

nonisolated enum MacLibraryStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("iPodSync", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    static func load() -> [Song] {
        guard let data = try? Data(contentsOf: fileURL),
              var songs = try? JSONDecoder().decode([Song].self, from: data) else { return [] }

        // La ruta guardada puede ya no servir (archivo movido); el bookmark la vuelve a encontrar.
        for index in songs.indices {
            guard let bookmark = songs[index].bookmark else { continue }
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                  relativeTo: nil, bookmarkDataIsStale: &isStale) {
                songs[index].fileURL = url
                if isStale {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    songs[index].bookmark = (try? url.bookmarkData(options: .withSecurityScope,
                                                                   includingResourceValuesForKeys: nil,
                                                                   relativeTo: nil)) ?? bookmark
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        return songs.map { var s = $0; s.isOnDevice = false; return s }
    }

    static func save(_ songs: [Song]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(songs).write(to: fileURL, options: .atomic)
        } catch {
            print("No se pudo guardar la biblioteca: \(error)")
        }
    }
}
