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
                .artworkChooserPopover(for: album.id, presented: $choosingArtworkFor,
                                       artist: cover.artist, album: cover.album) { data in
                    simulator.setArtwork(data, forAlbum: album.id)
                }
                .accessibilityLabel("\(cover.album), \(cover.artist), \(album.items.count) canciones")
                .accessibilityHint("Abre el álbum")
                .id(album.id)   // destino del índice A–Z
            }
        }
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

#Preview("AlbumsGridView · cuadrícula de álbumes") {
    let sim = IPodSimulator()
    return ScrollView {
        AlbumsGridView(albums: LibraryIndex.albums(sim.songs, query: ""), simulator: sim) { _ in }
    }
    .frame(width: 420, height: 500)
    .padding()
}

#Preview("AlbumArtwork · portadas") {
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
