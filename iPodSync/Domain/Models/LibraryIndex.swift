//
//  LibraryIndex.swift
//  iPodSync
//
//  Agrupa y ordena la biblioteca (Mac o iPod) por artista o por álbum en un solo lugar.
//  Antes esta lógica estaba copiada en ~7 vistas y, al buscar, recalculaba la coincidencia
//  de cada grupo dentro del `sort` (miles de veces). Aquí se calcula una vez por grupo.
//

import Foundation

// Se usa desde las vistas (hilo principal), igual que `Song.albumOrder` y `searchMatch`,
// que con el aislamiento por defecto del proyecto son del MainActor.

/// Algo que se puede listar por artista y álbum: una canción de la Mac o una pista del iPod.
protocol LibraryItem {
    var title: String { get }
    var artist: String { get }
    var album: String { get }
    func searchMatch(_ query: String) -> SearchMatch?
}

extension Song: LibraryItem {}
extension IPodTrack: LibraryItem {}

/// Un artista o un álbum con sus canciones, ya ordenadas.
struct LibraryGroup<Item: LibraryItem>: Identifiable {
    /// Clave estable: el artista, o "artista|álbum".
    let id: String
    /// Lo que se muestra y por lo que se ordena (y de donde sale la letra del índice A–Z).
    let title: String
    let items: [Item]
    /// Cuántas coinciden con la búsqueda (igual a `items.count` si no se busca).
    let matchCount: Int

    init(id: String, title: String, items: [Item], matchCount: Int? = nil) {
        self.id = id
        self.title = title
        self.items = items
        self.matchCount = matchCount ?? items.count
    }

    /// "3 de 21 coinciden" cuando la búsqueda no abarca todo el grupo.
    var matchSummary: String? {
        matchCount < items.count ? "\(matchCount) de \(items.count) coinciden" : nil
    }
}

enum LibraryIndex {

    // MARK: Mac

    static func artists(_ songs: [Song], query: String) -> [LibraryGroup<Song>] {
        groups(songs, query: query, key: { normalizedKey($0.artist) }, title: { $0.artist }, order: Song.albumOrder)
    }

    static func albums(_ songs: [Song], query: String) -> [LibraryGroup<Song>] {
        groups(songs, query: query, key: \.albumKey, title: { $0.album }, order: Song.albumOrder)
    }

    // MARK: iPod

    static func artists(_ tracks: [IPodTrack], query: String) -> [LibraryGroup<IPodTrack>] {
        groups(tracks, query: query, key: { normalizedKey($0.artist) },
               title: { $0.artist.isEmpty ? "Artista desconocido" : $0.artist },
               order: trackOrder)
    }

    /// Clave "artista|álbum" normalizada (la misma que usa `LibraryState.openIPodAlbum`).
    static func albums(_ tracks: [IPodTrack], query: String) -> [LibraryGroup<IPodTrack>] {
        groups(tracks, query: query, key: albumKey(for:),
               title: { $0.album.isEmpty ? "Sin álbum" : $0.album },
               order: trackOrder)
    }

    static func albumKey(for track: IPodTrack) -> String {
        "\(normalizedKey(track.artist))|\(normalizedKey(track.album))"
    }

    // MARK: Con búsqueda o filtro: cada grupo trae TODAS sus canciones

    /// La búsqueda (o "Sin enviar") decide QUÉ artistas o álbumes aparecen y en qué orden,
    /// pero cada uno trae todas sus canciones. Antes un artista mostraba "1 canción" (la que
    /// coincidía) y al abrirlo tenía 20; y cambiar la portada de un álbum buscado solo
    /// cambiaba las canciones que coincidían.
    static func artists(_ visible: [Song], all: [Song], query: String) -> [LibraryGroup<Song>] {
        expanding(artists(visible, query: query), visibleCount: visible.count, all: all,
                  key: { normalizedKey($0.artist) }, order: Song.albumOrder)
    }

