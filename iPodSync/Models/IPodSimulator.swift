//
//  IPodSimulator.swift
//  iPodSync
//
//  Estado del iPod simulado: conexión, navegación del LCD y cola de transferencias (mock).
//

import SwiftUI
import Observation

enum LCDScreenID: Equatable {
    case main, recents, songs, artists, storage, settings

    var title: String {
        switch self {
        case .main:     "TONO"
        case .recents:  "RECIENTES"
        case .songs:    "CANCIONES"
        case .artists:  "ARTISTAS"
        case .storage:  "ESPACIO"
        case .settings: "AJUSTES"
        }
    }
}

enum LCDRowAction: Equatable {
    case open(LCDScreenID)
    case toggleBacklight
}

struct LCDRow: Identifiable, Equatable {
    let id: String
    let title: String
    var value: String? = nil
    var action: LCDRowAction? = nil
}

struct TransferState: Equatable {
    var song: Song
    var position: Int
    var total: Int
    var progress: Double
    var finished = false
}

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
        songs.filter(\.isOnDevice).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    var recentSongs: [Song] {
        recentIDs.compactMap { id in songs.first { $0.id == id } }
    }

    var artists: [(name: String, count: Int)] {
        Dictionary(grouping: onDeviceSongs, by: \.artist)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var musicGB: Double { onDeviceSongs.map(\.sizeMB).reduce(0, +) / 1024 }
    var freeGB: Double { MockLibrary.capacityGB - otherUsedGB - musicGB }
    var usedOtherFraction: Double { otherUsedGB / MockLibrary.capacityGB }
    var usedMusicFraction: Double { musicGB / MockLibrary.capacityGB }
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
                LCDRow(id: "songs",    title: "Canciones", value: "\(onDeviceSongs.count)", action: .open(.songs)),
                LCDRow(id: "artists",  title: "Artistas",  value: "\(artists.count)", action: .open(.artists)),
                LCDRow(id: "storage",  title: "Espacio",   action: .open(.storage)),
                LCDRow(id: "settings", title: "Ajustes",   action: .open(.settings))
            ]
        case .recents:
            return recentSongs.map { LCDRow(id: $0.id.uuidString, title: $0.title) }
        case .songs:
            return onDeviceSongs.map { LCDRow(id: $0.id.uuidString, title: $0.title) }
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
        if song.isOnDevice { return .onDevice }
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
