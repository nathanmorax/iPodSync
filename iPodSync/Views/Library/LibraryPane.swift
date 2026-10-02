//
//  LibraryPane.swift
//  iPodSync
//
//  Mitad izquierda: lista de la biblioteca y espacio del iPod.
//  El selector de vista y el buscador viven en la barra de herramientas de la ventana.
//

import SwiftUI
import UniformTypeIdentifiers

struct LibraryPane: View {
    @Bindable var library: LibraryState
    let simulator: IPodSimulator

    @State private var isFileDropTarget = false

    private var filtered: [Song] { library.filter(simulator.songs) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // Clic en un espacio vacío quita la selección, como en el Finder.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { library.clearSelection() })

            Divider()

            StorageFooter(
                onDeviceCount: simulator.onDeviceSongs.count,
                freeSpaceText: simulator.freeSpaceText,
                usedOther: simulator.usedOtherFraction,
                usedMusic: simulator.usedMusicFraction
            )
        }
        .background(Theme.libraryBackground)
        .overlay {
            if isFileDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        // Archivos de audio arrastrados desde el Finder se agregan a la biblioteca.
        .dropDestination(for: URL.self) { urls, _ in
            let audio = urls.filter { url in
                url.isFileURL && (UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false)
            }
            return !simulator.addSongs(from: audio).isEmpty
        } isTargeted: { isFileDropTarget = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            if library.query.isEmpty {
                ContentUnavailableView {
                    Label("Tu biblioteca está vacía", systemImage: "music.note.list")
                } description: {
                    Text("Arrastra archivos de audio aquí o elige Archivo › Agregar a la biblioteca.")
                } actions: {
                    Button("Agregar a la biblioteca…") { library.isImporting = true }
                }
                .padding(.top, 40)
            } else {
                ContentUnavailableView.search(text: library.query)
                    .padding(.top, 40)
            }
        } else {
            switch library.scope {
            case .songs:
                SongsListView(songs: filtered, simulator: simulator, library: library)
            case .artists:
                ArtistsListView(songs: filtered, simulator: simulator, library: library)
            case .albums:
                if let id = library.selectedAlbumID, let song = simulator.songs.first(where: { $0.id == id }) {
                    AlbumDetailView(song: song, simulator: simulator, library: library) {
                        library.selectedAlbumID = nil
                    }
                } else {
                    AlbumsGridView(songs: filtered, simulator: simulator) { song in
                        library.selectedAlbumID = song.id
                    }
                }
            }
        }
    }
}

// MARK: - Pie con el espacio del iPod

struct StorageFooter: View {
    let onDeviceCount: Int
    let freeSpaceText: String
    let usedOther: Double
    let usedMusic: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: geo.size.width * usedOther)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: max(3, geo.size.width * usedMusic))
                    Spacer(minLength: 0)
                }
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.3), value: usedMusic)

            Text("\(onDeviceCount) canciones en el iPod · \(freeSpaceText) de \(Int(MockLibrary.capacityGB)) GB")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LibraryPane(library: LibraryState(), simulator: IPodSimulator())
        .frame(width: 520, height: 600)
}