    static func albums(_ visible: [Song], all: [Song], query: String) -> [LibraryGroup<Song>] {
        expanding(albums(visible, query: query), visibleCount: visible.count, all: all,
                  key: \.albumKey, order: Song.albumOrder)
    }

    static func artists(_ visible: [IPodTrack], all: [IPodTrack], query: String) -> [LibraryGroup<IPodTrack>] {
        expanding(artists(visible, query: query), visibleCount: visible.count, all: all,
                  key: { normalizedKey($0.artist) }, order: trackOrder)
    }

    static func albums(_ visible: [IPodTrack], all: [IPodTrack], query: String) -> [LibraryGroup<IPodTrack>] {
        expanding(albums(visible, query: query), visibleCount: visible.count, all: all,
                  key: albumKey(for:), order: trackOrder)
    }

    private static func expanding<Item: LibraryItem>(_ groups: [LibraryGroup<Item>],
                                                     visibleCount: Int,
                                                     all: [Item],
                                                     key: (Item) -> String,
                                                     order: (Item, Item) -> Bool) -> [LibraryGroup<Item>] {
        guard visibleCount != all.count else { return groups }   // sin filtro: ya están completos
        let wanted = Set(groups.map(\.id))
        var byKey: [String: [Item]] = [:]
        for item in all {
            let k = key(item)
            if wanted.contains(k) { byKey[k, default: []].append(item) }
        }
        return groups.map { group in
            LibraryGroup(id: group.id, title: group.title,
                         items: byKey[group.id]?.sorted(by: order) ?? group.items,
                         matchCount: group.items.count)
        }
    }

    // MARK: Mismo nombre, escrito distinto

    /// Junta el mismo artista o álbum aunque venga escrito distinto en las etiquetas:
    /// "Kings Of Leon", "kings of leon ", "Kings  of Leon" → "kings of leon".
    /// Antes se agrupaba por el texto exacto y un artista se partía en varios
    /// (uno con 1 canción, otro con el resto).
    static func normalizedKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// La forma de escribirlo que más se repite (para mostrar "Kings of Leon" y no la clave).
    static func mostCommon(_ names: [String]) -> String? {
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        var best: (name: String, count: Int)?
        for name in names where counts[name, default: 0] > (best?.count ?? 0) {
            best = (name, counts[name, default: 0])
        }
        return best?.name
    }

    static func trackOrder(_ a: IPodTrack, _ b: IPodTrack) -> Bool {
        (a.trackNumber, a.title) < (b.trackNumber, b.title)
    }

    // MARK: Genérico

    /// Agrupa por `key`; sin búsqueda ordena por `title`, y con búsqueda primero el grupo
    /// que mejor coincide (su rango se calcula UNA vez, no dentro del `sort`).
    static func groups<Item: LibraryItem>(_ items: [Item],
                                          query: String,
                                          key: (Item) -> String,
                                          title: (Item) -> String,
                                          order: (Item, Item) -> Bool) -> [LibraryGroup<Item>] {
        var buckets: [String: [Item]] = [:]
        var keys: [String] = []
        for item in items {
            let k = key(item)
            if buckets[k] == nil { keys.append(k) }
            buckets[k, default: []].append(item)
        }
        let groups = keys.map { k -> LibraryGroup<Item> in
            let list = buckets[k, default: []].sorted(by: order)
            // Si el nombre viene escrito de varias formas, se muestra la más común.
            return LibraryGroup(id: k, title: mostCommon(list.map(title)) ?? title(list[0]), items: list)
        }

        guard SearchMatch.isSearching(query) else {
            return groups.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
        let ranked = groups.map { group in
            (group: group, rank: group.items.compactMap { $0.searchMatch(query) }.min() ?? SearchMatch.genre)
        }
        return ranked
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.group.title.localizedCompare(b.group.title) == .orderedAscending
            }
            .map(\.group)
    }

    /// Entradas para el índice A–Z, en el mismo orden que la lista.
    static func indexEntries<Item>(_ groups: [LibraryGroup<Item>]) -> [(id: String, title: String)] {
        groups.map { (id: $0.id, title: $0.title) }
    }
}
