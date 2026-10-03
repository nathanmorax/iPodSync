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

    var songs: [Song]
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
    @ObservationIgnored private var trackKeys: Set<String> = []
    private(set) var recentIDs: [Song.ID]
    private(set) var nav: [NavEntry] = [NavEntry(screen: .main)]
    private(set) var transfer: TransferState?
    private(set) var queue: [Song.ID] = []

    private var transferTask: Task<Void, Never>?
    private let otherUsedGB: Double

    init(songs: [Song] = MockLibrary.songs) {
        self.songs = songs
        self.recentIDs = songs.filter(\.isOnDevice).map(\.id)
        let musicGB = songs.filter(\.isOnDevice).map(\.sizeMB).reduce(0, +) / 1024
        self.otherUsedGB = MockLibrary.capacityGB - MockLibrary.initialFreeGB - musicGB
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
        if let transfer, transfer.song.id == song.id, !transfer.finished { return .sending(transfer.progress) }
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
            transferTask = Task { [weak self] in
                await self?.runQueue()
            }
        }
    }

    /// Agrega archivos de audio elegidos o arrastrados desde el Finder a la biblioteca.
    @discardableResult
    func addSongs(from urls: [URL]) -> [Song.ID] {
        var added: [Song.ID] = []
        for url in urls where url.isFileURL {
            let title = url.deletingPathExtension().lastPathComponent
            guard !songs.contains(where: { $0.title == title }) else { continue }
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let song = Song(title: title,
                            artist: "Artista desconocido",
                            sizeMB: max(0.1, Double(bytes) / 1_048_576),
                            artworkHue: Double.random(in: 0..<1),
                            isOnDevice: false)
            songs.append(song)
            added.append(song.id)
        }
        return added
    }

    func sendAll(_ ids: [Song.ID]) {
        ids.forEach { send($0) }
    }

    func cancelTransfers() {
        transferTask?.cancel()
        transferTask = nil
        queue.removeAll()
        transfer = nil
    }

    private func runQueue() async {
        var position = 0

        while !queue.isEmpty {
            if Task.isCancelled { return }
            let id = queue.removeFirst()
            guard let song = songs.first(where: { $0.id == id }) else { continue }
            position += 1

            withAnimation(.easeOut(duration: 0.2)) {
                transfer = TransferState(song: song, position: position,
                                         total: position + queue.count, progress: 0)
            }

            let duration = max(1.8, song.sizeMB * 0.3)
            let steps = 100
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
                if Task.isCancelled { return }
                transfer?.progress = Double(step) / Double(steps)
                transfer?.total = position + queue.count
            }

            if let index = songs.firstIndex(where: { $0.id == id }) {
                songs[index].isOnDevice = true
                if !isSimulated { sentIDs.insert(id) }
            }
            recentIDs.removeAll { $0 == id }
            recentIDs.insert(id, at: 0)
        }

        transfer?.finished = true
        try? await Task.sleep(for: .seconds(1.2))
        if Task.isCancelled { return }

        withAnimation(.easeOut(duration: 0.2)) {
            transfer = nil
        }
        transferTask = nil
    }
}
