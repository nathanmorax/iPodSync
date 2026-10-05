//
//  IPodSimulator.swift
//  iPodSync
//
//  Estado del iPod en pantalla: conexión, navegación del LCD y cola de envío (simulada).
//  Paso 3 de la reestructura: se divide en DeviceViewModel, EmulatorViewModel y TransferRepository.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class IPodSimulator {
    struct NavEntry: Equatable {
        var screen: LCDScreenID
        var selection = 0
        var scroll = 0
    }

    /// Filas que caben en la pantalla del iPod.
    static let visibleRows = 7

    var songs: [Song] {
        didSet { rebuildArtworkIndex() }
    }
    /// Portada de cada canción de la Mac por "título|artista". Antes cada portada del iPod
    /// buscaba recorriendo todas las canciones (cientos de miles de comparaciones por render).
    private(set) var artworkByKey: [String: Data] = [:]
    /// Para no reasignar (y redibujar) el índice si las portadas no cambiaron.
    @ObservationIgnored private var artworkSignature = 0
    var backlightOn = false
    private(set) var isConnected = true
    /// true = iPod de prueba (Ajustes › Simular un iPod). false = sigue al iPod real conectado.
    private(set) var isSimulated = true
    /// El iPod real conectado (nil con el simulado o si no hay ninguno).
    private(set) var device: IPodDevice?
    /// Canciones que tiene el iPod real (leídas de su iTunesDB).
    private(set) var deviceTracks: [IPodTrack] = []
    /// Canciones enviadas en esta sesión al iPod real (el envío todavía es simulado).
    private(set) var sentIDs: Set<Song.ID> = []
    /// Canciones que ya tiene el iPod (título|artista). Observable: al terminar de leer el iPod,
    /// las filas tienen que enterarse para dejar de decir "sin enviar" (antes era @ObservationIgnored).
    private var trackKeys: Set<String> = []
    /// Sube con cada "Cancelar envíos": una cola vieja que despierta tarde ya no toca el estado nuevo.
    @ObservationIgnored private var queueGeneration = 0
    /// Archivos que se están agregando a la biblioteca ahora mismo.
    private(set) var importingCount = 0
    /// Avisos al agregar archivos (formato no compatible, duplicados…).
    var importMessage: String?
    /// Error al enviar al iPod real (se muestra en una alerta).
    var sendMessage: String?
    /// Con el iPod real: copia la canción de verdad (lo pone IPodMonitor).
    @ObservationIgnored var realSender: ((Song, @escaping @Sendable (Double) -> Void) async throws -> Void)?
    /// Con el iPod real: al terminar la cola, volver a leer la música del iPod.
    @ObservationIgnored var onRealQueueFinished: (() -> Void)?
    /// La biblioteca que no se está usando: la de ejemplo mientras se usa el iPod real, y al revés.
    @ObservationIgnored private var otherLibrary: [Song] = []
    private(set) var recentIDs: [Song.ID]
    private(set) var nav: [NavEntry] = [NavEntry(screen: .main)]
    private(set) var transfer: TransferState?
    /// Progreso de la canción en curso. Es `let`: leer `simulator.transferProgress` no suscribe
    /// a la vista; solo quien lea `.value` (la barra del LCD) se redibuja con cada avance.
    let transferProgress = TransferProgress()
    private(set) var queue: [Song.ID] = []

    private var transferTask: Task<Void, Never>?
    private let otherUsedGB: Double

    init(songs: [Song] = MockLibrary.songs) {
        self.songs = songs
        self.recentIDs = songs.filter(\.isOnDevice).map(\.id)
        let musicGB = songs.filter(\.isOnDevice).map(\.sizeMB).reduce(0, +) / 1024
        self.otherUsedGB = MockLibrary.capacityGB - MockLibrary.initialFreeGB - musicGB
        // Biblioteca real guardada (se usa al cambiar al iPod real).
        self.otherLibrary = MacLibraryStore.load()
        rebuildArtworkIndex()
    }

    private func rebuildArtworkIndex() {
        var signature = Hasher()
        var index: [String: Data] = [:]
        for song in songs {
            guard let data = song.artworkData else { continue }
            let key = Self.matchKey(title: song.title, artist: song.artist)
            index[key] = data
            signature.combine(key)
            signature.combine(data)   // tamaño + primeros bytes: barato y detecta portadas nuevas
        }
        let value = signature.finalize()
        guard value != artworkSignature else { return }
        artworkSignature = value
        artworkByKey = index
    }

    // MARK: - Datos derivados

    var current: NavEntry { nav[nav.count - 1] }
    var isTransferring: Bool { transfer != nil }
    var canNavigate: Bool { isConnected && transfer == nil }

    var statusTitle: String { transfer != nil ? "SYNC" : current.screen.title }

    /// Canciones esperando o enviándose ahora.
    var pendingCount: Int {
        queue.count + ((transfer?.finished == false) ? 1 : 0)
    }

    var onDeviceSongs: [Song] {
        songs.filter(isOnIPod).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// ¿Esta canción de la Mac ya está en el iPod?
    /// Simulado: la marca de prueba. Real: si el iPod tiene una con el mismo título y artista.
    func isOnIPod(_ song: Song) -> Bool {
        if isSimulated { return song.isOnDevice }
        return sentIDs.contains(song.id) || trackKeys.contains(Self.matchKey(title: song.title, artist: song.artist))
    }

    func setDeviceTracks(_ tracks: [IPodTrack]) {
        trackKeys = Set(tracks.map { Self.matchKey(title: $0.title, artist: $0.artist) })
        deviceTracks = tracks
    }

    static func matchKey(title: String, artist: String) -> String {
        "\(title)|\(artist)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Títulos para el menú Canciones del LCD.
    private var lcdSongTitles: [String] {
        isSimulated ? onDeviceSongs.map(\.title) : deviceTracks.map(\.title)
    }

    var recentSongs: [Song] {
        recentIDs.compactMap { id in songs.first { $0.id == id } }
    }

    var artists: [(name: String, count: Int)] {
        let names = isSimulated ? onDeviceSongs.map(\.artist) : deviceTracks.map(\.artist)
        return Dictionary(grouping: names, by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var musicGB: Double {
        if isSimulated { return onDeviceSongs.map(\.sizeMB).reduce(0, +) / 1024 }
        return Double(deviceTracks.map(\.sizeBytes).reduce(0, +)) / 1_000_000_000
    }

    /// Nombre a mostrar: el del iPod real o "iPod classic".
    var deviceName: String { device?.name ?? "iPod classic" }

    /// Capacidad en GB: la real del disco o la de prueba.
    var capacityGB: Double {
        if let device, device.totalGB > 0 { return device.totalGB }
        return MockLibrary.capacityGB
    }

    var freeGB: Double {
        if let device { return device.freeGB }
        return MockLibrary.capacityGB - otherUsedGB - musicGB
    }

    var usedMusicFraction: Double { musicGB / capacityGB }

    var usedOtherFraction: Double {
        if device != nil {
            return max(0, (capacityGB - freeGB) / capacityGB - usedMusicFraction)
        }
        return otherUsedGB / MockLibrary.capacityGB
    }

    var usedFraction: Double { usedOtherFraction + usedMusicFraction }

    var freeSpaceText: String {
        String(format: "%.1f GB libres", freeGB).replacingOccurrences(of: ".", with: ",")
    }

    var rows: [LCDRow] { rows(for: current.screen) }

    func rows(for screen: LCDScreenID) -> [LCDRow] {
        switch screen {
        case .main:
            return [
                LCDRow(id: "recents",  title: "Recientes", value: "\(recentSongs.count)", action: .open(.recents)),
                LCDRow(id: "songs",    title: "Canciones", value: "\(lcdSongTitles.count)", action: .open(.songs)),
                LCDRow(id: "artists",  title: "Artistas",  value: "\(artists.count)", action: .open(.artists)),
                LCDRow(id: "storage",  title: "Espacio",   action: .open(.storage)),
                LCDRow(id: "settings", title: "Ajustes",   action: .open(.settings))
            ]
        case .recents:
            return recentSongs.map { LCDRow(id: $0.id.uuidString, title: $0.title) }
        case .songs:
            return lcdSongTitles.enumerated().map { LCDRow(id: "song-\($0.offset)", title: $0.element) }
        case .artists:
            return artists.map { LCDRow(id: $0.name, title: $0.name, value: "\($0.count)") }
        case .storage:
            return []
        case .settings:
            return [
                LCDRow(id: "light",   title: "Luz", value: backlightOn ? "Sí" : "No", action: .toggleBacklight),
                LCDRow(id: "version", title: "Versión", value: "1.0")
            ]
        }
    }

    func status(of song: Song) -> SongSyncStatus {
        if isOnIPod(song) { return .onDevice }
        if let transfer, transfer.songID == song.id, !transfer.finished { return .sending }
        if queue.contains(song.id) { return .queued }
        return .notOnDevice
    }

    func canSend(_ song: Song) -> Bool {
        isConnected && status(of: song) == .notOnDevice
    }

    // MARK: - Navegación

    func moveUp() {
        guard canNavigate else { return }
        var entry = current
        guard entry.selection > 0 else { return }
        entry.selection -= 1
        if entry.selection < entry.scroll { entry.scroll = entry.selection }
        nav[nav.count - 1] = entry
    }

    func moveDown() {
        guard canNavigate else { return }
        var entry = current
        guard entry.selection < rows.count - 1 else { return }
        entry.selection += 1
        if entry.selection >= entry.scroll + Self.visibleRows {
            entry.scroll = entry.selection - Self.visibleRows + 1
        }
        nav[nav.count - 1] = entry
    }

    func select() {
        guard canNavigate else { return }
        let rows = rows
        guard rows.indices.contains(current.selection) else { return }
        switch rows[current.selection].action {
        case .open(let screen):  nav.append(NavEntry(screen: screen))
        case .toggleBacklight:   backlightOn.toggle()
        case nil:                break
        }
    }

    func back() {
        guard canNavigate, nav.count > 1 else { return }
        nav.removeLast()
    }

    func toggleBacklight() {
        guard isConnected else { return }
        backlightOn.toggle()
    }

    // MARK: - Conexión

    /// Lo llama IPodMonitor: con el iPod real, "conectado" sigue al cable; con el simulado, no cambia nada.
    func attach(device: IPodDevice?, simulated: Bool) {
        let wasSimulated = isSimulated
        isSimulated = simulated
        self.device = simulated ? nil : device

        // Biblioteca: las canciones de ejemplo (MockLibrary) solo existen con el iPod simulado.
        // Con el iPod real la biblioteca empieza vacía y solo tiene lo que agregues (⌘O o arrastrando).
        if wasSimulated != simulated {
            cancelTransfers()
            swap(&songs, &otherLibrary)
            recentIDs = simulated ? songs.filter(\.isOnDevice).map(\.id) : []
        }

        if simulated {
            if !wasSimulated {
                isConnected = true
                nav = [NavEntry(screen: .main)]
            }
            return
        }

        let connected = device != nil
        if connected != isConnected {
            if !connected { cancelTransfers() }
            nav = [NavEntry(screen: .main)]
            withAnimation(.easeInOut(duration: 0.3)) { isConnected = connected }
        }
    }

    /// Solo para el iPod simulado; el real se expulsa con IPodMonitor.eject().
    func eject() {
        cancelTransfers()
        isConnected = false
        nav = [NavEntry(screen: .main)]
    }

    func connect() {
        isConnected = true
    }

    // MARK: - Transferencias (simuladas)

    func send(_ id: Song.ID) {
        guard isConnected,
              let song = songs.first(where: { $0.id == id }),
              status(of: song) == .notOnDevice else { return }

        queue.append(id)
        if transferTask == nil {
            let generation = queueGeneration
            transferTask = Task { [weak self] in
                await self?.runQueue(generation: generation)
            }
        }
    }

    // MARK: - Biblioteca de la Mac

    /// Agrega archivos de audio (⌘O o arrastrados desde el Finder): lee sus datos y portada.
    /// Con el iPod real la biblioteca se guarda y sigue ahí al volver a abrir la app.
    func importFiles(_ urls: [URL]) async {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        importingCount += files.count
        defer { importingCount -= files.count }

        var problems: [String] = []
        var duplicates = 0
        for url in files {
            do {
                let song = try await MacLibraryImporter.importFile(url)
                let already = songs.contains {
                    $0.fileURL?.standardizedFileURL == url.standardizedFileURL
                        || ($0.title == song.title && $0.artist == song.artist && $0.album == song.album)
                }
                if already { duplicates += 1; continue }
                songs.append(song)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        if !isSimulated { MacLibraryStore.save(songs) }

        if duplicates > 0 {
            problems.append(duplicates == 1 ? "1 canción ya estaba en la biblioteca." : "\(duplicates) canciones ya estaban en la biblioteca.")
        }
        if !problems.isEmpty { importMessage = problems.joined(separator: "\n") }
    }

    /// Quita canciones de la biblioteca (el archivo sigue en la Mac).
    func removeSongs(_ ids: Set<Song.ID>) {
        songs.removeAll { ids.contains($0.id) && status(of: $0) != .queued }
        if !isSimulated { MacLibraryStore.save(songs) }
    }

    /// Cambia (o quita, con nil) la portada de todas las canciones de un álbum de la Mac.
    /// La imagen se reduce a ~600 px, igual que las portadas que vienen en los archivos.
    func setArtwork(_ imageData: Data?, forAlbum albumKey: String) {
        let image = imageData.map { MacLibraryImporter.thumbnail($0) ?? $0 }
        for index in songs.indices where songs[index].albumKey == albumKey {
            songs[index].artworkData = image
        }
        if !isSimulated { MacLibraryStore.save(songs) }
    }

    /// Pone la portada en las canciones de la Mac que son las mismas que estas del iPod
    /// (mismo título y artista). Así la portada cambiada en el iPod también se ve en la app.
    func setArtwork(_ imageData: Data, matching tracks: [IPodTrack]) {
        let keys = Set(tracks.map { Self.matchKey(title: $0.title, artist: $0.artist) })
        let indices = songs.indices.filter { keys.contains(Self.matchKey(title: songs[$0].title, artist: songs[$0].artist)) }
        guard !indices.isEmpty else { return }
        let image = MacLibraryImporter.thumbnail(imageData) ?? imageData
        for index in indices { songs[index].artworkData = image }
        if !isSimulated { MacLibraryStore.save(songs) }
    }

    /// Álbumes buscando portada en internet ahora mismo (para mostrar un indicador).
    private(set) var fetchingArtwork: Set<String> = []
    /// Aviso al terminar de buscar portadas.
    var artworkMessage: String?

    /// Busca la portada del álbum en internet y la pone si el álbum y el artista coinciden.
    /// Devuelve false si no encontró una que coincida bien.
    @discardableResult
    func fetchArtwork(forAlbum albumKey: String) async -> Bool {
        guard let song = songs.first(where: { $0.albumKey == albumKey }),
              !fetchingArtwork.contains(albumKey) else { return false }
        fetchingArtwork.insert(albumKey)
        defer { fetchingArtwork.remove(albumKey) }
        do {
            guard let match = try await ArtworkLookup.bestMatch(artist: song.artist, album: song.album) else {
                return false
            }
            let data = try await ArtworkLookup.download(match)
            setArtwork(data, forAlbum: albumKey)
            return true
        } catch {
            return false
        }
    }

    /// Busca en internet la portada de todos los álbumes que no tienen.
    func fetchMissingArtwork() async {
        let keys = Set(songs.filter { $0.artworkData == nil }.map(\.albumKey))
        guard !keys.isEmpty else {
            artworkMessage = "Todos los álbumes ya tienen portada."
            return
        }
        var found = 0
        for key in keys {
            if await fetchArtwork(forAlbum: key) { found += 1 }
        }
        let missing = keys.count - found
        artworkMessage = missing == 0
            ? "Listo: se pusieron \(found) portadas."
            : "Se pusieron \(found) portadas. \(missing) no se encontraron; ponlas a mano con clic derecho › Cambiar portada…"
    }

    func sendAll(_ ids: [Song.ID]) {
        ids.forEach { send($0) }
    }

    func cancelTransfers() {
        queueGeneration += 1
        transferTask?.cancel()
        transferTask = nil
        queue.removeAll()
        transfer = nil
    }

    private func runQueue(generation: Int) async {
        var position = 0
        /// ¿Esta cola sigue siendo la vigente? (false si se canceló y ya empezó otra).
        func isCurrent() -> Bool { !Task.isCancelled && generation == queueGeneration }

        while true {
            while !queue.isEmpty {
                guard isCurrent() else { return }
                let id = queue.removeFirst()
                guard let song = songs.first(where: { $0.id == id }) else { continue }
                position += 1

                transferProgress.value = 0
                withAnimation(.easeOut(duration: 0.2)) {
                    transfer = TransferState(songID: song.id, title: song.title, position: position,
                                             total: position + queue.count)
                }

                if !isSimulated, let realSender {
                    // iPod real: copiar de verdad.
                    let current = position
                    do {
                        try await realSender(song) { [weak self] value in
                            Task { @MainActor in
                                guard let self, self.transfer?.songID == id else { return }
                                // Solo avances de 1 % o más (llegan muchos por segundo).
                                if value >= 1 || abs(value - self.transferProgress.value) >= 0.01 {
                                    self.transferProgress.value = value
                                }
                                let total = current + self.queue.count
                                if self.transfer?.total != total { self.transfer?.total = total }
                            }
                        }
                    } catch {
                        // Cancelada (⌘. o expulsar): cancelTransfers ya limpió todo; no tocar la cola
                        // nueva que pudo haber empezado mientras tanto.
                        if error is CancellationError || !isCurrent() { return }
                        // Se detiene la cola: mejor revisar antes de seguir escribiendo en el iPod.
                        let message = error is CancellationError
                            ? nil
                            : "“\(song.title)”: \(error.localizedDescription)"
                        queue.removeAll()
                        withAnimation(.easeOut(duration: 0.2)) { transfer = nil }
                        transferTask = nil
                        if let message { sendMessage = message }
                        onRealQueueFinished?()
                        return
                    }
                    guard isCurrent() else { return }
                } else {
                    // iPod de prueba: solo la animación.
                    let duration = max(1.8, song.sizeMB * 0.3)
                    let steps = 100
                    for step in 1...steps {
                        try? await Task.sleep(for: .seconds(duration / Double(steps)))
                        guard isCurrent() else { return }
                        transferProgress.value = Double(step) / Double(steps)
                        let total = position + queue.count
                        if transfer?.total != total { transfer?.total = total }
                    }
                }

                if let index = songs.firstIndex(where: { $0.id == id }) {
                    songs[index].isOnDevice = true
                    if !isSimulated { sentIDs.insert(id) }
                }
                recentIDs.removeAll { $0 == id }
                recentIDs.insert(id, at: 0)
            }

            transfer?.finished = true
            if !isSimulated { onRealQueueFinished?() }
            try? await Task.sleep(for: .seconds(1.2))
            guard isCurrent() else { return }

            // Si mandaste más canciones durante la pausa final, se siguen enviando
            // (antes se quedaban "en cola" para siempre).
            if !queue.isEmpty { continue }

            withAnimation(.easeOut(duration: 0.2)) {
                transfer = nil
            }
            transferTask = nil
            return
        }
    }
}
