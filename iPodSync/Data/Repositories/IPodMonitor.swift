//
//  IPodMonitor.swift
//  iPodSync
//
//  Detecta el iPod real: al abrir la app revisa los discos montados y después escucha cuando
//  macOS monta o desmonta uno. También pide/recuerda el permiso de acceso y expulsa el iPod.
//
//  Con "Simular un iPod" (Ajustes) todo esto se ignora y la app usa el iPod de prueba.
//

import SwiftUI
import AppKit
import DiskArbitration
import Observation

@MainActor
@Observable
final class IPodMonitor {
    /// El iPod conectado ahora (nil si no hay).
    private(set) var device: IPodDevice?
    /// Ya tenemos permiso del sandbox para entrar al disco del iPod.
    private(set) var hasAccess = false
    private(set) var isEjecting = false
    /// Canciones leídas del iPod (iTunesDB).
    private(set) var tracks: [IPodTrack] = []
    private(set) var isLoadingTracks = false
    /// Portadas del iPod (ArtworkDB + .ithmb); se crea al leer la música.
    private(set) var artwork: IPodArtworkStore?
    /// Por qué no se pudo leer la música (nil si todo bien).
    private(set) var tracksError: String?
    /// Mensaje para mostrar en una alerta (no se pudo expulsar, elegiste otra carpeta…).
    var alertMessage: String?

