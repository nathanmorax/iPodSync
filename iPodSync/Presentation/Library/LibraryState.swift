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
            openIPodAlbum = nil
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey)
        }
    }
    /// Qué se ve: la música de la Mac o la del iPod.
    var source: LibrarySource = .mac {
        didSet {
            guard source != oldValue else { return }
            selectedAlbumID = nil
            openIPodAlbum = nil
            clearSelection()
        }
    }
    var query = ""
    /// Filtro por estado en la Mac: Todas o Sin enviar.
    var statusFilter: LibraryStatusFilter = .all
    /// Se incrementa con ⌘F para pedir el foco del buscador del panel.
    var searchFocusRequest = 0
    var selectedAlbumID: Song.ID?
    /// Álbum abierto en "En el iPod" (clave artista|álbum).
    var openIPodAlbum: String?
    /// Artistas cerrados en la vista Artistas (Mac y iPod por separado).
    var collapsedArtists: Set<String> = []
    var collapsedIPodArtists: Set<String> = []
    var isImporting = false

    /// Canciones seleccionadas con clic, ⌘‑clic o ⇧‑clic.
    var selection: Set<Song.ID> = []
    private var anchor: Song.ID?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.scopeKey)
        scope = saved.flatMap(LibraryScope.init(rawValue:)) ?? .artists
    }

    /// Abre o cierra un artista. Con ⌥ (Opción) abre o cierra todos, como en el Finder.
    func toggleArtist(_ name: String,
                      in keyPath: ReferenceWritableKeyPath<LibraryState, Set<String>>,
                      all names: [String]) {
        let collapse = !self[keyPath: keyPath].contains(name)
        if NSEvent.modifierFlags.contains(.option) {
            self[keyPath: keyPath] = collapse ? Set(names) : []
        } else if collapse {
            self[keyPath: keyPath].insert(name)
        } else {
            self[keyPath: keyPath].remove(name)
        }
    }

    func filter(_ songs: [Song]) -> [Song] {
        guard SearchMatch.isSearching(query) else { return songs }
        // Busca en título, artista, álbum y género (sin importar mayúsculas ni acentos).
        return songs.filter { $0.searchMatch(query) != nil }
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
