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
    /// Número de pista: fila de álbum (sin portada, que ya va en el encabezado del álbum).
    var number: Int? = nil

    @AppStorage(SettingsKey.rowDensity) private var density = "regular"

    private var status: SongSyncStatus { simulator.status(of: song) }
    private var isSelected: Bool { library.selection.contains(song.id) }
    private var compact: Bool { density == "compact" }

    var body: some View {
        HStack(spacing: 10) {
            if let number {
                Text("\(number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 20, alignment: .trailing)
                    .accessibilityHidden(true)
            } else {
                SongArtworkView(song: song, size: compact ? 22 : 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
                    )
                    .accessibilityHidden(true)
            }

            if number != nil {
                // El título toma todo el ancho y la duración va en una columna fija a la derecha,
                // así todos los minutos quedan alineados (antes cada uno quedaba a media fila).
                Text(song.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 44, alignment: .trailing)
            } else if compact {
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

            // Sin ícono de estado: la duración queda pegada a la derecha.
            // (Enviar: doble clic, clic derecho o el botón Enviar del pie.)
            if number == nil { Spacer(minLength: 8) }
        }
        .padding(.leading, indented ? 38 : 12)
        .padding(.trailing, 12)
        .frame(height: number != nil ? 34 : (compact ? 32 : 44))
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
/// Estado de una canción con solo dos SF Symbols: `ipod` (ya está o va para allá)
/// y `laptopcomputer` (solo en la Mac; es botón para enviar).
struct SyncStatusView: View {
    let status: SongSyncStatus
    let canSend: Bool
    let onSend: () -> Void

    @State private var isHovering = false

    var body: some View {
        Group {
            switch status {
            case .onDevice:
                Image(systemName: "ipod")
                    .foregroundStyle(.white)
                    .help("En el iPod")
                    .accessibilityLabel("En el iPod")
                    .transition(.opacity)

            case .sending(let progress):
                // El iPod en azul, latiendo, con un anillo que se llena.
                Image(systemName: "ipod")
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                    .padding(4)
                    .overlay {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .help("Enviando · \(Int(progress * 100)) %")
                    .accessibilityLabel("Enviando, \(Int(progress * 100)) por ciento")

            case .queued:
                Image(systemName: "ipod")
                    .foregroundStyle(.tertiary)
                    .help("En cola para el iPod")
                    .accessibilityLabel("En cola")

            case .notOnDevice:
                // Solo en la Mac. Al pasar el mouse se pinta azul: clic para enviar.
                Button(action: onSend) {
                    Image(systemName: "laptopcomputer")
                        .foregroundStyle(isHovering && canSend ? AnyShapeStyle(TintShapeStyle.tint)
                                                               : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .onHover { isHovering = $0 }
                .help(canSend ? "Solo en tu Mac · clic para enviar al iPod" : "Solo en tu Mac · conecta el iPod para enviar")
                .accessibilityLabel("Solo en tu Mac, enviar al iPod")
            }
        }
        .font(.system(size: 11))
        .animation(.easeOut(duration: 0.2), value: status)
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
        if let url = song.fileURL {
            Button("Mostrar en Finder") {
                let didAccess = url.startAccessingSecurityScopedResource()
                NSWorkspace.shared.activateFileViewerSelecting([url])
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            .disabled(song.isFileMissing)
        }
        Button("Copiar título") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(song.title) — \(song.artist)", forType: .string)
        }
        if song.fileURL != nil || song.bookmark != nil {
            Divider()
            if let library, library.selection.count > 1, library.selection.contains(song.id) {
                Button("Quitar \(library.selection.count) canciones de la biblioteca") {
                    simulator.removeSongs(library.selection)
                    library.clearSelection()
                }
            } else {
                Button("Quitar de la biblioteca") { simulator.removeSongs([song.id]) }
            }
        }
    }
}

/// Portada de una canción de la Mac: la del archivo si tiene, si no un color.
/// `size` nil = cuadrada y del ancho disponible (para la cuadrícula de álbumes).
struct SongArtworkView: View {
    let song: Song
    var size: CGFloat? = 30
    var cornerRadius: CGFloat = 5

    var body: some View {
        // Un cuadro que mide lo que le toca (o `size`) y la imagen se recorta adentro:
        // así una portada que no es cuadrada no empuja ni desborda la celda.
        Color.clear
            .frame(width: size, height: size)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let data = song.artworkData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Rectangle().fill(song.artworkGradient)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview("SongRow · filas de canción") {
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

#Preview("SyncStatusView · los 4 estados") {
    VStack(alignment: .trailing, spacing: 14) {
        SyncStatusView(status: .notOnDevice, canSend: true) {}
        SyncStatusView(status: .queued, canSend: true) {}
        SyncStatusView(status: .sending(0.48), canSend: true) {}
        SyncStatusView(status: .onDevice, canSend: true) {}
    }
    .frame(width: 140)
    .padding()
}

#Preview("SongContextMenu · menú contextual (clic en el botón)") {
    let sim = IPodSimulator()
    return Menu("Menú de \(sim.songs[1].title)") {
        SongContextMenu(song: sim.songs[1], simulator: sim)
    }
    .fixedSize()
    .padding()
}
