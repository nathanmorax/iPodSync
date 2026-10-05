//
//  AlbumArtworkEditing.swift
//  iPodSync
//
//  Cambiar la portada de un álbum de la Mac: elegir una imagen, pegarla, arrastrarla o quitarla.
//  Se aplica a todas las canciones del álbum y se guarda en la biblioteca.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ArtworkPicker {
    /// Abre "Abrir" para elegir una imagen (JPEG, PNG, HEIC…).
    static func chooseImage(albumTitle: String, completion: @escaping (Data) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Portada de “\(albumTitle)”"
        panel.prompt = "Usar como portada"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return }
            completion(data)
        }
    }

    /// Imagen copiada (⌘C en Safari, Vista Previa, Finder…).
    static var pasteboardImage: Data? {
        NSImage(pasteboard: .general)?.tiffRepresentation
    }

    static var hasPasteboardImage: Bool {
        NSImage.canInit(with: .general)
    }

    static func isImageFile(_ url: URL) -> Bool {
        url.isFileURL && (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false)
    }
}

/// Opciones de portada para el menú de clic derecho de un álbum.
struct AlbumArtworkMenu: View {
    /// Canciones del álbum (todas comparten albumKey).
    let songs: [Song]
    let simulator: IPodSimulator

    var body: some View {
        if let first = songs.first {
            let key = first.albumKey
            Button("Cambiar portada…", systemImage: "photo") {
                ArtworkPicker.chooseImage(albumTitle: first.album) { simulator.setArtwork($0, forAlbum: key) }
            }
            Button("Pegar portada", systemImage: "doc.on.clipboard") {
                if let data = ArtworkPicker.pasteboardImage { simulator.setArtwork(data, forAlbum: key) }
            }
            .disabled(!ArtworkPicker.hasPasteboardImage)
            if songs.contains(where: { $0.artworkData != nil }) {
                Button("Quitar portada", systemImage: "photo.badge.minus", role: .destructive) {
                    simulator.setArtwork(nil, forAlbum: key)
                }
            }
        }
    }
}

/// Portada grande del detalle del álbum: clic para cambiarla, arrastra una imagen encima,
/// o clic derecho para pegar o quitar.
struct EditableAlbumCover: View {
    let songs: [Song]
    let fallback: Song
    let simulator: IPodSimulator
    var size: CGFloat = 120

    @State private var isHovering = false
    @State private var isDropTarget = false
    @State private var showsOnlineChoices = false

