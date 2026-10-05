//
//  LibraryLists.swift
//  iPodSync
//
//  Las tres vistas de la biblioteca: Canciones, Artistas y Álbumes (+ detalle de álbum).
//

import SwiftUI

// MARK: - Tarjeta contenedora (lista agrupada estilo macOS)

struct LibraryCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            // Sin fondo propio: se ve el vidrio del panel, igual que la lista de "En el iPod".
    }
}

// MARK: - Canciones

struct SongsListView: View {
    let songs: [Song]
    let simulator: IPodSimulator
    let library: LibraryState

    private var sorted: [Song] {
        songs.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        LibraryCard {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, song in
                if index > 0 { Divider().padding(.leading, 52) }
                SongRow(song: song,
                        subtitle: song.librarySubtitle,
                        simulator: simulator,
                        library: library,
                        order: sorted.map(\.id))
            }
        }
    }
}

// MARK: - Artistas

struct ArtistsListView: View {
    let songs: [Song]
    let simulator: IPodSimulator
    let library: LibraryState

    private var groups: [(artist: String, songs: [Song])] {
        let q = library.query
        let grouped = Dictionary(grouping: songs, by: \.artist)
            .map { (artist: $0.key, songs: $0.value.sorted { $0.title < $1.title }) }
        guard SearchMatch.isSearching(q) else {
            return grouped.sorted { $0.artist.localizedCompare($1.artist) == .orderedAscending }
        }
        // Con búsqueda: primero el artista con la mejor coincidencia (p. ej. la canción que se llama así).
        func rank(_ song: Song) -> SearchMatch { song.searchMatch(q) ?? SearchMatch.genre }
        func best(_ songs: [Song]) -> SearchMatch { songs.map(rank).min() ?? SearchMatch.genre }

        var result: [(artist: String, songs: [Song])] = []
        for group in grouped {
            let ordered = group.songs.sorted { rank($0) < rank($1) }
            result.append((artist: group.artist, songs: ordered))
        }
        result.sort { a, b in
            let rankA = best(a.songs), rankB = best(b.songs)
            if rankA != rankB { return rankA < rankB }
            return a.artist.localizedCompare(b.artist) == .orderedAscending
        }
        return result
    }

    var body: some View {
        let all = groups
        let names = all.map(\.artist)
        // Mientras buscas, todos los artistas se ven abiertos para que aparezcan los resultados.
        let searching = !library.query.trimmingCharacters(in: .whitespaces).isEmpty
        let order = all.filter { searching || library.expandedArtists.contains($0.artist) }.flatMap { $0.songs.map(\.id) }
        LibraryCard {
            ForEach(Array(all.enumerated()), id: \.element.artist) { index, group in
                let expanded = searching || library.expandedArtists.contains(group.artist)
                if index > 0 { Divider() }
                ArtistHeader(name: group.artist,
                             count: group.songs.count,
                             hue: group.songs.first?.artworkHue ?? 0,
                             isExpanded: expanded) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        library.toggleArtist(group.artist, in: \.expandedArtists, all: names)
                    }
                }
                .id(group.artist)   // destino del índice A–Z
                if expanded {
                    Divider()
                    ForEach(Array(group.songs.enumerated()), id: \.element.id) { i, song in
                        if i > 0 { Divider().padding(.leading, 78) }
                        SongRow(song: song, subtitle: [song.albumName, song.durationText ?? song.sizeText].compactMap { $0 }.joined(separator: " · "), indented: true,
                                simulator: simulator, library: library, order: order)
                    }
                }
            }
        }
    }
}

struct ArtistHeader: View {
    let name: String
    let count: Int
    let hue: Double
    var isExpanded = true
    /// Si hay acción, el encabezado abre y cierra el artista (⌥ clic: todos).
    var onToggle: (() -> Void)? = nil

    var body: some View {
        if let onToggle {
            Button(action: onToggle) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help(isExpanded ? "Cerrar (⌥ clic: cerrar todos)" : "Abrir (⌥ clic: abrir todos)")
                .accessibilityValue(isExpanded ? "Abierto" : "Cerrado")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            if onToggle != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
                    .accessibilityHidden(true)
            }
            Text(Song.initials(of: name))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.55)))
                .accessibilityHidden(true)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(count == 1 ? "1 canción" : "\(count) canciones")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Álbumes

struct AlbumsGridView: View {
    /// Álbumes ya agrupados y ordenados (LibraryIndex.albums), calculados una vez en el panel.
    let albums: [LibraryGroup<Song>]
    let simulator: IPodSimulator
    let onOpen: (Song) -> Void

