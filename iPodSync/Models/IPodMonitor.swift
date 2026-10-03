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
    /// Mensaje para mostrar en una alerta (no se pudo expulsar, elegiste otra carpeta…).
    var alertMessage: String?

    var isSimulating: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.simulateIPod)
    }

    @ObservationIgnored private weak var simulator: IPodSimulator?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var accessedURL: URL?
    @ObservationIgnored private var didStartAccess = false

    // MARK: - Inicio

    func start(simulator: IPodSimulator) {
        self.simulator = simulator
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
