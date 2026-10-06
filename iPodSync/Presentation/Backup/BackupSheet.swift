//
//  BackupSheet.swift
//  iPodSync
//
//  Ventana de Respaldo: un respaldo por iPod que se actualiza (solo copia lo nuevo), los días
//  guardados para regresar el iPod a uno de ellos, y "Limpiar…" para lo que ya borraste.
//

import SwiftUI
import AppKit

struct BackupSheet: View {
    let viewModel: BackupViewModel
    let monitor: IPodMonitor

    private var deviceName: String { monitor.device?.name ?? "tu iPod" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(20)
        .frame(width: 480)
        .task(id: viewModel.loadToken) { await viewModel.load(monitor: monitor) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.mode == .backup ? "externaldrive.badge.timemachine" : "clock.arrow.circlepath")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Respaldo de “\(deviceName)”")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if case .chooseDay = viewModel.phase { return "Elige a qué día quieres regresar el iPod." }
        if viewModel.mode == .restore, viewModel.days.isEmpty { return "Regresa la música del iPod a como estaba." }
        if let last = viewModel.days.first {
            return "Último respaldo: \(last.date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Todavía no tienes respaldo de este iPod."
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                Text("Revisando qué hay que copiar…")
                ProgressView().progressViewStyle(.linear)
                HStack {
                    Spacer()
                    Button("Cancelar") { viewModel.close() }
                        .keyboardShortcut(.cancelAction)
                }
            }

        case .ready:
            if monitor.accessibleVolumeURL == nil {
                notConnected
            } else if viewModel.mode == .backup {
                summary
            } else {
                legacyRestore
            }

        case .chooseDay:
            chooseDay

        case .confirmRestore(let manifest, let url):
            confirmRestore(manifest, url)

        case .preparing:
            running(title: "Contando archivos…", indeterminate: true)

        case .copying:
            running(title: viewModel.mode == .backup ? "Copiando lo nuevo a tu Mac…" : "Primero se guarda lo de hoy en el respaldo…",
                    indeterminate: false)

        case .verifying:
            running(title: "Revisando que todo se copió completo…", indeterminate: true)

        case .restoring:
            running(title: "Regresando el iPod…", indeterminate: false)

        case .done(let message):
            VStack(alignment: .leading, spacing: 14) {
                Label(message, systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let folder = viewModel.lastBackupFolder {
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

    // MARK: Sin iPod

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conecta el iPod y dale acceso para continuar.")
                .foregroundStyle(.red)
            HStack {
                Spacer()
                Button("Cerrar") { viewModel.close() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: Resumen (Respaldar / Actualizar)

    @ViewBuilder
    private var summary: some View {
        let preview = viewModel.preview
        VStack(alignment: .leading, spacing: 12) {
            if let folder = viewModel.folder {
                folderRow(folder)
            } else {
                Text("Se crea **una carpeta para este iPod**. La primera vez se copia todo; las siguientes, solo lo nuevo.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let preview, !preview.isFirst {
                    BackupStat(value: "\(preview.songsToCopy)",
                               label: preview.songsToCopy == 1 ? "canción nueva" : "canciones nuevas",
                               tint: preview.songsToCopy > 0 ? .green : .primary)
                    BackupStat(value: bytes(preview.bytesToCopy), label: "por copiar")
                    BackupStat(value: "\(preview.songsAlready)", label: "ya están")
                } else {
                    BackupStat(value: "\(preview?.songsOnIPod ?? monitor.tracks.count)", label: "canciones")
                    BackupStat(value: bytes(preview?.bytesToCopy ?? usedOnIPod), label: "por copiar")
                }
            }

            if !viewModel.days.isEmpty {
                daysSummary
            }

            if let preview, !preview.isFirst {
                HStack {
                    Text(preview.goneSongs > 0
                         ? "Ocupa \(bytes(preview.backupBytes)) · \(preview.goneSongs) \(preview.goneSongs == 1 ? "canción ya no está" : "canciones ya no están") en el iPod"
                         : "Ocupa \(bytes(preview.backupBytes))")
                    Spacer()
                    if preview.goneSongs > 0 {
                        Button("Limpiar…") { viewModel.cleanGoneSongs(monitor: monitor) }
                            .buttonStyle(.link)
                            .help("Quitar del respaldo las canciones que ya borraste del iPod")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        HStack {
            Spacer()
            Button("Cancelar") { viewModel.close() }
                .keyboardShortcut(.cancelAction)
            Button(primaryTitle) { viewModel.backUp(monitor: monitor) }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryTitle: String {
        if viewModel.folder == nil { return "Elegir carpeta y respaldar…" }
        return (viewModel.preview?.isFirst ?? true) ? "Respaldar todo" : "Actualizar respaldo"
    }

    private func folderRow(_ folder: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("\(folder.deletingLastPathComponent().lastPathComponent) › **\(folder.lastPathComponent)**")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Cambiar…") { viewModel.changeFolder(monitor: monitor) }
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Carpeta del respaldo: \(folder.lastPathComponent)")
    }

    private var daysSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DÍAS GUARDADOS · \(viewModel.days.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(viewModel.days.prefix(3)) { day in
                HStack {
                    Text(day.date.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    Text("\(day.trackCount) canciones")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
            Button("Ver todos y restaurar…") { viewModel.showDays() }
                .buttonStyle(.link)
                .font(.callout)
                .padding(.leading, 8)
        }
    }

    private var usedOnIPod: Int64 {
        guard let device = monitor.device else { return 0 }
        return max(0, device.totalBytes - device.freeBytes)
    }

    // MARK: Elegir el día

    @ViewBuilder
    private var chooseDay: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(viewModel.days) { day in
                    let isOn = viewModel.selectedDay == day
                    Button {
                        viewModel.select(day)
                    } label: {
                        HStack {
                            Text(day.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text("\(day.trackCount) canciones")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.accentColor.opacity(0.22) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(4)
        }
        .frame(height: min(CGFloat(viewModel.days.count) * 30 + 10, 190))
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

        if let error = viewModel.dayPreviewError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.callout)
        } else if let day = viewModel.selectedDay, let preview = viewModel.dayPreview {
            dayChanges(day, preview)
        }

        HStack {
            if viewModel.mode == .backup {
                Button("Atrás") { viewModel.backToSummary() }
            } else {
                Button("Cancelar") { viewModel.close() }
                    .keyboardShortcut(.cancelAction)
            }
            Button("Otro respaldo…") { viewModel.chooseBackupToRestore() }
                .help("Restaurar desde otra carpeta de respaldo (por ejemplo, uno de los de antes)")
            Spacer()
            // Sin atajo de Return: cambia la música del iPod, que sea un clic a propósito.
            Button(restoreTitle, role: .destructive) { viewModel.restoreSelectedDay(monitor: monitor) }
                .disabled(!canRestore)
        }
    }

    private var restoreTitle: String {
        guard let day = viewModel.selectedDay else { return "Regresar" }
        return "Regresar al \(day.date.formatted(.dateTime.day().month(.wide)))"
    }

    private var canRestore: Bool {
        guard monitor.accessibleVolumeURL != nil, let preview = viewModel.dayPreview else { return false }
        return !preview.comeBack.isEmpty || !preview.goAway.isEmpty
    }

    private func dayChanges(_ day: IPodBackupService.Day, _ preview: IPodBackupService.DayPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Si regresas al \(day.date.formatted(date: .long, time: .omitted)):")
                .fontWeight(.semibold)
            if preview.comeBack.isEmpty && preview.goAway.isEmpty {
                Text("El iPod ya está igual que ese día.")
                    .foregroundStyle(.secondary)
            }
            if !preview.comeBack.isEmpty {
                change("＋ \(count(preview.comeBack.count)) \(preview.comeBack.count == 1 ? "vuelve" : "vuelven")",
                       names: preview.comeBack, tint: .green)
            }
            if !preview.goAway.isEmpty {
                change("－ \(count(preview.goAway.count)) se \(preview.goAway.count == 1 ? "quita" : "quitan")",
                       names: preview.goAway, tint: .orange, note: "siguen guardadas en el respaldo")
            }
            if preview.missing > 0 {
                Label("\(count(preview.missing)) de ese día no \(preview.missing == 1 ? "está" : "están") en el respaldo y no van a volver.",
                      systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
            }
            Text("Antes se actualiza el respaldo, así lo de hoy también queda guardado.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func change(_ title: String, names: [String], tint: Color, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(tint)
            Text([listOfNames(names), note].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func count(_ n: Int) -> String { n == 1 ? "1 canción" : "\(n) canciones" }

    private func listOfNames(_ names: [String]) -> String {
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) y \(names.count - 3) más" : shown
    }

    // MARK: Respaldos viejos

    @ViewBuilder
    private var legacyRestore: some View {
        Text("Todavía no hay un respaldo de este iPod con días guardados. Puedes elegir la carpeta de un respaldo hecho antes con iPodSync.")
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Cancelar") { viewModel.close() }
                .keyboardShortcut(.cancelAction)
            Button("Elegir respaldo…") { viewModel.chooseBackupToRestore() }
                .keyboardShortcut(.defaultAction)
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
            // Sin atajo de Return: restaurar borra la música actual del iPod, que sea un clic a propósito.
            Button("Restaurar", role: .destructive) { viewModel.restore(from: url, monitor: monitor) }
        }
    }

    // MARK: Copiando

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

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// Cuadrito con un número grande y su descripción (canciones nuevas, por copiar…).
private struct BackupStat: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
