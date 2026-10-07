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
    let library: LibraryState
    let scope: LibraryScope
    let query: String

    @AppStorage(SettingsKey.albumColumns) private var columnCount = 2
    /// Álbum con la ventanita "Elegir de internet…" abierta.
    @State private var choosingArtworkFor: String?

    private var filtered: [IPodTrack] {
        guard isSearching else { return monitor.tracks }
        // Con búsqueda: solo lo que coincide, y primero lo que mejor coincide.
        var ranked: [(track: IPodTrack, rank: SearchMatch)] = []
        for track in monitor.tracks {
            if let rank = track.searchMatch(query) { ranked.append((track: track, rank: rank)) }
        }
        ranked.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            return a.track.title.localizedCompare(b.track.title) == .orderedAscending
        }
        return ranked.map { $0.track }
    }

    private var isSearching: Bool { SearchMatch.isSearching(query) }

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
        } else if scope == .albums {
            if let key = library.openIPodAlbum, let album = albums.first(where: { $0.key == key }) {
                albumDetail(album)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                albumsGrid
                    .transition(.opacity)
            }
        } else if scope == .artists {
            if let key = library.openIPodArtist,
               monitor.tracks.contains(where: { LibraryIndex.normalizedKey($0.artist) == key }) {
                artistPage(key)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                artistsGrid
                    .transition(.opacity)
            }
        } else {
            list
        }
    }

    // MARK: Selección y eliminar

    /// Fila con selección (clic, ⌘‑clic, ⇧‑clic) y clic derecho › Eliminar del iPod…
    private func row(_ track: IPodTrack, subtitle: String, number: Int? = nil,
                     isMatch: Bool = false, order: [UInt32]) -> some View {
        let selected = library.iPodSelection.contains(track.id)
        let several = selected && library.iPodSelection.count > 1
        return IPodTrackRow(track: track, subtitle: subtitle, artwork: monitor.artwork,
                            number: number, isMatch: isMatch, isSelected: selected,
                            isDeleting: monitor.deletingTrackIDs.contains(track.id),
                            deleteTitle: several ? "Eliminar \(library.iPodSelection.count) canciones del iPod…" : "Eliminar del iPod…",
                            onDelete: { deleteTracks(several ? selectedTracks : [track]) })
            .onTapGesture { library.clickIPod(track.id, in: order) }
    }

    private var selectedTracks: [IPodTrack] {
        monitor.tracks.filter { library.iPodSelection.contains($0.id) }
    }

    private func deleteTracks(_ tracks: [IPodTrack]) {
        if monitor.confirmAndDelete(tracks) { library.clearIPodSelection() }
    }

    // MARK: Artistas (círculos de 3 y página del artista)

    /// Agrupado y ordenado por LibraryIndex: el mismo artista escrito distinto
    /// ("Kings Of Leon" / "Kings of Leon") queda en un solo grupo.
    private var artistsGrid: some View {
        let groups = LibraryIndex.artists(filtered, all: monitor.tracks, query: query)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3)
        return AlphabetIndexedScroll(entries: LibraryIndex.indexEntries(groups), showsIndex: !isSearching) {
            LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
                ForEach(groups) { group in
                    let cover = group.items.first(where: \.hasArtwork) ?? group.items[0]
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { library.openIPodArtist = group.id }
                    } label: {
                        ArtistCell(name: group.title, count: group.items.count, matchSummary: group.matchSummary) {
                            IPodArtworkView(track: cover, artwork: monitor.artwork, size: nil,
                                            macArtwork: monitor.macArtwork(for: cover))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(group.title)
                    .contextMenu {
                        Button("Eliminar artista del iPod…", systemImage: "trash", role: .destructive) {
                            deleteTracks(group.items)
                        }
                    }
                    .id(group.id)   // destino del índice A–Z
                    .accessibilityLabel("\(group.title), \(group.items.count) canciones")
                    .accessibilityHint("Abre el artista")
                }
            }
            .padding(.top, 2)
        }
    }

    /// `key`: artista normalizado (LibraryIndex.normalizedKey).
    private func artistPage(_ key: String) -> some View {
        let allTracks = monitor.tracks.filter { LibraryIndex.normalizedKey($0.artist) == key }
        let name = LibraryIndex.mostCommon(allTracks.map(\.artist)) ?? key
        // Mientras buscas, como iTunes: solo las que coinciden (o todas, resaltadas).
        let scoped = SearchScopedList(allTracks, query: query, onlyMatches: library.detailShowsOnlyMatches)
        let tracks = scoped.shown
        // Cambiar la portada siempre aplica al álbum completo, aunque se vean solo coincidencias.
        let allByAlbum = Dictionary(grouping: allTracks, by: LibraryIndex.albumKey(for:))
        let allAlbumCount = allByAlbum.count
        // Álbumes del artista, del más nuevo al más viejo (misma clave que la vista Álbumes).
        let albums = LibraryIndex.albums(tracks, query: "")
            .map { (key: $0.id, tracks: $0.items) }
            .sorted { a, b in
                let ya = a.tracks[0].year, yb = b.tracks[0].year
                if ya != yb { return ya > yb }
                return a.tracks[0].album.localizedCompare(b.tracks[0].album) == .orderedAscending
            }
        let cover = allTracks.first(where: \.hasArtwork) ?? allTracks[0]
        // Orden en pantalla (para ⇧‑clic): álbum por álbum, por número de pista.
        let order = albums.flatMap { album in
            album.tracks.sorted { ($0.trackNumber, $0.title) < ($1.trackNumber, $1.title) }.map(\.id)
        }

        return AlphabetIndexedScroll(entries: [], showsIndex: false) {
            VStack(alignment: .leading, spacing: 14) {
                ArtistPageHeader(name: name.isEmpty ? "Artista desconocido" : name, albumCount: allAlbumCount, songCount: scoped.total, onBack: {
                    withAnimation(.easeInOut(duration: 0.25)) { library.openIPodArtist = nil }
                }) {
                    IPodArtworkView(track: cover, artwork: monitor.artwork, size: 56,
                                    macArtwork: monitor.macArtwork(for: cover))
                } accessory: {
                    EmptyView()
                }

                if scoped.showsBar {
                    SearchMatchBar(query: query, matchCount: scoped.matches.count, total: scoped.total,
                                   onlyMatches: Bindable(library).detailShowsOnlyMatches)
                }

                // Como Apple Music (Biblioteca › Artistas): cada álbum con su portada de encabezado
                // y sus canciones abajo. Todo a la vista, sin abrir nada ni cambiar de pestaña.
                ForEach(albums, id: \.key) { album in
                    let first = album.tracks.first(where: \.hasArtwork) ?? album.tracks[0]
                    let songs = album.tracks.sorted { ($0.trackNumber, $0.title) < ($1.trackNumber, $1.title) }
                    VStack(alignment: .leading, spacing: 6) {
                        ArtistAlbumSectionHeader(title: first.album.isEmpty ? "Sin álbum" : first.album,
                                                 year: first.year > 0 ? first.year : nil,
                                                 songCount: songs.count) {
                            IPodArtworkView(track: first, artwork: monitor.artwork, size: 56,
                                            macArtwork: monitor.macArtwork(for: first))
                        } accessory: {
                            EmptyView()
                        }
                        .contextMenu {
                            IPodAlbumArtworkMenu(albumKey: album.key, title: first.album, artist: first.artist,
                                                 tracks: allByAlbum[album.key] ?? album.tracks, monitor: monitor)
                            Divider()
                            Button("Eliminar álbum del iPod…", systemImage: "trash", role: .destructive) {
                                deleteTracks(allByAlbum[album.key] ?? album.tracks)
                            }
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, track in
                                if index > 0 { Divider().padding(.leading, 42) }
                                row(track, subtitle: "",
                                    number: track.trackNumber > 0 ? track.trackNumber : index + 1,
                                    isMatch: scoped.highlights(track), order: order)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    // MARK: Álbumes (cuadrícula de 2 o 3)

    private typealias Album = (key: String, title: String, artist: String, tracks: [IPodTrack], matchSummary: String?)

    private var albums: [Album] {
        LibraryIndex.albums(filtered, all: monitor.tracks, query: query).map {
            (key: $0.id, title: $0.title, artist: $0.items[0].artist, tracks: $0.items, matchSummary: $0.matchSummary)
        }
    }

    private var albumsGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                            count: max(2, min(4, columnCount)))
        let all = albums
        return AlphabetIndexedScroll(entries: all.map { (id: $0.key, title: $0.title) }, showsIndex: !isSearching) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(all, id: \.key) { album in
                    let cover = album.tracks.first(where: \.hasArtwork) ?? album.tracks[0]
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { library.openIPodAlbum = album.key }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            IPodArtworkView(track: cover, artwork: monitor.artwork, size: nil,
                                            macArtwork: monitor.macArtwork(for: cover))
                            Text(album.title)
                                .font(.system(size: columnCount >= 3 ? 11 : 12, weight: .semibold))
                                .lineLimit(1)
                            Text(album.matchSummary.map { "\(album.artist) · \($0)" }
                                 ?? (album.tracks.count == 1 ? album.artist : "\(album.artist) · \(album.tracks.count)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(album.title) — \(album.artist)")
                    .contextMenu {
                        Button("Elegir de internet…", systemImage: "square.grid.2x2") { choosingArtworkFor = album.key }
                            .disabled(monitor.updatingArtworkAlbums.contains(album.key))
                        IPodAlbumArtworkMenu(albumKey: album.key, title: album.title, artist: album.artist,
                                             tracks: album.tracks, monitor: monitor)
                        Divider()
                        Button("Eliminar álbum del iPod…", systemImage: "trash", role: .destructive) {
                            deleteTracks(album.tracks)
                        }
                    }
                    .artworkChooserPopover(for: album.key, presented: $choosingArtworkFor,
                                           artist: album.artist, album: album.title) { data in
                        monitor.replaceArtwork(albumKey: album.key, tracks: album.tracks, imageData: data)
                    }
                    .overlay(alignment: .top) {
                        if monitor.updatingArtworkAlbums.contains(album.key) {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 12)
                        }
                    }
                    .accessibilityLabel("\(album.title), \(album.artist), \(album.tracks.count) canciones")
                    .accessibilityHint("Abre el álbum")
                    .id(album.key)   // destino del índice A–Z
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func albumDetail(_ album: Album) -> some View {
        // Mientras buscas, como iTunes: solo las que coinciden (o todas, resaltadas).
        let scoped = SearchScopedList(album.tracks, query: query, onlyMatches: library.detailShowsOnlyMatches)
        let cover = album.tracks.first(where: \.hasArtwork) ?? album.tracks[0]
        let minutes = album.tracks.map(\.durationMs).reduce(0, +) / 60_000
        let year = album.tracks.first(where: { $0.year > 0 })?.year
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { library.openIPodAlbum = nil }
                } label: {
                    Label("Álbumes", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("[", modifiers: .command)
                .help("Volver a Álbumes (⌘[)")

                HStack(alignment: .bottom, spacing: 14) {
                    EditableIPodAlbumCover(albumKey: album.key, title: album.title, artist: album.artist,
                                           tracks: album.tracks, cover: cover, monitor: monitor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        Text([album.artist,
                              year.map(String.init),
                              album.tracks.count == 1 ? "1 canción" : "\(album.tracks.count) canciones",
                              minutes > 0 ? "\(minutes) min" : nil].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if scoped.showsBar {
                    SearchMatchBar(query: query, matchCount: scoped.matches.count, total: scoped.total,
                                   onlyMatches: Bindable(library).detailShowsOnlyMatches)
                }

                VStack(spacing: 0) {
                    // Igual que en la página del artista: número, título y duración a la derecha.
                    let order = scoped.shown.map(\.id)
                    ForEach(Array(scoped.shown.enumerated()), id: \.element.id) { index, track in
                        if index > 0 { Divider().padding(.leading, 42) }
                        row(track, subtitle: "",
                            number: track.trackNumber > 0 ? track.trackNumber : index + 1,
                            isMatch: scoped.highlights(track), order: order)
                    }
                }
            }
        }
    }

    // MARK: Lista de canciones (Artistas y Álbumes usan cuadrículas)

    private var sections: [(key: String, tracks: [IPodTrack])] {
        if isSearching {
            // Resultados: "Canciones" (por nombre), luego "Por artista", "Por álbum", "Por género".
            return group(filtered) { ($0.searchMatch(query) ?? .genre).sectionTitle }
        }
        return group(filtered) { IndexedSongsList.letter(for: $0.title) }
    }

    /// Agrupa en orden de aparición (las pistas ya vienen ordenadas).
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
        return result
    }

    private var list: some View {
        let groups = sections
        let order = groups.flatMap(\.tracks).map(\.id)
        return ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 4) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.key) { group in
                            Section {
                                ForEach(group.tracks) { track in
                                    row(track, subtitle: subtitle(for: track), order: order)
                                    Divider().padding(.leading, 52)
                                }
                            } header: {
                                sectionHeader(group.key)
                                    .id(group.key)
                            }
                        }
                    }
                }
                .scrollIndicators(isSearching ? .automatic : .hidden)

                if !isSearching {
                    AlphabetIndex(available: Set(groups.map(\.key))) { letter in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(letter, anchor: .top) }
                    }
                }
            }
        }
    }

    private func subtitle(for track: IPodTrack) -> String {
        track.album.isEmpty ? track.artist : "\(track.artist) · \(track.album)"
    }

    /// Letra (o "Por artista", "Por álbum"… al buscar) fija arriba de su sección.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.tint)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.thinMaterial)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Fila de una canción del iPod.
