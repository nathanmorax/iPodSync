//
//  LibraryState.swift
//  iPodSync
//
//  Estado de navegación de la biblioteca: vista activa, búsqueda, álbum abierto y selección.
//

import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class LibraryState {
    private static let scopeKey = "libraryScope"

    var scope: LibraryScope {
        didSet {
            selectedAlbumID = nil
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey)
        }
    }
    var query = ""
    var selectedAlbumID: Song.ID?
    var isImporting = false

    /// Canciones seleccionadas con clic, ⌘‑clic o ⇧‑clic.
    var selection: Set<Song.ID> = []
    private var anchor: Song.ID?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.scopeKey)
        scope = saved.flatMap(LibraryScope.init(rawValue:)) ?? .artists
    }

    func filter(_ songs: [Song]) -> [Song] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q)
        }
    }

    /// Selección como en el Finder: clic = una, ⌘‑clic = agregar/quitar, ⇧‑clic = rango.
    func click(_ id: Song.ID, in order: [Song.ID]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else if flags.contains(.shift), let anchor,
                  let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) {
            selection.formUnion(order[min(a, b)...max(a, b)])
        } else {
            selection = [id]
            anchor = id
        }
    }

    func clearSelection() {
        selection.removeAll()
        anchor = nil
    }
}
