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
    private static let scopeKey = SettingsKey.libraryScope

    var scope: LibraryScope {
        didSet {
            selectedAlbumID = nil
            openIPodAlbum = nil
            openArtist = nil
            openIPodArtist = nil
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey)
        }
    }
    /// Qué se ve: la música de la Mac o la del iPod.
    var source: LibrarySource = .mac {
        didSet {
            guard source != oldValue else { return }
            selectedAlbumID = nil
            openIPodAlbum = nil
            openArtist = nil
            openIPodArtist = nil
            clearSelection()
        }
    }
    var query = "" {
        didSet {
            // Al empezar una búsqueda nueva, adentro de un artista o álbum se ven solo
            // las coincidencias (como iTunes); con un clic se ven todas.
            if query.isEmpty != oldValue.isEmpty { detailShowsOnlyMatches = true }
        }
    }
    /// Dentro de un artista o álbum, mientras buscas: solo las canciones que coinciden.
    var detailShowsOnlyMatches = true
    /// Filtro por estado en la Mac: Todas o Sin enviar.
    var statusFilter: LibraryStatusFilter = .all
    /// Se incrementa con ⌘F para pedir el foco del buscador del panel.
    var searchFocusRequest = 0
    var selectedAlbumID: Song.ID?
    /// Artista abierto (su página) en la Mac y en el iPod.
    var openArtist: String?
    var openIPodArtist: String?
    /// Álbum abierto en "En el iPod" (clave artista|álbum).
    var openIPodAlbum: String?
    var isImporting = false

    /// Canciones seleccionadas con clic, ⌘‑clic o ⇧‑clic.
    var selection: Set<Song.ID> = []
    @ObservationIgnored private var anchor: Song.ID?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.scopeKey)
        scope = saved.flatMap(LibraryScope.init(rawValue:)) ?? .artists
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

    // MARK: Selección en "En mi iPod" (iPod real: las canciones tienen ID del iPod)

    var iPodSelection: Set<UInt32> = []
    @ObservationIgnored private var iPodAnchor: UInt32?

    /// Igual que `click`: clic = una, ⌘‑clic = agregar/quitar, ⇧‑clic = rango.
    func clickIPod(_ id: UInt32, in order: [UInt32]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if iPodSelection.contains(id) { iPodSelection.remove(id) } else { iPodSelection.insert(id) }
            iPodAnchor = id
        } else if flags.contains(.shift), let iPodAnchor,
                  let a = order.firstIndex(of: iPodAnchor), let b = order.firstIndex(of: id) {
            iPodSelection.formUnion(order[min(a, b)...max(a, b)])
        } else {
            iPodSelection = [id]
            iPodAnchor = id
        }
    }

    func clearIPodSelection() {
        iPodSelection.removeAll()
        iPodAnchor = nil
    }
}