struct IPodTrackRow: View {
    let track: IPodTrack
    let subtitle: String
    var artwork: IPodArtworkStore? = nil
    /// Número de pista: fila de álbum (sin portada, que ya va en el encabezado del álbum).
    var number: Int? = nil
    /// Coincide con la búsqueda (se resalta cuando se ven todas las canciones).
    var isMatch = false
    var isSelected = false
    /// Se está borrando del iPod: se ve tenue y tachada.
    var isDeleting = false
    /// Clic derecho › Eliminar…: texto del botón y qué hacer (nil = sin esa opción).
    var deleteTitle: String? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let number {
                Text("\(number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 20, alignment: .trailing)
                Text(track.title)
                    .fontWeight(isMatch ? .semibold : .medium)
                    .foregroundStyle(isMatch ? AnyShapeStyle(TintShapeStyle.tint) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    .strikethrough(isDeleting)
                    .lineLimit(1)
            } else {
                IPodArtworkView(track: track, artwork: artwork, size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .fontWeight(.medium)
                        .strikethrough(isDeleting)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .frame(height: number != nil ? 34 : 44)
        .background(isSelected ? Color.accentColor.opacity(0.16)
                    : isMatch ? Color.accentColor.opacity(0.08) : .clear)
        .opacity(isDeleting ? 0.3 : 1)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copiar título") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(track.title) — \(track.artist)", forType: .string)
            }
            if let deleteTitle, let onDelete {
                Divider()
                Button(deleteTitle, systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .allowsHitTesting(!isDeleting)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([track.title, subtitle, track.durationText].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if let deleteTitle, let onDelete { Button(deleteTitle, action: onDelete) }
        }
    }
}

/// Portada de una canción del iPod. Mientras carga (o si no tiene) muestra un color con una nota.
struct IPodArtworkView: View {
    let track: IPodTrack
    let artwork: IPodArtworkStore?
    /// nil = cuadrada y del ancho disponible (cuadrícula de álbumes).
    var size: CGFloat? = 30
    /// Portada de la misma canción en tu Mac (más nítida que la del iPod, que es de 200×200 como máximo).
    var macArtwork: Data? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    private var corner: CGFloat { (size ?? 48) * 0.17 }
    /// Píxeles reales que ocupa (según la pantalla, no un ×2 fijo).
    private var neededPixels: Int { Int((size ?? 200) * displayScale) }

    /// Qué cargar: cambia si cambia la pista, el tamaño, la portada de la Mac o el almacén del iPod.
    private struct LoadKey: Hashable {
        let dbid: UInt64
        let pixels: Int
        let macImage: Int?
        let store: ObjectIdentifier?
    }

    var body: some View {
        // El cuadro mide lo que le toca y la imagen se recorta adentro: no desborda la celda.
        Color.clear
            .frame(width: size, height: size)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(hue: track.artworkHue, saturation: 0.40, brightness: 0.86),
                                                Color(hue: track.artworkHue, saturation: 0.62, brightness: 0.64)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note")
                            .font(.system(size: (size ?? 60) * 0.37, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
            // La portada de la Mac (más nítida) se reduce en la caché; si no hay, la del iPod.
            // Incluye el almacén: al cambiar una portada del iPod se crea uno nuevo y se vuelve a cargar.
            .task(id: LoadKey(dbid: track.dbid, pixels: neededPixels,
                              macImage: macArtwork.map(ArtworkThumbnailCache.imageID(for:)),
                              store: artwork.map(ObjectIdentifier.init))) {
                let loaded: CGImage?
                if let mac = macArtwork {
                    loaded = await ArtworkThumbnailCache.shared.thumbnail(
                        for: mac, imageID: ArtworkThumbnailCache.imageID(for: mac), maxPixels: neededPixels)
                } else if let artwork {
                    loaded = await artwork.image(for: track.dbid, minPixels: neededPixels)
                } else {
                    loaded = nil
                }
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
