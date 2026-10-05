//
//  MacLibraryPanel.swift
//  iPodSync
//
//  Panel flotante: "En mi Mac" / "En mi iPod", búsqueda, filtros, lista y espacio antes de enviar.
//

import SwiftUI
import UniformTypeIdentifiers

struct MacLibraryPanel: View {
    @Bindable var library: LibraryState
    let simulator: IPodSimulator
    let monitor: IPodMonitor

    @Environment(BackupViewModel.self) private var backup
    @FocusState private var searchFocused: Bool
    @State private var isFileDropTarget = false
    @Namespace private var sourceNamespace

    // MARK: Datos

    private var isMac: Bool { library.source == .mac }

    private var visible: [Song] {
        if isMac {
            // Con "Todas" no se pregunta el estado de cada canción: así el panel no depende
            // de la cola de envíos y no se recalcula con cada canción que se manda.
            guard library.statusFilter != .all else { return library.filter(simulator.songs) }
            return library.filter(simulator.songs).filter { library.statusFilter.matches(simulator.status(of: $0)) }
        }
        // iPod simulado: las canciones que ya están en el iPod.
        return library.filter(simulator.onDeviceSongs)
    }

    private var iPodCount: Int {
        simulator.isSimulated ? simulator.onDeviceSongs.count : monitor.tracks.count
    }

    private var pending: [Song] {
        simulator.songs.filter { simulator.status(of: $0) == .notOnDevice }
    }

    private var selectedSendable: [Song] {
        simulator.songs.filter { library.selection.contains($0.id) && simulator.canSend($0) }
    }

    /// Lo que mandaría el botón principal: la selección si hay, si no todo lo pendiente.
    private var toSend: [Song] { selectedSendable.isEmpty ? pending : selectedSendable }
    private var toSendGB: Double { toSend.map(\.sizeMB).reduce(0, +) / 1024 }

