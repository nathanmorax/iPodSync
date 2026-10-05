//
//  ArtistViews.swift
//  iPodSync
//
//  Artistas como cuadrícula de círculos (3 por fila). Al tocar uno se abre su página:
//  sus álbumes en fila y abajo sus canciones. Versión para la Mac y para el iPod.
//

import SwiftUI

// MARK: - Piezas comunes

/// Círculo + nombre + cuántas canciones (una celda de la cuadrícula de artistas).
struct ArtistCell<Artwork: View>: View {
    let name: String
    let count: Int
    let artwork: Artwork

    init(name: String, count: Int, @ViewBuilder artwork: () -> Artwork) {
        self.name = name
        self.count = count
        self.artwork = artwork()
    }

    var body: some View {
        VStack(spacing: 5) {
            artwork
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .padding(.horizontal, 6)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(count == 1 ? "1 canción" : "\(count) canciones")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// Encabezado de la página de un artista: "‹ Artistas", círculo grande, nombre y totales.
struct ArtistPageHeader<Artwork: View, Accessory: View>: View {
    let name: String
    let albumCount: Int
    let songCount: Int
    let onBack: () -> Void
    let artwork: Artwork
    let accessory: Accessory

    init(name: String, albumCount: Int, songCount: Int, onBack: @escaping () -> Void,
         @ViewBuilder artwork: () -> Artwork, @ViewBuilder accessory: () -> Accessory) {
        self.name = name
        self.albumCount = albumCount
        self.songCount = songCount
        self.onBack = onBack
        self.artwork = artwork()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onBack) {
                Label("Artistas", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("Volver a Artistas (⌘[)")

            HStack(spacing: 12) {
                artwork
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(albumCount) \(albumCount == 1 ? "álbum" : "álbumes") · \(songCount) \(songCount == 1 ? "canción" : "canciones")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                accessory
            }
        }
    }
}

/// Encabezado de un álbum dentro de la página del artista: portada, nombre, año y canciones.
struct ArtistAlbumSectionHeader<Artwork: View, Accessory: View>: View {
    let title: String
    let year: Int?
    let songCount: Int
    let artwork: Artwork
    let accessory: Accessory

    init(title: String, year: Int?, songCount: Int,
         @ViewBuilder artwork: () -> Artwork, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.year = year
        self.songCount = songCount
        self.artwork = artwork()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(2)
                Text([year.map(String.init), songCount == 1 ? "1 canción" : "\(songCount) canciones"]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Solo el título y el año se leen juntos como encabezado; el botón "Enviar" queda aparte.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            accessory
        }
        .padding(.top, 4)
    }
}

// MARK: - Mac

struct ArtistsGridView: View {
    /// Artistas ya agrupados y ordenados (LibraryIndex.artists), calculados una vez en el panel.
    let groups: [LibraryGroup<Song>]
    let simulator: IPodSimulator
    let onOpen: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
            ForEach(groups) { group in
                let cover = group.items.first(where: { $0.artworkData != nil }) ?? group.items[0]
                Button { onOpen(group.id) } label: {
                    ArtistCell(name: group.title, count: group.items.count) {
                        SongArtworkView(song: cover, size: nil, cornerRadius: 0)
                    }
                }
                .buttonStyle(.plain)
                .help(group.title)
                .contextMenu {
                    let sendable = group.items.filter(simulator.canSend).map(\.id)
                    Button("Enviar \(sendable.count) al iPod") { simulator.sendAll(sendable) }
                        .disabled(sendable.isEmpty)
                }
                .id(group.id)   // destino del índice A–Z
                .accessibilityLabel("\(group.title), \(group.items.count) canciones")
                .accessibilityHint("Abre el artista")
            }
        }
        .padding(.top, 2)
    }
}

struct ArtistDetailView: View {
    /// Clave normalizada del artista (LibraryIndex.normalizedKey).
    let artist: String
    let simulator: IPodSimulator
    let library: LibraryState
    let onBack: () -> Void

    private var tracks: [Song] {
        simulator.songs.filter { LibraryIndex.normalizedKey($0.artist) == artist }.sorted(by: Song.albumOrder)
    }

    /// Álbumes del artista, del más nuevo al más viejo.
    private func albums(_ tracks: [Song]) -> [[Song]] {
        Dictionary(grouping: tracks, by: \.albumKey).values
            .map { $0.sorted(by: Song.albumOrder) }
            .sorted { a, b in
                let ya = a[0].year ?? 0, yb = b[0].year ?? 0
                if ya != yb { return ya > yb }
                return a[0].album.localizedCompare(b[0].album) == .orderedAscending
            }
    }

    var body: some View {
        let list = tracks
        let groups = albums(list)
        let cover = list.first(where: { $0.artworkData != nil }) ?? list.first
        let artistMissing = list.filter { simulator.status(of: $0) != .onDevice }.count

        VStack(alignment: .leading, spacing: 14) {
            ArtistPageHeader(name: LibraryIndex.mostCommon(list.map(\.artist)) ?? artist,
                             albumCount: groups.count, songCount: list.count, onBack: onBack) {
                if let cover { SongArtworkView(song: cover, size: 56, cornerRadius: 0) }
            } accessory: {
                SendSongsButton(songs: list, simulator: simulator, compact: true,
                                help: "Enviar al iPod las canciones de \(artist) que faltan")
            }

            // Como Apple Music (Biblioteca › Artistas): cada álbum con su portada de encabezado
            // y sus canciones abajo. Todo a la vista, sin abrir nada ni cambiar de pestaña.
            let order = groups.flatMap { $0.map(\.id) }
            ForEach(groups, id: \.first!.albumKey) { songs in
                let first = songs.first(where: { $0.artworkData != nil }) ?? songs[0]
                let albumMissing = songs.filter { simulator.status(of: $0) != .onDevice }.count
                VStack(alignment: .leading, spacing: 6) {
                    ArtistAlbumSectionHeader(title: first.album, year: first.year, songCount: songs.count) {
                        SongArtworkView(song: first, size: 56, cornerRadius: 0)
                    } accessory: {
                        // Por álbum solo si al artista le falta más que este álbum (si no, basta el de arriba).
                        if albumMissing > 0 && albumMissing < artistMissing {
                            SendSongsButton(songs: songs, simulator: simulator, prominent: false, compact: true,
                                            help: "Enviar al iPod las canciones de este álbum que faltan")
                        }
                    }
                    .contextMenu {
                        AlbumArtworkMenu(songs: songs, simulator: simulator)
                    }
                    LibraryCard {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            if index > 0 { Divider().padding(.leading, 42) }
                            SongRow(song: song,
                                    subtitle: song.durationText ?? song.sizeText,
                                    simulator: simulator, library: library, order: order,
                                    number: song.trackNumber ?? index + 1)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}
