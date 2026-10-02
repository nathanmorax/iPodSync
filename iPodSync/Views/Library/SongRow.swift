//
//  SongRow.swift
//  iPodSync
//

import SwiftUI
import AppKit

struct SongRow: View {
    let song: Song
    let subtitle: String
    var indented = false
    let simulator: IPodSimulator
    let library: LibraryState
    /// Orden visible de la lista, para seleccionar rangos con ⇧‑clic.
    let order: [Song.ID]

    @AppStorage(SettingsKey.rowDensity) private var density = "regular"

    private var status: SongSyncStatus { simulator.status(of: song) }
    private var isSelected: Bool { library.selection.contains(song.id) }
    private var compact: Bool { density == "compact" }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(song.artworkGradient)
                .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            if compact {
                HStack(spacing: 8) {
                    Text(song.title).fontWeight(.medium).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            SyncStatusView(status: status, canSend: simulator.isConnected) {
                simulator.send(song.id)
            }
            .frame(width: 108, alignment: .trailing)
        }
        .padding(.leading, indented ? 38 : 12)
        .padding(.trailing, 12)
        .frame(height: compact ? 32 : 44)
        .background(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        .contentShape(Rectangle())
        // Doble clic envía; un clic selecciona (⌘ agrega, ⇧ rango).
        .onTapGesture(count: 2) { simulator.send(song.id) }
        .onTapGesture { library.click(song.id, in: order) }
        .draggable(song.id.uuidString) {
            Label(song.title, systemImage: "music.note")
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu { SongContextMenu(song: song, simulator: simulator, library: library) }
        .animation(.easeOut(duration: 0.2), value: status == .onDevice)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(song.title), \(subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Indicador del estado de sincronización a la derecha de cada fila.
struct SyncStatusView: View {
    let status: SongSyncStatus
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        switch status {
        case .onDevice:
            Label {
                Text("En el iPod")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
            }
            .font(.caption)
            .foregroundStyle(Theme.onDeviceGreen)
            .transition(.opacity)

        case .sending(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .frame(width: 44)
                Text("\(Int(progress * 100)) %")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Enviando, \(Int(progress * 100)) por ciento")

        case .queued:
            Label("En cola", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .notOnDevice:
            Button("Enviar", action: onSend)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canSend)
                .help(canSend ? "Enviar al iPod" : "Conecta el iPod para enviar")
        }
    }
}

/// Menú contextual compartido por filas y portadas.
struct SongContextMenu: View {
    let song: Song
    let simulator: IPodSimulator
    var library: LibraryState? = nil

    var body: some View {
        if let library, library.selection.count > 1, library.selection.contains(song.id) {
            Button("Enviar \(library.selection.count) canciones al iPod") {
                simulator.sendAll(Array(library.selection))
            }
            .disabled(!simulator.isConnected)
        } else {
            Button("Enviar al iPod") { simulator.send(song.id) }
                .disabled(!simulator.canSend(song))
        }
        Divider()
        Button("Copiar título") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(song.title) — \(song.artist)", forType: .string)
        }
    }
}

#Preview {
    let sim = IPodSimulator()
    let lib = LibraryState()
    return LibraryCard {
        SongRow(song: sim.songs[0], subtitle: "9,6 MB", simulator: sim, library: lib, order: [])
        Divider()
        SongRow(song: sim.songs[1], subtitle: "8,7 MB", simulator: sim, library: lib, order: [])
    }
    .padding()
    .frame(width: 480)
}