    var body: some View {
        let cover = songs.first(where: { $0.artworkData != nil }) ?? fallback
        let showsOverlay = isHovering || isDropTarget

        Button(action: choose) {
            SongArtworkView(song: cover, size: size, cornerRadius: 10)
                .overlay {
                    if showsOverlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .overlay {
                                VStack(spacing: 4) {
                                    Image(systemName: isDropTarget ? "square.and.arrow.down" : "photo.badge.plus")
                                        .font(.system(size: 20))
                                    Text(isDropTarget ? "Soltar aquí" : "Cambiar")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                            }
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .overlay {
                    if simulator.fetchingArtwork.contains(fallback.albumKey) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .overlay { ProgressView().controlSize(.small) }
                    }
                }
                .animation(.easeOut(duration: 0.15), value: showsOverlay)
                .shadow(color: .black.opacity(0.16), radius: 9, y: 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Elegir de internet…", systemImage: "square.grid.2x2") { showsOnlineChoices = true }
            AlbumArtworkMenu(songs: songs.isEmpty ? [fallback] : songs, simulator: simulator)
        }
        .popover(isPresented: $showsOnlineChoices, arrowEdge: .trailing) {
            OnlineArtworkChooser(artist: fallback.artist, album: fallback.album) { data in
                simulator.setArtwork(data, forAlbum: fallback.albumKey)
                showsOnlineChoices = false
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: ArtworkPicker.isImageFile),
                  let data = try? Data(contentsOf: url) else { return false }
            simulator.setArtwork(data, forAlbum: fallback.albumKey)
            return true
        } isTargeted: { isDropTarget = $0 }
        .help("Cambiar portada: haz clic, arrastra una imagen encima o clic derecho › Pegar portada")
        .accessibilityLabel("Portada de \(fallback.album)")
        .accessibilityHint("Elegir otra imagen")
    }

    private func choose() {
        let key = fallback.albumKey
        ArtworkPicker.chooseImage(albumTitle: fallback.album) { simulator.setArtwork($0, forAlbum: key) }
    }
}

/// Portadas encontradas en internet para elegir una. Jalando la lista hacia abajo desde arriba
/// (como para "actualizar") aparecen portadas nuevas al principio: primero las de artista + álbum,
/// luego las del álbum y al final otros álbumes del artista.
struct OnlineArtworkChooser: View {
    let artist: String
    let album: String
    let onPick: (Data) -> Void

    /// Cuántas portadas nuevas aparecen cada vez.
    private let pageSize = 12
    /// Cuánto hay que jalar (en puntos) para pedir más.
    private let pullThreshold: CGFloat = 50

    /// Todo lo bajado de internet, en orden; `shown` son las que ya se ven.
    @State private var loaded: [ArtworkLookup.Candidate] = []
    @State private var shown: [ArtworkLookup.Candidate] = []
    @State private var pendingTerms: [String] = []
    @State private var seen: Set<Int> = []
    @State private var isLoading = false
    @State private var didStart = false
    @State private var downloading: ArtworkLookup.Candidate.ID?
    @State private var pull: CGFloat = 0
    @State private var didTriggerPull = false
    @State private var newIDs: Set<Int> = []

    private let columns = Array(repeating: GridItem(.fixed(96), spacing: 10), count: 3)

    private var hasMore: Bool { shown.count < loaded.count || !pendingTerms.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Portadas en internet")
                .font(.headline)
            Text("\(album) · \(artist)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if shown.isEmpty && (isLoading || !didStart) {
                ProgressView()
                    .frame(width: 308, height: 120)
            } else if shown.isEmpty {
                ContentUnavailableView("Sin resultados", systemImage: "photo.on.rectangle",
                                       description: Text("Prueba con Cambiar portada… para elegir una imagen tuya."))
                    .frame(width: 308)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id("top")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(shown) { candidate in
                                Button { pick(candidate) } label: { cell(candidate) }
                                    .buttonStyle(.plain)
                                    .disabled(downloading != nil)
                                    .help("\(candidate.album) — \(candidate.artist)")
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                    }
                    .scrollBounceBehavior(.always)
                    // Cuánto se jala hacia abajo pasando el borde de arriba.
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                    } action: { _, newPull in
                        pull = newPull
                        if newPull > pullThreshold, !didTriggerPull {
                            didTriggerPull = true
                            Task {
                                await loadMore()
                                withAnimation { proxy.scrollTo("top", anchor: .top) }
                            }
                        } else if newPull == 0 {
                            didTriggerPull = false
                        }
                    }
                    .overlay(alignment: .top) { pullIndicator }
                    .frame(width: 308, height: 320)
                }
            }

            Text(hasMore ? "Jala la lista hacia abajo para ver más portadas" : "Ya no hay más portadas")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .task {
            guard !didStart else { return }
            pendingTerms = ArtworkLookup.searchTerms(artist: artist, album: album)
            await loadMore()
            newIDs = []
            didStart = true
        }
    }

    /// Flecha mientras jalas; indicador mientras carga.
    @ViewBuilder
    private var pullIndicator: some View {
        if isLoading && !shown.isEmpty {
            ProgressView()
                .controlSize(.small)
                .padding(6)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 6)
        } else if pull > 4 && hasMore {
            Label(pull > pullThreshold ? "Suelta para ver más" : "Jala para ver más",
                  systemImage: pull > pullThreshold ? "arrow.clockwise" : "arrow.down")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 6)
                .opacity(min(1, pull / pullThreshold))
        }
    }

    /// Pone hasta 12 portadas nuevas al principio. Si ya se mostraron todas las bajadas,
    /// hace la siguiente búsqueda (cada vez más amplia).
    private func loadMore() async {
        guard !isLoading, hasMore || !didStart else { return }
        isLoading = true
        defer { isLoading = false }

        while shown.count + pageSize > loaded.count, !pendingTerms.isEmpty {
            let term = pendingTerms.removeFirst()
            let results = (try? await ArtworkLookup.search(term: term, artist: artist, album: album, limit: 100)) ?? []
            for candidate in results where !seen.contains(candidate.id) {
                seen.insert(candidate.id)
                loaded.append(candidate)
            }
        }
        let next = Array(loaded[shown.count..<min(loaded.count, shown.count + pageSize)])
        guard !next.isEmpty else { return }
        newIDs = Set(next.map(\.id))
        withAnimation(.spring(duration: 0.35)) {
            // Las nuevas van arriba, para verlas sin bajar.
            shown.insert(contentsOf: next, at: 0)
        }
    }

    private func cell(_ candidate: ArtworkLookup.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            AsyncImage(url: candidate.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if downloading == candidate.id { ProgressView().controlSize(.small) }
            }
            // Las que acaban de aparecer llevan un borde azul.
            .overlay {
                if newIDs.contains(candidate.id) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            Text(candidate.album)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text([candidate.artist, candidate.year].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 96)
        .contentShape(Rectangle())
    }

    private func pick(_ candidate: ArtworkLookup.Candidate) {
        downloading = candidate.id
        Task {
            defer { downloading = nil }
            if let data = try? await ArtworkLookup.download(candidate) { onPick(data) }
        }
    }
}

