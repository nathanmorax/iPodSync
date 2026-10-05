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
}

enum LibraryIndex {

    // MARK: Mac

    static func artists(_ songs: [Song], query: String) -> [LibraryGroup<Song>] {
        groups(songs, query: query, key: \.artist, title: { $0.artist }, order: Song.albumOrder)
    }

    static func albums(_ songs: [Song], query: String) -> [LibraryGroup<Song>] {
        groups(songs, query: query, key: \.albumKey, title: { $0.album }, order: Song.albumOrder)
    }

    // MARK: iPod

    static func artists(_ tracks: [IPodTrack], query: String) -> [LibraryGroup<IPodTrack>] {
        groups(tracks, query: query, key: \.artist,
               title: { $0.artist.isEmpty ? "Artista desconocido" : $0.artist },
               order: trackOrder)
    }

    /// Clave "artista|álbum" (la misma que usa `LibraryState.openIPodAlbum`).
    static func albums(_ tracks: [IPodTrack], query: String) -> [LibraryGroup<IPodTrack>] {
        groups(tracks, query: query, key: { "\($0.artist)|\($0.album)" },
               title: { $0.album.isEmpty ? "Sin álbum" : $0.album },
               order: trackOrder)
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
            return LibraryGroup(id: k, title: title(list[0]), items: list)
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
