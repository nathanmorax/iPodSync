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

    /// Aviso pendiente si la biblioteca guardada no se pudo leer (lo muestra IPodMonitor.start).
    nonisolated(unsafe) private static var pendingProblem: String?

    /// Devuelve el aviso (una sola vez).
    static func takeLoadProblem() -> String? {
        defer { pendingProblem = nil }
        return pendingProblem
    }

    static func load() -> [Song] {
        // Sin archivo = biblioteca nueva, vacía.
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoded: [Song]
        do {
            decoded = try JSONDecoder().decode([Song].self, from: data)
        } catch {
            // Antes se cargaba vacía sin avisar y el siguiente guardado borraba la biblioteca.
            // Ahora el archivo se aparta (no se pierde) y se avisa.
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("library-no-se-pudo-leer-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            pendingProblem = "No se pudo leer tu biblioteca guardada (\(error.localizedDescription)). "
                + "Se guardó una copia como “\(aside.lastPathComponent)” y empezamos con la biblioteca vacía."
            print("Biblioteca: \(error)")
            return []
        }
        var songs = decoded

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