// MARK: - Álbumes del iPod

/// Opciones de portada para un álbum que está en el iPod (aunque no esté en la Mac).
struct IPodAlbumArtworkMenu: View {
    let albumKey: String
    let title: String
    let artist: String
    let tracks: [IPodTrack]
    let monitor: IPodMonitor

    var body: some View {
        let busy = monitor.updatingArtworkAlbums.contains(albumKey)
        Button("Cambiar portada…", systemImage: "photo") {
            ArtworkPicker.chooseImage(albumTitle: title) {
                monitor.replaceArtwork(albumKey: albumKey, tracks: tracks, imageData: $0)
            }
        }
        .disabled(busy)
        Button("Pegar portada", systemImage: "doc.on.clipboard") {
            if let data = ArtworkPicker.pasteboardImage {
                monitor.replaceArtwork(albumKey: albumKey, tracks: tracks, imageData: data)
            }
        }
        .disabled(busy || !ArtworkPicker.hasPasteboardImage)
    }
}

/// Portada grande del detalle de un álbum del iPod: clic para cambiarla, arrastra una imagen,
/// o clic derecho para buscarla en internet o pegarla. Se escribe directo en el iPod.
struct EditableIPodAlbumCover: View {
    let albumKey: String
    let title: String
    let artist: String
    let tracks: [IPodTrack]
    let cover: IPodTrack
    let monitor: IPodMonitor
    var size: CGFloat = 110

    @State private var isHovering = false
    @State private var isDropTarget = false
    @State private var showsOnlineChoices = false

    var body: some View {
        let busy = monitor.updatingArtworkAlbums.contains(albumKey)
        let showsOverlay = (isHovering || isDropTarget) && !busy

        Button(action: choose) {
            IPodArtworkView(track: cover, artwork: monitor.artwork, size: size,
                            macArtwork: monitor.macArtwork(for: cover))
                .overlay {
                    if showsOverlay {
                        RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .overlay {
                                VStack(spacing: 4) {
                                    Image(systemName: isDropTarget ? "square.and.arrow.down" : "photo.badge.plus")
                                        .font(.system(size: 20))
                                    Text(isDropTarget ? "Soltar aquí" : "Cambiar")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                            }
                    }
                }
                .overlay {
                    if busy {
                        RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .overlay { ProgressView().controlSize(.small) }
                    }
                }
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: showsOverlay)
                .shadow(color: .black.opacity(0.25), radius: 9, y: 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Elegir de internet…", systemImage: "square.grid.2x2") { showsOnlineChoices = true }
                .disabled(busy)
            IPodAlbumArtworkMenu(albumKey: albumKey, title: title, artist: artist, tracks: tracks, monitor: monitor)
        }
        .popover(isPresented: $showsOnlineChoices, arrowEdge: .trailing) {
            OnlineArtworkChooser(artist: artist, album: title) { data in
                monitor.replaceArtwork(albumKey: albumKey, tracks: tracks, imageData: data)
                showsOnlineChoices = false
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: ArtworkPicker.isImageFile),
                  let data = try? Data(contentsOf: url) else { return false }
            monitor.replaceArtwork(albumKey: albumKey, tracks: tracks, imageData: data)
            return true
        } isTargeted: { isDropTarget = $0 }
        .help("Cambiar la portada en el iPod: haz clic, arrastra una imagen encima o clic derecho › Elegir de internet…")
        .accessibilityLabel("Portada de \(title)")
        .accessibilityHint("Elegir otra imagen para el iPod")
    }

    private func choose() {
        ArtworkPicker.chooseImage(albumTitle: title) {
            monitor.replaceArtwork(albumKey: albumKey, tracks: tracks, imageData: $0)
        }
    }
}