    @AppStorage(SettingsKey.albumColumns) private var columnCount = 2
    /// Álbum con la ventanita "Elegir de internet…" abierta.
    @State private var choosingArtworkFor: String?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: max(2, min(3, columnCount)))
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(albums) { album in
                let cover = album.items[0]
                Button { onOpen(cover) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        AlbumArtwork(song: cover)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cover.album)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(album.items.count == 1 ? cover.artist : "\(cover.artist) · \(album.items.count) canciones")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(cover.album) — \(cover.artist)")
                .contextMenu {
                    let sendable = album.items.filter(simulator.canSend).map(\.id)
                    Button(album.items.count == 1 ? "Enviar al iPod" : "Enviar álbum al iPod (\(sendable.count))") {
                        simulator.sendAll(sendable)
                    }
                    .disabled(sendable.isEmpty)
                    Divider()
                    Button("Elegir de internet…", systemImage: "square.grid.2x2") { choosingArtworkFor = album.id }
                    AlbumArtworkMenu(songs: album.items, simulator: simulator)
                }
                .popover(isPresented: Binding(get: { choosingArtworkFor == album.id },
                                              set: { if !$0 { choosingArtworkFor = nil } }),
                         arrowEdge: .trailing) {
                    OnlineArtworkChooser(artist: cover.artist, album: cover.album) { data in
                        simulator.setArtwork(data, forAlbum: album.id)
                        choosingArtworkFor = nil
                    }
                }
                .accessibilityLabel("\(cover.album), \(cover.artist), \(album.items.count) canciones")
                .accessibilityHint("Abre el álbum")
                .id(album.id)   // destino del índice A–Z
            }
        }
    }

    /// Estado del álbum: enviando si alguna se envía, en el iPod si todas están, en cola si alguna espera.
    static func albumStatus(_ songs: [Song], _ simulator: IPodSimulator) -> SongSyncStatus {
        let statuses = songs.map(simulator.status(of:))
        for status in statuses {
            if case .sending = status { return status }
        }
        if statuses.allSatisfy({ $0 == .onDevice }) { return .onDevice }
        if statuses.contains(.queued) { return .queued }
        return .notOnDevice
    }
}

struct AlbumArtwork: View {
    let song: Song

    var body: some View {
        SongArtworkView(song: song, size: nil, cornerRadius: 8)
            .overlay(alignment: .bottomLeading) {
                Text(song.artworkData == nil ? Song.initials(of: song.album) : "")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(8)
            }

            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

struct AlbumDetailView: View {
    /// Cualquier canción del álbum; se muestran todas las que comparten álbum y artista.
    let song: Song
    let simulator: IPodSimulator
    let library: LibraryState
    let onBack: () -> Void

    private var tracks: [Song] {
        simulator.songs.filter { $0.albumKey == song.albumKey }.sorted(by: Song.albumOrder)
    }

    private var details: String {
        let total = tracks.compactMap(\.durationSeconds).reduce(0, +)
        let minutes = Int((total / 60).rounded())
        return [song.artist,
                song.albumName == nil ? "Sencillo" : song.year.map(String.init),
                tracks.count == 1 ? "1 canción" : "\(tracks.count) canciones",
                total > 0 ? "\(minutes) min" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let list = tracks

        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) {
                Label("Álbumes", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("Volver a Álbumes (⌘[)")

            HStack(alignment: .bottom, spacing: 16) {
                EditableAlbumCover(songs: list, fallback: song, simulator: simulator)

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.album)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(details)
                        .foregroundStyle(.secondary)
                    SendSongsButton(songs: list, simulator: simulator)
                        .padding(.top, 6)
                }
            }

            LibraryCard {
                // Igual que en la página del artista: número, título y duración a la derecha.
                ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                    if index > 0 { Divider().padding(.leading, 42) }
                    SongRow(song: track,
                            subtitle: track.durationText ?? track.sizeText,
                            simulator: simulator, library: library, order: list.map(\.id),
                            number: track.trackNumber ?? index + 1)
                }
            }
        }
    }
}

#Preview("LibraryCard · tarjeta contenedora") {
    LibraryCard {
        Text("Contenido").padding()
        Divider()
        Text("Más contenido").padding()
    }
    .frame(width: 300)
    .padding()
}

#Preview("SongsListView · lista de canciones") {
    let sim = IPodSimulator()
    return ScrollView {
        SongsListView(songs: sim.songs, simulator: sim, library: LibraryState())
    }
    .frame(width: 420, height: 500)
    .padding()
}

#Preview("ArtistsListView · agrupado por artista") {
    let sim = IPodSimulator()
    return ScrollView {
        ArtistsListView(songs: sim.songs, simulator: sim, library: LibraryState())
    }
    .frame(width: 420, height: 500)
    .padding()
}

#Preview("ArtistHeader · encabezado de artista") {
    ArtistHeader(name: "Natalia Lafourcade", count: 2, hue: 0.84)
        .frame(width: 360)
        .padding()
}

#Preview("AlbumsGridView · cuadrícula de álbumes") {
    let sim = IPodSimulator()
    return ScrollView {
        AlbumsGridView(albums: LibraryIndex.albums(sim.songs, query: ""), simulator: sim) { _ in }
    }
    .frame(width: 420, height: 500)
    .padding()
}

#Preview("AlbumArtwork · portada con estados") {
    HStack(spacing: 12) {
        AlbumArtwork(song: MockLibrary.songs[0])
        AlbumArtwork(song: MockLibrary.songs[1])
        AlbumArtwork(song: MockLibrary.songs[2])
        AlbumArtwork(song: MockLibrary.songs[4])
    }
    .frame(height: 110)
    .padding()
}

#Preview("AlbumDetailView · detalle de álbum") {
    let sim = IPodSimulator()
    return AlbumDetailView(song: sim.songs[1], simulator: sim, library: LibraryState()) {}
        .frame(width: 420)
        .padding()
}
