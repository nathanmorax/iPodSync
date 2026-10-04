//
//  BackupSheet.swift
//  iPodSync
//
//  Hoja para respaldar la música del iPod en la Mac, o restaurarlo desde un respaldo.
//

import SwiftUI
import AppKit

struct BackupSheet: View {
    let viewModel: BackupViewModel
    let monitor: IPodMonitor

    private var deviceName: String { monitor.device?.name ?? "tu iPod" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.mode == .backup ? "externaldrive.badge.timemachine" : "arrow.counterclockwise")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.mode == .backup ? "Respaldar la música de “\(deviceName)”" : "Restaurar “\(deviceName)” desde un respaldo")
                        .font(.headline)
                    Text(viewModel.mode == .backup ? "Una copia exacta en tu Mac, por si algo sale mal." : "Regresa la música del iPod a como estaba.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(viewModel.isRunning)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .ready:
            ready

        case .confirmRestore(let manifest, let url):
            confirmRestore(manifest, url)

        case .preparing:
            running(title: "Contando archivos…", indeterminate: true)

        case .copying:
            running(title: viewModel.mode == .backup ? "Copiando a tu Mac…" : "Copiando al iPod…", indeterminate: false)

        case .verifying:
            running(title: "Revisando que todo se copió completo…", indeterminate: true)

        case .done(let message):
            VStack(alignment: .leading, spacing: 14) {
                Label(message, systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if viewModel.mode == .backup, let folder = viewModel.lastBackupFolder {
                        Button("Mostrar en Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                    }
                    Spacer()
                    Button("Listo") { viewModel.close() }
                        .keyboardShortcut(.defaultAction)
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 14) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cerrar") { viewModel.close() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // MARK: Pasos

    @ViewBuilder
    private var ready: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.mode == .backup {
                Text("Se copia **toda** la carpeta de música del iPod (canciones, listas, reproducciones y portadas) tal como está. Si una prueba sale mal, con “Restaurar desde un respaldo” el iPod regresa a como está hoy.")
                if let device = monitor.device {
                    let used = ByteCountFormatter.string(fromByteCount: max(0, device.totalBytes - device.freeBytes), countStyle: .file)
                    Text("\(monitor.tracks.count) canciones · alrededor de \(used) ocupados en el iPod. Necesitas al menos ese espacio libre en tu Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let device = monitor.device, let date = viewModel.lastBackupDate(for: device.id) {
                    Text("Último respaldo: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Elige la carpeta de un respaldo hecho con iPodSync. Se regresan la base de datos y las portadas del respaldo, y se copian las canciones que falten. Las canciones que agregaste después dejarán de aparecer en el iPod.")
            }
        }
        .fixedSize(horizontal: false, vertical: true)

        HStack {
            Spacer()
            Button("Cancelar") { viewModel.close() }
                .keyboardShortcut(.cancelAction)
            if viewModel.mode == .backup {
                Button("Elegir carpeta y respaldar…") { viewModel.chooseFolderAndBackup(monitor: monitor) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(monitor.accessibleVolumeURL == nil)
            } else {
                Button("Elegir respaldo…") { viewModel.chooseBackupToRestore() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(monitor.accessibleVolumeURL == nil)
            }
        }

        if monitor.accessibleVolumeURL == nil {
            Text("Conecta el iPod y dale acceso para continuar.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func confirmRestore(_ manifest: IPodBackupService.Manifest, _ url: URL) -> some View {
        let size = ByteCountFormatter.string(fromByteCount: manifest.totalBytes, countStyle: .file)
        VStack(alignment: .leading, spacing: 8) {
            Text("Respaldo de “\(manifest.deviceName)” del \(manifest.date.formatted(date: .long, time: .shortened))")
                .fontWeight(.semibold)
            Text("\(manifest.trackCount) canciones · \(manifest.fileCount) archivos · \(size)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if manifest.deviceName != deviceName {
                Label("Este respaldo es de otro iPod (“\(manifest.deviceName)”).", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
            }
            Text("El iPod quedará como en ese respaldo. No desconectes el cable mientras se copia.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)

        HStack {
            Spacer()
            Button("Cancelar") { viewModel.close() }
                .keyboardShortcut(.cancelAction)
            Button("Restaurar", role: .destructive) { viewModel.restore(from: url, monitor: monitor) }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func running(title: String, indeterminate: Bool) -> some View {
        let p = viewModel.progress
        let formatter = ByteCountFormatter()
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
            if indeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: p.fraction)
                    .progressViewStyle(.linear)
                HStack {
                    Text("\(formatter.string(fromByteCount: p.copiedBytes)) de \(formatter.string(fromByteCount: p.totalBytes))")
                    Spacer()
                    Text("\(p.filesDone) de \(p.filesTotal) archivos")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                Text(p.currentFile)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Text("No desconectes el iPod.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
