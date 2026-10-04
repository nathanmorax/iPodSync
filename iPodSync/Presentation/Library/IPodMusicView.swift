//
//  IPodMusicView.swift
//  iPodSync
//
//  "En el iPod" con el iPod real: la música que trae, leída de su iTunesDB.
//  Respeta la vista elegida (Canciones / Artistas / Álbumes) y la búsqueda.
//

import SwiftUI
import AppKit

struct IPodMusicView: View {
    let monitor: IPodMonitor
    let scope: LibraryScope
    let query: String

    private var filtered: [IPodTrack] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return monitor.tracks }
        return monitor.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.artist.localizedCaseInsensitiveContains(q)
                || $0.album.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        if monitor.device == nil {
            ContentUnavailableView("Conecta tu iPod",
                                   systemImage: "cable.connector",
                                   description: Text("Aquí verás la música que tiene."))
        } else if !monitor.hasAccess {
            ContentUnavailableView {
                Label("Falta dar acceso al iPod", systemImage: "lock.shield")
            } description: {
                Text("Sin acceso no se puede leer su música.")
            } actions: {
                Button("Dar acceso…") { monitor.requestAccess() }
            }
        } else if monitor.isLoadingTracks {
            VStack(spacing: 10) {
                ProgressView()
                Text("Leyendo la música del iPod…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = monitor.tracksError {
            ContentUnavailableView {
                Label("No se pudo leer la música", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Volver a intentar") { monitor.reloadTracks() }
            }
        } else if monitor.tracks.isEmpty {
            ContentUnavailableView("Tu iPod no tiene música",
                                   systemImage: "music.note",
                                   description: Text("Envía canciones desde “Todas” o “Sin enviar”."))
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            list
        }
    }

    // MARK: Lista

    private var sections: [(key: String, tracks: [IPodTrack])] {
        switch scope {
        case .songs:
            return group(filtered) { IndexedSongsList.letter(for: $0.title) }
        case .artists:
            return group(filtered.sorted { ($0.artist, $0.album, $0.trackNumber) < ($1.artist, $1.album, $1.trackNumber) }) { $0.artist }
        case .albums:
            return group(filtered.sorted { ($0.album, $0.trackNumber, $0.title) < ($1.album, $1.trackNumber, $1.title) }) {
                $0.album.isEmpty ? "Sin álbum" : $0.album
            }
        }
    }

    private func group(_ tracks: [IPodTrack], by key: (IPodTrack) -> String) -> [(key: String, tracks: [IPodTrack])] {
        var result: [(key: String, tracks: [IPodTrack])] = []
        var index: [String: Int] = [:]
        for track in tracks {
            let k = key(track)
            if let i = index[k] {
                result[i].tracks.append(track)
            } else {
                index[k] = result.count
                result.append((key: k, tracks: [track]))
            }
        }
        if scope != .songs {
            result.sort { $0.key.localizedCompare($1.key) == .orderedAscending }
        }
        return result
    }

    private var list: some View {
        let groups = sections
        return ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 4) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.key) { group in
                            Section {
                                ForEach(group.tracks) { track in
                                    IPodTrackRow(track: track, subtitle: subtitle(for: track), artwork: monitor.artwork)
                                    Divider().padding(.leading, 52)
                                }
                            } header: {
                                header(group.key, count: group.tracks.count)
                                    .id(group.key)
                            }
                        }
                    }
                }

                if scope == .songs {
                    AlphabetIndex(available: Set(groups.map(\.key))) { letter in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(letter, anchor: .top) }
                    }
                }
            }
        }
    }

    private func subtitle(for track: IPodTrack) -> String {
        switch scope {
        case .songs:   return track.album.isEmpty ? track.artist : "\(track.artist) · \(track.album)"
        case .artists: return track.album.isEmpty ? track.sizeText : track.album
        case .albums:  return track.artist
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: scope == .songs ? 11 : 12, weight: .bold))
                .foregroundStyle(scope == .songs ? AnyShapeStyle(TintShapeStyle.tint) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .lineLimit(1)
            Spacer()
            if scope != .songs {
                Text(count == 1 ? "1 canción" : "\(count) canciones")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, scope == .songs ? 4 : 6)
        .background(.thinMaterial)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Fila de una canción del iPod.
struct IPodTrackRow: View {
    let track: IPodTrack
    let subtitle: String
    var artwork: IPodArtworkStore? = nil

    var body: some View {
        HStack(spacing: 10) {
            IPodArtworkView(track: track, artwork: artwork, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if track.playCount > 0 {
                Text("\(track.playCount)×")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .help("Reproducciones en el iPod")
            }
            Text(track.durationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copiar título") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(track.title) — \(track.artist)", forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(subtitle), \(track.durationText)")
    }
}

/// Portada de una canción del iPod. Mientras carga (o si no tiene) muestra un color con una nota.
struct IPodArtworkView: View {
    let track: IPodTrack
    let artwork: IPodArtworkStore?
    var size: CGFloat = 30

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Color(hue: track.artworkHue, saturation: 0.40, brightness: 0.86),
                                        Color(hue: track.artworkHue, saturation: 0.62, brightness: 0.64)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.37, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
        .task(id: track.dbid) {
            guard let artwork else { return }
            let loaded = await artwork.image(for: track.dbid)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}

#Preview("IPodTrackRow · canción del iPod") {
    IPodTrackRow(track: IPodTrack(id: 1, title: "Afuera", artist: "Caifanes", album: "El Silencio",
                                  genre: "Rock", location: ":iPod_Control:Music:F01:ABCD.mp3",
                                  sizeBytes: 7_800_000, durationMs: 287_000, trackNumber: 3,
                                  year: 1992, playCount: 41, rating: 5),
                 subtitle: "Caifanes · El Silencio")
        .frame(width: 360)
        .padding()
}