    var isSimulating: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.simulateIPod)
    }

    @ObservationIgnored private weak var simulator: IPodSimulator?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var accessedURL: URL?
    @ObservationIgnored private var didStartAccess = false
    @ObservationIgnored private var tracksDeviceID: String?
    @ObservationIgnored private var tracksTask: Task<Void, Never>?

    // MARK: - Inicio

    func start(simulator: IPodSimulator) {
        self.simulator = simulator
        // Con el iPod real, "Enviar" copia de verdad (ver writeToIPod).
        simulator.realSender = { [weak self] song, progress in
            guard let self else { throw CancellationError() }
            try await self.writeToIPod(song, progress: progress)
        }
        simulator.onRealQueueFinished = { [weak self] in self?.reloadTracks() }
        if let problem = MacLibraryStore.takeLoadProblem() { alertMessage = problem }
        guard observers.isEmpty else { rescan(); return }

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescan() }
            }
            observers.append(token)
        }
        rescan()
    }

    /// Vuelve a buscar el iPod y actualiza la app. Se llama sola al montar/desmontar discos.
    func rescan() {
        let found = isSimulating ? nil : findIPod()

        if found?.id != device?.id { stopAccess() }
        device = found

        if let found, accessedURL == nil, let url = VolumeAccess.resolve(for: found.id) {
            startAccess(url)
        }
        hasAccess = accessedURL != nil

        // Con permiso ya podemos ver iPod_Control y el espacio exacto.
        if hasAccess, let current = device, let url = accessedURL {
            device = describe(volume: url, id: current.id) ?? current
        }

        simulator?.attach(device: device, simulated: isSimulating)

        // Música del iPod: se lee una vez por iPod conectado (o con "Volver a leer").
        if let device, hasAccess, let url = accessedURL {
            if tracksDeviceID != device.id { loadTracks(from: url, deviceID: device.id) }
        } else if tracksDeviceID != nil || !tracks.isEmpty {
            clearTracks()
        }
    }

    /// Raíz del iPod con permiso de acceso (nil si no hay iPod o falta el permiso).
    var accessibleVolumeURL: URL? {
        hasAccess ? (accessedURL ?? device?.volumeURL) : nil
    }

    // MARK: - Escribir en el iPod

    enum WriteToIPodError: LocalizedError {
        case noAccess
        case needsBackup
        case classicNotSupported
        case fileMissing(String)

        var errorDescription: String? {
            switch self {
            case .noAccess:
                return "Conecta el iPod y dale acceso antes de enviar."
            case .needsBackup:
                return "Antes de copiar música, haz un respaldo del iPod (menú iPod › Respaldar la música del iPod…)."
            case .classicNotSupported:
                return "Los iPod classic necesitan una firma especial en su base de datos que todavía no soportamos. No se cambió nada."
            case .fileMissing(let name):
                return "No se encuentra el archivo de “\(name)” en tu Mac. ¿Lo moviste o lo borraste?"
            }
        }
    }

    /// ¿Hay un respaldo hecho con iPodSync para este iPod?
    private func hasBackup(for deviceID: String) -> Bool {
        let all = UserDefaults.standard.dictionary(forKey: SettingsKey.lastIPodBackups) as? [String: Date]
        return all?[deviceID] != nil
    }

    /// Copia una canción al iPod real y la agrega a su base de datos.
    func writeToIPod(_ song: Song, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let volume = accessibleVolumeURL, let device else { throw WriteToIPodError.noAccess }
        guard hasBackup(for: device.id) else { throw WriteToIPodError.needsBackup }
        if let model = IPodInfoReader.read(volume: volume).modelName,
           model.localizedCaseInsensitiveContains("classic") {
            throw WriteToIPodError.classicNotSupported
        }

        // El permiso para leer el archivo vive en su bookmark.
        var source = song.fileURL
        if let bookmark = song.bookmark {
            var stale = false
            source = (try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                               relativeTo: nil, bookmarkDataIsStale: &stale)) ?? source
        }
        guard let source else { throw WriteToIPodError.fileMissing(song.title) }

        let track = IPodTrackWriter.NewTrack(
            title: song.title,
            artist: song.artist,
            album: song.albumName,
            genre: song.genre,
            trackNumber: song.trackNumber,
            year: song.year,
            durationMs: Int((song.durationSeconds ?? 0) * 1000),
            sizeBytes: Int64(song.sizeMB * 1_048_576),
            fileExtension: song.fileFormat ?? source.pathExtension
        )

        let artwork = song.artworkData
        let work = Task.detached(priority: .userInitiated) {
            // Una escritura a la vez en la base del iPod (ver IPodWriteLock).
            try await IPodWriteLock.shared.run {
                let didAccess = source.startAccessingSecurityScopedResource()
                defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
                let realSize = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
                var exact = track
                if let realSize { exact.sizeBytes = realSize }
                let added = try IPodTrackWriter.add(source: source, track: exact, volume: volume, progress: progress)
                // La portada es un extra: si falla, la canción ya quedó bien en el iPod.
                if let artwork {
                    do {
                        try IPodArtworkWriter.addArtwork(volume: volume, dbid: added.dbid, imageData: artwork)
                    } catch {
                        print("No se pudo poner la portada de \(exact.title): \(error.localizedDescription)")
                    }
                }
            }
        }
        // Cancelar envíos (⌘.) o expulsar detiene la copia; la base del iPod no se toca a medias.
        try await withTaskCancellationHandler {
            _ = try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    // MARK: - Portadas que faltan

    private(set) var isWritingArtwork = false

    /// Canciones del iPod sin portada cuya portada sí tenemos en la biblioteca de la Mac.
    private func missingArtworkJobs() -> [(dbid: UInt64, image: Data)] {
        guard let simulator else { return [] }
        let images = simulator.artworkByKey
        return tracks.compactMap { track in
            guard !track.hasArtwork, track.dbid != 0,
                  let image = images[IPodSimulator.matchKey(title: track.title, artist: track.artist)] else { return nil }
            return (dbid: track.dbid, image: image)
        }
    }

    var missingArtworkCount: Int { missingArtworkJobs().count }

    /// Portada de la misma canción en la biblioteca de la Mac (más nítida que la del iPod).
    func macArtwork(for track: IPodTrack) -> Data? {
        // Búsqueda directa en el índice (antes recorría todas las canciones de la Mac por cada portada).
        simulator?.artworkByKey[IPodSimulator.matchKey(title: track.title, artist: track.artist)]
    }

    /// Pone en el iPod las portadas de las canciones que llegaron sin ella.
    func addMissingArtwork() {
        guard let volume = accessibleVolumeURL, let device else {
            alertMessage = WriteToIPodError.noAccess.localizedDescription
            return
        }
        guard hasBackup(for: device.id) else {
            alertMessage = WriteToIPodError.needsBackup.localizedDescription
            return
        }
        let jobs = missingArtworkJobs()
        guard !jobs.isEmpty else {
            alertMessage = "No hay canciones del iPod sin portada que tengan portada en tu biblioteca."
            return
        }
        isWritingArtwork = true
        Task {
            let (added, failed): (Int, Int) = await Task.detached(priority: .userInitiated) {
                // Espera su turno si se están enviando canciones u otra portada.
                (try? await IPodWriteLock.shared.run {
                    var ok = 0, bad = 0
                    for job in jobs {
                        do {
                            try IPodArtworkWriter.addArtwork(volume: volume, dbid: job.dbid, imageData: job.image)
                            ok += 1
                        } catch {
                            print("Portada: \(error.localizedDescription)")
                            bad += 1
                        }
                    }
                    return (ok, bad)
                }) ?? (0, jobs.count)
            }.value
            isWritingArtwork = false
            reloadTracks()
            alertMessage = failed == 0
                ? "Se agregaron \(added) portadas. Expulsa el iPod para verlas en él."
                : "Se agregaron \(added) portadas; \(failed) no se pudieron agregar."
        }
    }

    // MARK: - Cambiar la portada de un álbum del iPod

    /// Álbumes del iPod (clave artista|álbum) a los que se les está poniendo portada.
    private(set) var updatingArtworkAlbums: Set<String> = []

    /// Pone `imageData` como portada de esas canciones del iPod (reemplaza la que tuvieran).
    func replaceArtwork(albumKey: String, tracks: [IPodTrack], imageData: Data) {
        guard let volume = accessibleVolumeURL, let device else {
            alertMessage = WriteToIPodError.noAccess.localizedDescription
            return
        }
        guard hasBackup(for: device.id) else {
            alertMessage = WriteToIPodError.needsBackup.localizedDescription
            return
        }
        let dbids = tracks.map(\.dbid).filter { $0 != 0 }
        guard !dbids.isEmpty, !updatingArtworkAlbums.contains(albumKey) else { return }
        // Misma resolución que las portadas de la Mac; el iPod la reduce a 100 y 200 px.
        let image = MacLibraryImporter.thumbnail(imageData) ?? imageData

        updatingArtworkAlbums.insert(albumKey)
        Task {
            let (failed, firstError): (Int, String?) = await Task.detached(priority: .userInitiated) {
                do {
                    // Espera su turno si se están enviando canciones u otra portada.
                    return try await IPodWriteLock.shared.run {
                        var bad = 0
                        var first: String?
                        for dbid in dbids {
                            do {
                                try IPodArtworkWriter.addArtwork(volume: volume, dbid: dbid, imageData: image)
                            } catch {
                                print("[Portada] dbid \(dbid): \(error.localizedDescription)")
                                bad += 1
                                if first == nil { first = error.localizedDescription }
                            }
                        }
                        return (bad, first)
                    }
                } catch {
                    return (dbids.count, error.localizedDescription)
                }
            }.value
            updatingArtworkAlbums.remove(albumKey)

            // Si estas canciones también están en tu Mac, la app mostraba la portada de la Mac
            // (es más nítida) y parecía que el cambio en el iPod no había funcionado.
            // Ahora la de la Mac se cambia igual, para que las dos coincidan.
            if failed < dbids.count {
                simulator?.setArtwork(imageData, matching: tracks)
            }
            reloadTracks()

            if failed > 0 {
                var message = failed == dbids.count
                    ? "No se pudo cambiar la portada en el iPod."
                    : "No se pudo cambiar la portada de \(failed) de \(dbids.count) canciones."
                if let firstError { message += "\n\n\(firstError)" }
                alertMessage = message
            }
        }
    }

    // MARK: - Eliminar canciones del iPod

    /// Canciones que se están borrando (sus filas se ven tenues mientras tanto).
    private(set) var deletingTrackIDs: Set<UInt32> = []
    /// Aviso chico al terminar ("Se eliminaron 3 canciones · 11,8 MB liberados").
    var notice: String?

    /// Pregunta y, si dices que sí, borra esas canciones del iPod.
    /// Devuelve true si se empezó a borrar (para limpiar la selección).
    @discardableResult
    func confirmAndDelete(_ tracks: [IPodTrack]) -> Bool {
        let tracks = tracks.filter { !deletingTrackIDs.contains($0.id) }
        guard !tracks.isEmpty else { return false }
        let keys = simulator?.macKeys ?? []
        let missing = tracks.filter { !(simulator?.hasOnMac($0, keys: keys) ?? false) }.count
        guard DeleteConfirmation.ask(titles: tracks.map(\.title),
                                     bytes: tracks.map(\.sizeBytes).reduce(0, +),
                                     missingOnMac: missing) else { return false }
        return delete(tracks)
    }

    private func delete(_ tracks: [IPodTrack]) -> Bool {
        guard let volume = accessibleVolumeURL, let device else {
            alertMessage = WriteToIPodError.noAccess.localizedDescription
            return false
        }
        guard hasBackup(for: device.id) else {
            alertMessage = "Antes de eliminar música, haz un respaldo del iPod (menú iPod › Respaldar la música del iPod…)."
            return false
        }
        if let model = IPodInfoReader.read(volume: volume).modelName,
           model.localizedCaseInsensitiveContains("classic") {
            alertMessage = WriteToIPodError.classicNotSupported.localizedDescription
            return false
        }

        let ids = Set(tracks.map(\.id))
        let total = tracks.count
        let simulator = self.simulator
        withAnimation(.easeOut(duration: 0.25)) { deletingTrackIDs.formUnion(ids) }
        withAnimation(.easeOut(duration: 0.2)) {
            simulator?.deletion = DeletionState(title: tracks[0].title, position: 1, total: total)
        }

        Task {
            let result: Result<IPodTrackWriter.RemovedTracks, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    // Espera su turno si se están enviando canciones o poniendo portadas.
                    return .success(try await IPodWriteLock.shared.run {
                        try IPodTrackWriter.remove(trackIDs: ids, volume: volume) { position, title in
                            Task { @MainActor in
                                simulator?.deletion = DeletionState(title: title, position: position, total: total)
                            }
                        }
                    })
                } catch {
                    return .failure(error)
                }
            }.value

            // Un momento con la barra llena antes de quitar la pantalla.
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.easeOut(duration: 0.2)) { simulator?.deletion = nil }

            switch result {
            case .success(let removed):
                // Ya se confirmó en la base: se quitan de la lista sin volver a leer todo el iPod
                // (así no se pierde dónde estabas).
                withAnimation(.easeOut(duration: 0.3)) {
                    self.tracks.removeAll { ids.contains($0.id) }
                    deletingTrackIDs.subtract(ids)
                }
                simulator?.setDeviceTracks(self.tracks)
                simulator?.forgetDeviceTracks(tracks)
                rescan()   // espacio libre actualizado

                var text = removed.count == 1 ? "Se eliminó 1 canción" : "Se eliminaron \(removed.count) canciones"
                if removed.freedBytes > 0 {
                    text += " · \(ByteCountFormatter.string(fromByteCount: removed.freedBytes, countStyle: .file)) liberados"
                }
                notice = text
                if removed.leftoverFiles > 0 {
                    alertMessage = "Las canciones ya no están en el iPod, pero \(removed.leftoverFiles) archivo(s) no se pudieron borrar y siguen ocupando espacio."
                }
            case .failure(let error):
                withAnimation { deletingTrackIDs.subtract(ids) }
                alertMessage = "No se eliminó nada.\n\n\(error.localizedDescription)"
                reloadTracks()
            }
        }
        return true
    }

    // MARK: - Música del iPod

    /// Vuelve a leer la base de datos del iPod (menú iPod › Volver a leer la música).
    func reloadTracks() {
        guard let device, let url = accessedURL else { return }
        loadTracks(from: url, deviceID: device.id)
    }

    private func loadTracks(from volume: URL, deviceID: String) {
        tracksTask?.cancel()
        tracksDeviceID = deviceID
        isLoadingTracks = true
        tracksError = nil
        artwork = IPodArtworkStore(volume: volume)

        tracksTask = Task {
            // Leer y descifrar el archivo fuera del hilo principal (puede tener miles de canciones).
            let result: Result<[IPodTrack], Error> = await Task.detached(priority: .userInitiated) {
                Result { try ITunesDBReader.readTracks(volume: volume) }
            }.value
            guard !Task.isCancelled, tracksDeviceID == deviceID else { return }

            isLoadingTracks = false
            switch result {
            case .success(let list):
                tracks = list.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            case .failure(let error):
                tracks = []
                tracksError = error.localizedDescription
            }
            simulator?.setDeviceTracks(tracks)
        }
    }

    private func clearTracks() {
        tracksTask?.cancel()
        tracksDeviceID = nil
        tracks = []
        artwork = nil
        isLoadingTracks = false
        tracksError = nil
        simulator?.setDeviceTracks([])
    }

    // MARK: - Buscar el iPod entre los discos montados

    private static let volumeKeys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeUUIDStringKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeIsInternalKey, .volumeIsRootFileSystemKey
    ]

    private func findIPod() -> IPodDevice? {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.volumeKeys,
                                                            options: [.skipHiddenVolumes]) ?? []
        for url in volumes {
            let values = try? url.resourceValues(forKeys: Set(Self.volumeKeys))
            if values?.volumeIsRootFileSystem == true || values?.volumeIsInternal == true { continue }

            let id = values?.volumeUUIDString ?? values?.volumeLocalizedName ?? url.lastPathComponent
            guard let device = describe(volume: url, id: id) else { continue }

            let usb = (device.vendor ?? "").localizedCaseInsensitiveContains("apple")
                   && (device.model ?? "").localizedCaseInsensitiveContains("ipod")
            if usb || device.hasIPodControl || VolumeAccess.hasBookmark(for: id) {
                return device
            }
        }
        return nil
    }

    private func describe(volume url: URL, id: String) -> IPodDevice? {
        let values = try? url.resourceValues(forKeys: Set(Self.volumeKeys))
        let disk = Self.diskDescription(for: url)
        let controlPath = url.appendingPathComponent("iPod_Control").path

        return IPodDevice(
            id: id,
            name: values?.volumeLocalizedName ?? url.lastPathComponent,
            volumeURL: url,
            totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
            freeBytes: Int64(values?.volumeAvailableCapacity ?? 0),
            vendor: disk.vendor,
            model: disk.model,
            hasIPodControl: FileManager.default.fileExists(atPath: controlPath)
        )
    }

    /// Fabricante y modelo del disco según el USB (no necesita permiso para entrar al disco).
    private static func diskDescription(for volume: URL) -> (vendor: String?, model: String?) {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let info = DADiskCopyDescription(disk) as? [String: Any] else {
            return (nil, nil)
        }
        let vendor = (info[kDADiskDescriptionDeviceVendorKey as String] as? String)?
            .trimmingCharacters(in: .whitespaces)
        let model = (info[kDADiskDescriptionDeviceModelKey as String] as? String)?
            .trimmingCharacters(in: .whitespaces)
        return (vendor, model)
    }

    // MARK: - Permiso de acceso (sandbox)

    /// Abre el diálogo de macOS para que la persona elija su iPod y dé acceso.
    /// Si ya lo detectamos, el diálogo abre directo en él; si no, en la lista de discos.
    func requestAccess() {
        let panel = NSOpenPanel()
        panel.title = "Dar acceso al iPod"
        panel.message = device.map { "Elige “\($0.name)” y da clic en Dar acceso. iPodSync lo usará para leer y copiar música." }
            ?? "Elige el disco de tu iPod y da clic en Dar acceso."
        panel.prompt = "Dar acceso"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = device?.volumeURL ?? URL(fileURLWithPath: "/Volumes", isDirectory: true)

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.grantAccess(selected: url)
        }
    }

    private func grantAccess(selected url: URL) {
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeUUIDStringKey, .volumeLocalizedNameKey]
        let values = try? url.resourceValues(forKeys: keys)
        let volumeRoot = values?.volume ?? url

        // Tiene que ser el disco completo, no una carpeta dentro de él.
        guard url.standardizedFileURL.path == volumeRoot.standardizedFileURL.path,
              url.path != "/" else {
            alertMessage = "Elige el disco del iPod completo (en la barra lateral, bajo Ubicaciones), no una carpeta dentro de él."
            return
        }

        let id = device?.id ?? values?.volumeUUIDString ?? values?.volumeLocalizedName ?? url.lastPathComponent
        let name = values?.volumeLocalizedName ?? url.lastPathComponent
        do {
            try VolumeAccess.save(url, for: id)
            stopAccess()
            startAccess(url)
            rescan()
            if device == nil || device?.hasIPodControl == false {
                alertMessage = "“\(name)” no tiene la carpeta iPod_Control. Puede que no sea un iPod o que necesite restaurarse."
            }
        } catch {
            alertMessage = "No se pudo guardar el permiso: \(error.localizedDescription)"
        }
    }

    private func startAccess(_ url: URL) {
        // Si "start" devuelve false (p. ej. justo después del diálogo, que ya dio acceso), igual cuenta.
        didStartAccess = url.startAccessingSecurityScopedResource()
        accessedURL = url
    }

    private func stopAccess() {
        if didStartAccess { accessedURL?.stopAccessingSecurityScopedResource() }
        didStartAccess = false
        accessedURL = nil
    }

    // MARK: - Expulsar

    var canEject: Bool {
        (simulator?.isConnected ?? false) && !isEjecting
    }

    /// Expulsar desde la barra, el menú iPod (⌘E) o el Dock.
    func eject() {
        if isSimulating {
            guard let simulator else { return }
            withAnimation { simulator.eject() }
            return
        }
        guard let device, !isEjecting else { return }
        simulator?.cancelTransfers()
        isEjecting = true
        let url = device.volumeURL
        let name = device.name

        Task {
            let failure: String? = await Task.detached {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value

            isEjecting = false
            if let failure {
                alertMessage = "No se pudo expulsar “\(name)”. Cierra lo que lo esté usando (por ejemplo, una ventana del Finder copiando archivos) y vuelve a intentarlo.\n\n\(failure)"
            } else {
                stopAccess()
                rescan()   // macOS también avisa con didUnmount; esto solo lo hace inmediato
            }
        }
    }

    /// "Conectar" solo existe con el iPod simulado; el real se conecta con el cable.
    func connectSimulated() {
        guard isSimulating, let simulator else { return }
        withAnimation { simulator.connect() }
    }
}
