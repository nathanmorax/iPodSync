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
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
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
        Dictionary(grouping: songs, by: \.artist)
            .map { (artist: $0.key, songs: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.artist.localizedCompare($1.artist) == .orderedAscending }
    }

    var body: some View {
        let order = groups.flatMap { $0.songs.map(\.id) }
        LibraryCard {
            ForEach(Array(groups.enumerated()), id: \.element.artist) { index, group in
                if index > 0 { Divider() }
                ArtistHeader(name: group.artist,
                             count: group.songs.count,
                             hue: group.songs.first?.artworkHue ?? 0)
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

struct ArtistHeader: View {
    let name: String
    let count: Int
    let hue: Double

    var body: some View {
        HStack(spacing: 8) {
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
        .background(Theme.groupHeader)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Álbumes

struct AlbumsGridView: View {
    let songs: [Song]
    let simulator: IPodSimulator
    let onOpen: (Song) -> Void

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 14)]

    /// Un cuadro por álbum (mismo álbum y artista), no uno por canción.
    private var albums: [(key: String, songs: [Song])] {
        Dictionary(grouping: songs, by: \.albumKey)
            .map { (key: $0.key, songs: $0.value.sorted(by: Song.albumOrder)) }
            .sorted { $0.songs[0].album.localizedCompare($1.songs[0].album) == .orderedAscending }
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(albums, id: \.key) { album in
                let cover = album.songs[0]
                Button { onOpen(cover) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        AlbumArtwork(song: cover, status: Self.albumStatus(album.songs, simulator))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cover.album)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(album.songs.count == 1 ? cover.artist : "\(cover.artist) · \(album.songs.count) canciones")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    let sendable = album.songs.filter(simulator.canSend).map(\.id)
                    Button(album.songs.count == 1 ? "Enviar al iPod" : "Enviar álbum al iPod (\(sendable.count))") {
                        simulator.sendAll(sendable)
                    }
                    .disabled(sendable.isEmpty)
                }
                .accessibilityLabel("\(cover.album), \(cover.artist), \(album.songs.count) canciones")
                .accessibilityHint("Abre el álbum")
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
    let status: SongSyncStatus

    var body: some View {
        SongArtworkView(song: song, size: nil, cornerRadius: 8)
            .overlay(alignment: .bottomLeading) {
                Text(song.artworkData == nil ? Song.initials(of: song.album) : "")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                badge.padding(6)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .onDevice:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .font(.system(size: 16))
        case .sending(let p):
            Text("\(Int(p * 100)) %")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        case .queued:
            Image(systemName: "clock.fill")
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.35), in: Circle())
        case .notOnDevice:
            EmptyView()
        }
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
        let sendable = list.filter(simulator.canSend).map(\.id)

        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) {
                Label("Álbumes", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("Volver a Álbumes (⌘[)")

            HStack(alignment: .bottom, spacing: 16) {
                SongArtworkView(song: list.first(where: { $0.artworkData != nil }) ?? song, size: 120, cornerRadius: 10)
                    .shadow(color: .black.opacity(0.16), radius: 9, y: 6)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.album)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(details)
                        .foregroundStyle(.secondary)
                    if !sendable.isEmpty {
                        Button(list.count == 1 ? "Enviar al iPod" : "Enviar \(sendable.count) al iPod") {
                            simulator.sendAll(sendable)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                    }
                }
            }

            LibraryCard {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                    if index > 0 { Divider().padding(.leading, 52) }
                    SongRow(song: track,
                            subtitle: ["\(track.trackNumber ?? index + 1)", track.durationText ?? track.sizeText]
                                .joined(separator: " · "),
                            simulator: simulator, library: library, order: list.map(\.id))
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
        AlbumsGridView(songs: sim.songs, simulator: sim) { _ in }
    }
    .frame(width: 420, height: 500)
    .padding()
}

#Preview("AlbumArtwork · portada con estados") {
    HStack(spacing: 12) {
        AlbumArtwork(song: MockLibrary.songs[0], status: .onDevice)
        AlbumArtwork(song: MockLibrary.songs[1], status: .sending(0.48))
        AlbumArtwork(song: MockLibrary.songs[2], status: .queued)
        AlbumArtwork(song: MockLibrary.songs[4], status: .notOnDevice)
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
