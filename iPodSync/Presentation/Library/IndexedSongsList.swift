//
//  IndexedSongsList.swift
//  iPodSync
//
//  Lista de canciones agrupada por letra con índice A–Z.
//

import SwiftUI

struct IndexedSongsList: View {
    let songs: [Song]
    let simulator: IPodSimulator
    let library: LibraryState

    private var isSearching: Bool { SearchMatch.isSearching(library.query) }

    /// Sin búsqueda: por título. Con búsqueda: primero lo que mejor coincide.
    private var sorted: [Song] {
        guard isSearching else {
            return songs.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
        let q = library.query
        let ranked: [(song: Song, rank: SearchMatch)] = songs.map { song in
            (song: song, rank: song.searchMatch(q) ?? SearchMatch.genre)
        }
        let ordered = ranked.sorted(by: Self.rankedOrder)
        return ordered.map { $0.song }
    }

    /// Mejor coincidencia primero; si empatan, por título.
    private static func rankedOrder(_ a: (song: Song, rank: SearchMatch),
                                    _ b: (song: Song, rank: SearchMatch)) -> Bool {
        if a.rank != b.rank { return a.rank < b.rank }
        return a.song.title.localizedCompare(b.song.title) == .orderedAscending
    }

    /// `sorted` se calcula una sola vez en `body` y se pasa aquí (antes se ordenaba dos veces por render).
    private func sections(_ sorted: [Song]) -> [(letter: String, songs: [Song])] {
        if isSearching {
            // Resultados: "Canciones" (por nombre), luego "Por artista", "Por álbum", "Por género".
            var result: [(letter: String, songs: [Song])] = []
            for song in sorted {
                let title = (song.searchMatch(library.query) ?? .genre).sectionTitle
                if result.last?.letter == title {
                    result[result.count - 1].songs.append(song)
                } else {
                    result.append((letter: title, songs: [song]))
                }
            }
            return result
        }
        var result: [(letter: String, songs: [Song])] = []
        for song in sorted {
            let letter = Self.letter(for: song.title)
            if result.last?.letter == letter {
                result[result.count - 1].songs.append(song)
            } else {
                result.append((letter: letter, songs: [song]))
            }
        }
        return result
    }

    /// Se crea una vez (antes una por canción en cada render).
    private static let spanish = Locale(identifier: "es")

    static func letter(for title: String) -> String {
        guard let first = title.first else { return "#" }
        let folded = String(first)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: spanish)
            .uppercased()
        guard let char = folded.first, char.isLetter, char.isASCII else { return "#" }
        return String(char)
    }

    var body: some View {
        let ordered = sorted
        let groups = sections(ordered)
        let order = ordered.map(\.id)

        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 4) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.letter) { group in
                            Section {
                                ForEach(group.songs) { song in
                                    SongRow(song: song,
                                            subtitle: song.isFileMissing ? "No se encuentra el archivo" : song.librarySubtitle,
                                            simulator: simulator,
                                            library: library,
                                            order: order)
                                    Divider().padding(.leading, 52)
                                }
                            } header: {
                                Text(group.letter)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.tint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(.thinMaterial)
                                    .id(group.letter)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                }
                .scrollIndicators(isSearching ? .automatic : .hidden)

                if !isSearching {
                    AlphabetIndex(available: Set(groups.map(\.letter))) { letter in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(letter, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}

/// ScrollView con el índice A–Z a la derecha (Artistas y Álbumes).
/// `entries`: en el orden en que se ven, el id de cada elemento (el contenido debe ponerle `.id(id)`)
/// y el texto por el que se ordena; tocar una letra lleva al primero que empieza con ella.
struct AlphabetIndexedScroll<Content: View>: View {
    let entries: [(id: String, title: String)]
    var showsIndex = true
    let content: () -> Content

    init(entries: [(id: String, title: String)], showsIndex: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.entries = entries
        self.showsIndex = showsIndex
        self.content = content
    }

    /// Letra → primer elemento que empieza con ella.
    private var firstByLetter: [String: String] {
        var result: [String: String] = [:]
        for entry in entries {
            let letter = IndexedSongsList.letter(for: entry.title)
            if result[letter] == nil { result[letter] = entry.id }
        }
        return result
    }

    var body: some View {
        let targets = firstByLetter
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 4) {
                // La cuadrícula de álbumes no tiene ancho propio: sin esto la lista se encoge
                // y queda centrada y angosta. Así ocupa todo el ancho que deja el índice.
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                // Con índice A–Z la barra de scroll sobra y se encima con las portadas.
                .scrollIndicators(showsIndex ? .hidden : .automatic)
                if showsIndex {
                    AlphabetIndex(available: Set(targets.keys)) { letter in
                        guard let id = targets[letter] else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
    }
}

/// Índice vertical A–Z; las letras sin canciones se ven apagadas.
struct AlphabetIndex: View {
    let available: Set<String>
    let onSelect: (String) -> Void

    static let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map(String.init)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.letters, id: \.self) { letter in
                let enabled = available.contains(letter)
                Button {
                    onSelect(letter)
                } label: {
                    Text(letter)
                        .font(.system(size: 8.5, weight: .semibold))
                        // Las letras sin nada van en gris (no azul), pero legibles: antes eran
                        // .tertiary y además .disabled las apagaba otra vez, y casi no se veían.
                        .foregroundStyle(enabled ? AnyShapeStyle(TintShapeStyle.tint)
                                                 : AnyShapeStyle(Color.white.opacity(0.42)))
                        .frame(width: 14)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(enabled)
                // VoiceOver solo anuncia las letras que llevan a algo.
                .accessibilityHidden(!enabled)
                .accessibilityLabel("Ir a la letra \(letter)")
            }
        }
        .frame(width: 14)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Índice alfabético")
    }
}

// MARK: - Barra de espacio

#Preview("IndexedSongsList · canciones por letra + A–Z") {
    let sim = IPodSimulator()
    return IndexedSongsList(songs: sim.songs, simulator: sim, library: LibraryState())
        .frame(width: 350, height: 420)
        .padding()
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
}

#Preview("AlphabetIndex · índice A–Z") {
    AlphabetIndex(available: ["A", "C", "D", "E", "M", "N", "P"]) { _ in }
        .frame(height: 380)
        .padding()
        .environment(\.colorScheme, .dark)
        .background(Color.black)
}
