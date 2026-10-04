//
//  SearchMatch.swift
//  iPodSync
//
//  Qué tan bien coincide una canción con lo que escribiste en el buscador.
//  Sirve para ordenar: primero las canciones que SE LLAMAN así, luego las que empiezan así,
//  después las del artista, del álbum y del género. Ignora mayúsculas y acentos.
//

import Foundation

nonisolated enum SearchMatch: Int, Comparable, Sendable {
    case titleExact      // "Echoes" = "Echoes"
    case titleStart      // "Echoes" → "Echoes (Remastered)"
    case titleWord       // "numb" → "Comfortably Numb"
    case titleContains   // "hoe" → "Echoes"
    case artist
    case album
    case genre

    static func < (a: SearchMatch, b: SearchMatch) -> Bool { a.rawValue < b.rawValue }

    /// Encabezado de la sección de resultados.
    var sectionTitle: String {
        switch self {
        case .titleExact, .titleStart, .titleWord, .titleContains: "Canciones"
        case .artist: "Por artista"
        case .album:  "Por álbum"
        case .genre:  "Por género"
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// nil = no coincide.
    static func match(_ query: String, title: String, artist: String, album: String?, genre: String?) -> SearchMatch? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }

        let t = normalize(title)
        if t == q { return .titleExact }
        if t.hasPrefix(q) { return .titleStart }
        let words = t.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(q) }) { return .titleWord }
        if t.contains(q) { return .titleContains }
        if normalize(artist).contains(q) { return .artist }
        if let album, normalize(album).contains(q) { return .album }
        if let genre, normalize(genre).contains(q) { return .genre }
        return nil
    }

    static func isSearching(_ query: String) -> Bool {
        !normalize(query).isEmpty
    }
}

extension Song {
    func searchMatch(_ query: String) -> SearchMatch? {
        SearchMatch.match(query, title: title, artist: artist, album: albumName, genre: genre)
    }
}

extension IPodTrack {
    func searchMatch(_ query: String) -> SearchMatch? {
        SearchMatch.match(query, title: title, artist: artist, album: album, genre: genre)
    }
}
