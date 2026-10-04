//
//  IndexedSongsList.swift
//  iPodSync
//
//  Lista de canciones agrupada por letra con índice A–Z.
//

import SwiftUI
import UniformTypeIdentifiers

struct IndexedSongsList: View {
    let songs: [Song]
    let simulator: IPodSimulator
    let library: LibraryState

    private var sorted: [Song] {
        songs.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private var sections: [(letter: String, songs: [Song])] {
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

    static func letter(for title: String) -> String {
        guard let first = title.first else { return "#" }
        let folded = String(first)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .uppercased()
        guard let char = folded.first, char.isLetter, char.isASCII else { return "#" }
        return String(char)
    }

    var body: some View {
        let groups = sections
        let order = sorted.map(\.id)

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

                AlphabetIndex(available: Set(groups.map(\.letter))) { letter in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(letter, anchor: .top)
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
                        .foregroundStyle(enabled ? AnyShapeStyle(TintShapeStyle.tint) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                        .frame(width: 14)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
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