    // MARK: Vista

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourcePicker
            if needsAccess { accessBanner }
            if !simulator.isSimulated && monitor.device == nil { connectHint }
            searchField
            scopeTabs
            if isMac {
                filterChips
            } else if simulator.isConnected {
                storageBar
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if isMac { footer }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
        .overlay {
            if isFileDropTarget {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        // Archivos de audio arrastrados desde el Finder se agregan a la biblioteca.
        .dropDestination(for: URL.self) { urls, _ in
            let audio = urls.filter { url in
                url.isFileURL && (UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false)
            }
            guard !audio.isEmpty else { return false }
            Task { await simulator.importFiles(audio) }
            return true
        } isTargeted: { isFileDropTarget = $0 }
        .environment(\.colorScheme, .dark)
        .onChange(of: library.searchFocusRequest) { searchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Biblioteca de la Mac")
    }

    // MARK: Encabezado: En mi Mac | En mi iPod

    private var sourcePicker: some View {
        HStack(spacing: 2) {
            ForEach(LibrarySource.allCases) { source in
                sourceButton(source, count: source == .mac ? simulator.songs.count : iPodCount)
            }
        }
        .padding(2)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        // El encabezado del panel también mueve la ventana.
        .background(WindowDragArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ver música")
    }

    private func sourceButton(_ source: LibrarySource, count: Int) -> some View {
        let isOn = library.source == source
        return Button {
            withAnimation(.snappy(duration: 0.2)) { library.source = source }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 14))
                Text(source.title)
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .matchedGeometryEffect(id: "source", in: sourceNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.title), \(count) canciones")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Canciones / Artistas / Álbumes como pestañas oscuras; en Álbumes, 2 o 3 por fila al final.
    private var scopeTabs: some View {
        HStack(spacing: 8) {
            DarkSegmented(selection: $library.scope, options: LibraryScope.allCases) { scope, isOn in
                HStack(spacing: 5) {
                    Image(systemName: scope.systemImage)
                        .font(.system(size: 12))
                    Text(scope.title)
                        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            .help("Canciones, Artistas o Álbumes (⌘1, ⌘2, ⌘3)")

            if library.scope == .albums {
                AlbumColumnsPicker()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: library.scope)
    }

    // MARK: Permiso para entrar al iPod

    private var needsAccess: Bool {
        !simulator.isSimulated && monitor.device != nil && !monitor.hasAccess
    }

    private var accessBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Dale acceso a “\(monitor.device?.name ?? "tu iPod")”")
                    .font(.system(size: 12, weight: .semibold))
                Text("macOS pide que elijas el iPod una vez para que iPodSync pueda leer y copiar música.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Dar acceso…") { monitor.requestAccess() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var connectHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cable.connector")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Conecta tu iPod con el cable USB")
                    .font(.system(size: 12, weight: .semibold))
                Text("Se detecta solo. Si no aparece, elígelo a mano.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Elegir iPod…") { monitor.requestAccess() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Buscar", text: $library.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand {
                    library.query = ""
                    searchFocused = false
                }
            if !library.query.isEmpty {
                Button {
                    library.query = ""
                } label: {
                    Label("Borrar búsqueda", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 120, maxWidth: .infinity)
        .frame(height: 28)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("Buscar (⌘F)")
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(LibraryStatusFilter.allCases) { filter in
                let isOn = library.statusFilter == filter
                Button {
                    library.statusFilter = filter
                } label: {
                    Text(chipTitle(filter))
                        .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .foregroundStyle(isOn ? Color.black : Color.primary)
                        .background(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.quaternary), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            Spacer(minLength: 4)
            if simulator.importingCount > 0 {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Agregando \(simulator.importingCount)…")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func chipTitle(_ filter: LibraryStatusFilter) -> String {
        switch filter {
        case .notOnDevice: "\(filter.title) · \(pending.count)"
        case .all:         filter.title
        }
    }

    // MARK: Contenido

    /// Con el iPod real, "En mi iPod" muestra la música que trae el iPod (leída de su iTunesDB).
    private var showsIPodMusic: Bool {
        !simulator.isSimulated && library.source == .iPod
    }

    /// Lo que va en lugar de los filtros cuando se ve el iPod: espacio libre y respaldo.
    private var storageBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(storageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: 4)
            if canBackup { backupButtons }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canBackup: Bool {
        !simulator.isSimulated && monitor.accessibleVolumeURL != nil && !monitor.tracks.isEmpty
    }

    private var storageText: String {
        var text = "\(gb(simulator.freeGB, digits: 1)) GB libres"
        guard !simulator.isSimulated else { return text }
        if let id = monitor.device?.id, let date = backup.lastBackupDate(for: id) {
            text += " · respaldo \(date.formatted(.relative(presentation: .named)))"
        } else {
            text += " · sin respaldo"
        }
        return text
    }

    @ViewBuilder
    private var backupButtons: some View {
        let missingArt = monitor.missingArtworkCount
        if missingArt > 0 || monitor.isWritingArtwork {
            Button(monitor.isWritingArtwork ? "Portadas…" : "Portadas (\(missingArt))") {
                monitor.addMissingArtwork()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(monitor.isWritingArtwork)
            .help("Poner en el iPod las portadas que faltan")
        }
        Button(backup.isRunning ? "Respaldando…" : "Respaldar…") { backup.showBackup() }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private var content: some View {
        if showsIPodMusic {
            IPodMusicView(monitor: monitor, library: library, scope: library.scope, query: library.query)
        } else {
            // Se filtra una sola vez por render y se pasa a la lista que toque.
            libraryContent(visible)
        }
    }

    @ViewBuilder
    private func libraryContent(_ visible: [Song]) -> some View {
        if visible.isEmpty {
            emptyState
        } else {
            switch library.scope {
            case .songs:
                IndexedSongsList(songs: visible, simulator: simulator, library: library)
            case .artists:
                if let artist = library.openArtist, simulator.songs.contains(where: { $0.artist == artist }) {
                    AlphabetIndexedScroll(entries: [], showsIndex: false) {
                        ArtistDetailView(artist: artist, simulator: simulator, library: library) {
                            withAnimation(.easeInOut(duration: 0.25)) { library.openArtist = nil }
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    // Agrupado y ordenado una vez: lo usan la cuadrícula y el índice A–Z.
                    let artists = LibraryIndex.artists(visible, query: library.query)
                    AlphabetIndexedScroll(entries: LibraryIndex.indexEntries(artists), showsIndex: !isSearching) {
                        ArtistsGridView(groups: artists, simulator: simulator) { artist in
                            withAnimation(.easeInOut(duration: 0.25)) { library.openArtist = artist }
                        }
                    }
                    .transition(.opacity)
                }
            case .albums:
                let albums = LibraryIndex.albums(visible, query: library.query)
                AlphabetIndexedScroll(entries: LibraryIndex.indexEntries(albums),
                                      showsIndex: !isSearching && library.selectedAlbumID == nil) {
                    if let id = library.selectedAlbumID,
                       let song = simulator.songs.first(where: { $0.id == id }) {
                        AlbumDetailView(song: song, simulator: simulator, library: library) {
                            library.selectedAlbumID = nil
                        }
                    } else {
                        AlbumsGridView(albums: albums, simulator: simulator) { song in
                            library.selectedAlbumID = song.id
                        }
                    }
                }
            }
        }
    }

    // MARK: Índice A–Z (Artistas y Álbumes)

    private var isSearching: Bool { SearchMatch.isSearching(library.query) }

    @ViewBuilder
    private var emptyState: some View {
        if !library.query.isEmpty {
            ContentUnavailableView.search(text: library.query)
        } else if !isMac {
            ContentUnavailableView {
                Label(simulator.isConnected ? "Tu iPod está vacío" : "El iPod no está conectado", systemImage: "ipod")
            } description: {
                Text(simulator.isConnected ? "Envía canciones desde “En mi Mac”." : "Conéctalo para ver su música.")
            } actions: {
                if simulator.isConnected { Button("Ir a En mi Mac") { library.source = .mac } }
            }
        } else if library.statusFilter != .all {
            ContentUnavailableView {
                Label("Nada en “\(library.statusFilter.title)”", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Prueba con otro filtro.")
            } actions: {
                Button("Ver todas") { library.statusFilter = .all }
            }
        } else {
            ContentUnavailableView {
                Label("Tu biblioteca está vacía", systemImage: "music.note.list")
            } description: {
                Text("Arrastra archivos de audio aquí o elige Archivo › Agregar a la biblioteca.")
            } actions: {
                Button("Agregar a la biblioteca…") { library.isImporting = true }
            }
        }
    }

    // MARK: Pie: espacio y envío

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Text(toSend.isEmpty ? "Todo está en el iPod" : "Al enviar \(toSend.count) \(toSend.count == 1 ? "canción" : "canciones")")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(gb(simulator.freeGB)) → \(gb(simulator.freeGB - toSendGB)) GB libres")
                    .monospacedDigit()
            }
            .font(.caption)

            CapacityBar(other: simulator.usedOtherFraction,
                        music: simulator.usedMusicFraction,
                        pending: toSendGB / simulator.capacityGB)

            HStack(spacing: 12) {
                legend("Otros", Color.gray)
                legend("Música", Color.green)
                legend("Por enviar", Color.accentColor)
                Spacer(minLength: 4)
                Button(action: sendNow) {
                    Text(sendTitle).monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!simulator.isConnected || toSend.isEmpty)
                .help(simulator.isConnected ? "Enviar al iPod (⌘↩ envía la selección)" : "Conecta el iPod para enviar")
            }
        }
    }

    private var sendTitle: String {
        guard simulator.isConnected else { return simulator.isSimulated ? "iPod desconectado" : "Conecta tu iPod" }
        return selectedSendable.isEmpty ? "Enviar \(pending.count)" : "Enviar selección (\(selectedSendable.count))"
    }

    private func sendNow() {
        simulator.sendAll(toSend.map(\.id))
        library.clearSelection()
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func gb(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Lista de canciones por letra con índice A–Z

#Preview("MacLibraryPanel · En tu Mac") {
    MacLibraryPanel(library: LibraryState(), simulator: IPodSimulator(), monitor: IPodMonitor())
        .environment(BackupViewModel())
        .frame(width: 384, height: 640)
        .padding(30)
        .background(Wallpaper())
}

#Preview("MacLibraryPanel · iPod desconectado") {
    let sim = IPodSimulator()
    sim.eject()
    return MacLibraryPanel(library: LibraryState(), simulator: sim, monitor: IPodMonitor())
        .environment(BackupViewModel())
        .frame(width: 384, height: 640)
        .padding(30)
        .background(Wallpaper())
}

/// 2 o 3 álbumes por fila (se recuerda; aplica a la Mac y al iPod).
struct AlbumColumnsPicker: View {
    @AppStorage(SettingsKey.albumColumns) private var columnCount = 2

    var body: some View {
        DarkSegmented(selection: $columnCount, options: [2, 3], fillsWidth: false) { count, _ in
            Image(systemName: count == 2 ? "square.grid.2x2" : "square.grid.3x3")
                .font(.system(size: 12))
                .accessibilityLabel("\(count) por fila")
        }
        .fixedSize()
        .help("Álbumes por fila: 2 o 3")
    }
}
