//
//  ArtworkLookup.swift
//  iPodSync
//
//  Busca la portada de un álbum en internet con el nombre del álbum y del artista.
//  Usa la búsqueda pública de iTunes (sin cuenta ni clave) y baja la imagen a 600 px.
//

import Foundation

nonisolated enum ArtworkLookup {
    struct Candidate: Identifiable, Hashable, Sendable {
        let id: Int
        let album: String
        let artist: String
        let year: String?
        let artworkURL: URL       // 600 × 600
        let thumbnailURL: URL     // 200 × 200, para elegir
        /// Qué tanto se parece a lo que buscamos (mayor = mejor).
        let score: Int
    }

    enum LookupError: LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let album): "No se encontró la portada de “\(album)” en internet."
            }
        }
    }

    /// Resultados ordenados del más parecido al menos parecido.
    static func search(artist: String, album: String) async throws -> [Candidate] {
        try await search(term: "\(artist) \(cleanAlbum(album))", artist: artist, album: album, limit: 12)
    }

    /// Búsquedas cada vez más amplias para "Elegir de internet…": primero artista + álbum,
    /// luego solo el álbum y al final todos los álbumes del artista.
    static func searchTerms(artist: String, album: String) -> [String] {
        let cleaned = cleanAlbum(album)
        var terms = ["\(artist) \(cleaned)", cleaned, artist]
        if cleaned != album { terms.insert("\(artist) \(album)", at: 1) }
        return terms.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Una búsqueda con un texto libre; los resultados se ordenan por parecido a artista y álbum.
    static func search(term: String, artist: String, album: String, limit: Int) async throws -> [Candidate] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "term", value: term),
            .init(name: "media", value: "music"),
            .init(name: "entity", value: "album"),
            .init(name: "limit", value: String(min(200, max(1, limit)))),
            .init(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(Response.self, from: data)

        let wantedArtist = normalize(artist)
        let wantedAlbum = normalize(cleanAlbum(album))

        return response.results.compactMap { item -> Candidate? in
            guard let name = item.collectionName, let art = item.artworkUrl100,
                  let big = URL(string: art.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
                  let small = URL(string: art.replacingOccurrences(of: "100x100bb", with: "200x200bb")) else { return nil }
            let foundArtist = normalize(item.artistName ?? "")
            let foundAlbum = normalize(cleanAlbum(name))

            var score = 0
            if foundArtist == wantedArtist { score += 4 }
            else if foundArtist.contains(wantedArtist) || wantedArtist.contains(foundArtist) { score += 2 }
            if foundAlbum == wantedAlbum { score += 4 }
            else if foundAlbum.contains(wantedAlbum) || wantedAlbum.contains(foundAlbum) { score += 2 }

            return Candidate(id: item.collectionId ?? name.hashValue,
                             album: name,
                             artist: item.artistName ?? "",
                             year: item.releaseDate.map { String($0.prefix(4)) },
                             artworkURL: big,
                             thumbnailURL: small,
                             score: score)
        }
        .sorted { $0.score > $1.score }
    }

    /// El mejor resultado solo si el artista y el álbum coinciden bien (para ponerlo sin preguntar).
    static func bestMatch(artist: String, album: String) async throws -> Candidate? {
        try await search(artist: artist, album: album).first { $0.score >= 6 }
    }

    static func download(_ candidate: Candidate) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: candidate.artworkURL)
        return data
    }

    // MARK: - Ayudantes

    /// "Kill 'Em All (Remastered)" → "Kill 'Em All".
    private static func cleanAlbum(_ album: String) -> String {
        var text = album
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    private struct Response: Decodable {
        let results: [Item]
    }

    private struct Item: Decodable {
        let collectionId: Int?
        let collectionName: String?
        let artistName: String?
        let artworkUrl100: String?
        let releaseDate: String?
    }
}
