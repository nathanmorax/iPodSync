//
//  MacLibraryPanel.swift
//  iPodSync
//
//  Panel flotante "En tu Mac": búsqueda, filtros, lista y espacio antes de enviar.
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

    // MARK: Datos

    private var visible: [Song] {
        library.filter(simulator.songs).filter { library.statusFilter.matches(simulator.status(of: $0)) }
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
            header
            if needsAccess { accessBanner }
            if !simulator.isSimulated && monitor.device == nil { connectHint }
            searchField
            filterChips
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
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

    // MARK: Encabezado

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("En tu Mac")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(simulator.importingCount > 0
                     ? "Agregando \(simulator.importingCount) \(simulator.importingCount == 1 ? "archivo" : "archivos")…"
                     : "\(simulator.songs.count) canciones · \(simulator.onDeviceSongs.count) ya en el iPod")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            if library.scope == .albums {
                AlbumColumnsPicker()
            }
            Picker("Ver por", selection: $library.scope) {
                ForEach(LibraryScope.allCases) { scope in
                    Label(scope.title, systemImage: scope.systemImage).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            .help("Canciones, Artistas o Álbumes (⌘1, ⌘2, ⌘3)")
        }
        // El encabezado del panel también mueve la ventana.
        .background(WindowDragArea())
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
            TextField("Buscar canción o artista", text: $library.query)
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
        }
    }

    private func chipTitle(_ filter: LibraryStatusFilter) -> String {
        switch filter {
        case .notOnDevice:
            return "\(filter.title) · \(pending.count)"
        case .onDevice where showsIPodMusic && !monitor.tracks.isEmpty:
            return "\(filter.title) · \(monitor.tracks.count)"
        default:
            return filter.title
        }
    }

    // MARK: Contenido

    /// Con el iPod real, "En el iPod" muestra la música que trae el iPod (leída de su iTunesDB).
    private var showsIPodMusic: Bool {
        !simulator.isSimulated && library.statusFilter == .onDevice
    }

    /// Recordatorio de respaldo arriba de la música del iPod.
    private var backupBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.timemachine")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Group {
                if let id = monitor.device?.id, let date = backup.lastBackupDate(for: id) {
                    Text("Último respaldo: \(date.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Sin respaldo todavía")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            let missingArt = monitor.missingArtworkCount
            if missingArt > 0 || monitor.isWritingArtwork {
                Button(monitor.isWritingArtwork ? "Poniendo portadas…" : "Portadas (\(missingArt))") {
                    monitor.addMissingArtwork()
                }
                .controlSize(.small)
                .disabled(monitor.isWritingArtwork)
                .help("Poner en el iPod las portadas que faltan")
            }
            Button(backup.isRunning ? "Respaldando…" : "Respaldar…") { backup.showBackup() }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if showsIPodMusic {
            VStack(spacing: 8) {
                if monitor.accessibleVolumeURL != nil, !monitor.tracks.isEmpty { backupBar }
                IPodMusicView(monitor: monitor, library: library, scope: library.scope, query: library.query)
            }
        } else if visible.isEmpty {
            emptyState
        } else {
            switch library.scope {
            case .songs:
                IndexedSongsList(songs: visible, simulator: simulator, library: library)
            case .artists:
                ScrollView {
                    ArtistsListView(songs: visible, simulator: simulator, library: library)
                }
            case .albums:
                ScrollView {
                    if let id = library.selectedAlbumID,
                       let song = simulator.songs.first(where: { $0.id == id }) {
                        AlbumDetailView(song: song, simulator: simulator, library: library) {
                            library.selectedAlbumID = nil
                        }
                    } else {
                        AlbumsGridView(songs: visible, simulator: simulator, query: library.query) { song in
                            library.selectedAlbumID = song.id
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !library.query.isEmpty {
            ContentUnavailableView.search(text: library.query)
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

    private func gb(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
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
        Picker("Álbumes por fila", selection: $columnCount) {
            Label("2 por fila", systemImage: "square.grid.2x2").tag(2)
            Label("3 por fila", systemImage: "square.grid.3x3").tag(3)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
        .fixedSize()
        .help("Álbumes por fila: 2 o 3")
    }
}
