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
                        subtitle: "\(song.artist) · \(song.sizeText)",
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
                    SongRow(song: song, subtitle: song.sizeText, indented: true,
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

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(songs.sorted { $0.album < $1.album }) { song in
                Button { onOpen(song) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        AlbumArtwork(song: song, status: simulator.status(of: song))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.album)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .draggable(song.id.uuidString)
                .contextMenu { SongContextMenu(song: song, simulator: simulator) }
                .accessibilityLabel("\(song.album), \(song.artist)")
                .accessibilityHint("Abre el álbum")
            }
        }
    }
}

struct AlbumArtwork: View {
    let song: Song
    let status: SongSyncStatus

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(song.artworkGradient)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                Text(Song.initials(of: song.album))
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
    let song: Song
    let simulator: IPodSimulator
    let library: LibraryState
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) {
                Label("Álbumes", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("Volver a Álbumes (⌘[)")

            HStack(alignment: .bottom, spacing: 16) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(song.artworkGradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.16), radius: 9, y: 6)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.album)
                        .font(.title2.weight(.bold))
                    Text("\(song.artist) · Sencillo · \(song.sizeText)")
                        .foregroundStyle(.secondary)
                    if simulator.canSend(song) {
                        Button("Enviar al iPod") { simulator.send(song.id) }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                    }
                }
            }

            LibraryCard {
                SongRow(song: song, subtitle: "1 · \(song.sizeText)",
                        simulator: simulator, library: library, order: [song.id])
            }
        }
    }
}
