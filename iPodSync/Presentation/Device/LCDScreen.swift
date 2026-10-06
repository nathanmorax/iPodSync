//
//  LCDScreen.swift
//  iPodSync
//
//  Pantalla del iPod (204 × 152): menús, transferencia, espacio y estado apagado.
//

import SwiftUI

struct LCDScreen: View {
    let simulator: IPodSimulator
    var batteryLevel: Int = 3   // de 4

    @State private var isDropTargeted = false
    @AppStorage(SettingsKey.lcdTint) private var lcdTint = "green"

    private var backlight: Color { Theme.lcdBacklight(for: lcdTint) }

    private var background: Color {
        guard simulator.isConnected else { return Theme.lcdOff }
        return simulator.backlightOn ? backlight : Theme.lcdBackground
    }

    var body: some View {
        ZStack(alignment: .top) {
            background
            if simulator.isConnected {
                PixelGrid()
                VStack(spacing: 0) {
                    statusBar
                    Rectangle()
                        .fill(Theme.lcdInk.opacity(0.7))
                        .frame(height: 1)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: simulator.backlightOn)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.lcdBezel, lineWidth: 1.5)
        )
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .padding(-6)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: simulator.backlightOn && simulator.isConnected ? backlight.opacity(0.5) : .clear, radius: 14)
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(UUID.init(uuidString:))
            for id in ids { simulator.send(id) }
            return !ids.isEmpty && simulator.isConnected
        } isTargeted: { targeted in
            isDropTargeted = targeted && simulator.isConnected
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pantalla del iPod")
        .accessibilityValue(simulator.deletion.map { "Eliminando \($0.title)" }
                            ?? simulator.transfer.map { "Enviando \($0.title)" } ?? simulator.statusTitle)
    }

    @ViewBuilder
    private var content: some View {
        if let deletion = simulator.deletion {
            LCDDeletionView(state: deletion)
                .transition(.opacity)
        } else if let transfer = simulator.transfer {
            LCDTransferView(state: transfer, progress: simulator.transferProgress, simulator: simulator)
                .transition(.opacity)
        } else if simulator.current.screen == .storage {
            LCDStorageView(simulator: simulator)
        } else {
            LCDListView(rows: simulator.rows,
                        selection: simulator.current.selection,
                        scroll: simulator.current.scroll,
                        background: background)
        }
    }

    private var statusBar: some View {
        ZStack {
            HStack {
                Text(simulator.statusTitle)
                    .font(.lcd(6))
                    .tracking(1)
                Spacer()
                BatteryIndicator(level: batteryLevel)
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.lcd(9))
                    .tracking(1)
            }
        }
        .foregroundStyle(Theme.lcdInk)
        .padding(.horizontal, 6)
        .frame(height: 18)
    }
}

// MARK: - Lista

struct LCDListView: View {
    let rows: [LCDRow]
    let selection: Int
    let scroll: Int
    let background: Color

    private var visible: [(offset: Int, element: LCDRow)] {
        Array(Array(rows.enumerated()).dropFirst(scroll).prefix(IPodSimulator.visibleRows))
    }

    var body: some View {
        if rows.isEmpty {
            Text("VACÍO")
                .font(.lcd(7.5))
                .tracking(1.5)
                .foregroundStyle(Theme.lcdInk.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(visible, id: \.element.id) { index, row in
                        LCDMenuRow(row: row, isSelected: index == selection, background: background)
                    }
                }
                if rows.count > IPodSimulator.visibleRows {
                    LCDScrollBar(total: rows.count, scroll: scroll, visible: IPodSimulator.visibleRows)
                }
            }
        }
    }
}

struct LCDMenuRow: View {
    let row: LCDRow
    let isSelected: Bool
    let background: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(row.title.uppercased())
                .tracking(1)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let value = row.value {
                Text(value.uppercased())
            } else if case .open? = row.action {
                Text("›")
            }
        }
        .font(.lcd(7.5))
        .foregroundStyle(isSelected ? background : Theme.lcdInk)
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(isSelected ? Theme.lcdInk : .clear)
    }
}

struct LCDScrollBar: View {
    let total: Int
    let scroll: Int
    let visible: Int

    var body: some View {
        GeometryReader { geo in
            let thumb = max(8, geo.size.height * CGFloat(visible) / CGFloat(total))
            let maxScroll = CGFloat(max(1, total - visible))
            ZStack(alignment: .top) {
                Rectangle().fill(Theme.lcdInk.opacity(0.15))
                Rectangle()
                    .fill(Theme.lcdInk)
                    .frame(height: thumb)
                    .offset(y: (geo.size.height - thumb) * CGFloat(scroll) / maxScroll)
            }
        }
        .frame(width: 3, height: CGFloat(visible) * 19)
        .padding(.trailing, 2)
    }
}

// MARK: - Transferencia

/// Como la pantalla "En reproducción" del iPod classic: "2 de 11", portada a la izquierda,
/// canción / artista / álbum a la derecha y abajo la barra con los MB copiados.
/// Caen notitas ♪ sobre la portada mientras se copia y, al pasar a la siguiente, la portada se voltea.
struct LCDTransferView: View {
    let state: TransferState
    let progress: TransferProgress
    let simulator: IPodSimulator

    /// Una búsqueda por cambio de canción (no por avance: el progreso lo lee solo la barra).
    private var song: Song? { simulator.songs.first { $0.id == state.songID } }

    var body: some View {
        let song = song
        VStack(spacing: 8) {
            Text(state.finished ? "LISTO" : "\(state.position) DE \(state.total)")
                .font(.lcd(6.5, weight: .bold))
                .tracking(1)
            HStack(alignment: .top, spacing: 10) {
                LCDFlippingCover(song: song, finished: state.finished)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title.uppercased())
                        .font(.lcd(8, weight: .bold))
                    Text((song?.artist ?? "").uppercased())
                        .font(.lcd(8))
                    Text((song?.album ?? "").uppercased())
                        .font(.lcd(8))
                        .opacity(0.6)
                }
                .tracking(0.8)
                .lineLimit(1)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LCDTransferProgress(progress: progress, finished: state.finished, sizeMB: song?.sizeMB ?? 0)
        }
        .padding(.horizontal, 12)
        .foregroundStyle(Theme.lcdInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Portada que se voltea al cambiar de canción, con notitas cayendo mientras se copia.
private struct LCDFlippingCover: View {
    let song: Song?
    let finished: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let size: CGFloat = 58

    var body: some View {
        ZStack {
            if let song {
                SongArtworkView(song: song, size: size, cornerRadius: 2)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                    .id(song.id)
                    .transition(flip)
            }
            if !finished && !reduceMotion {
                LCDFallingNotes()
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }

    /// La vieja gira hasta quedar de canto y la nueva entra girando desde el otro lado.
    private var flip: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0))
                .animation(.easeOut(duration: 0.25).delay(0.25)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
                .animation(.easeIn(duration: 0.25))
        )
    }
}

private struct FlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(abs(angle) >= 90 ? 0 : 1)
    }
}

/// Notitas ♪ que caen sobre la portada mientras se copia.
private struct LCDFallingNotes: View {
    /// Columna (pt desde la izquierda) y desfase de cada nota.
    private let notes: [(x: CGFloat, delay: Double)] = [(14, 0), (30, 0.5), (8, 1.0), (24, 1.3)]
    private let cycle = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(notes.indices, id: \.self) { index in
                    let phase = ((time + notes[index].delay) / cycle).truncatingRemainder(dividingBy: 1)
                    Text("♪")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                        .opacity(phase < 0.2 ? phase / 0.2 : (phase > 0.8 ? (1 - phase) / 0.2 : 1))
                        .offset(x: notes[index].x, y: -12 + phase * 70)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

/// "Eliminando 2 de 3", la canción, la misma barra delgada y "No desconectar".
struct LCDDeletionView: View {
    let state: DeletionState

    var body: some View {
        VStack(spacing: 7) {
            Text("ELIMINANDO \(state.position) DE \(state.total)")
                .font(.lcd(6.5, weight: .bold))
                .tracking(1)
            Text(state.title.uppercased())
                .font(.lcd(9))
                .tracking(1.2)
                .lineLimit(1)
                .contentTransition(.opacity)
            Rectangle()
                .strokeBorder(Theme.lcdInk, lineWidth: 1)
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.lcdInk)
                            .frame(width: geo.size.width * Double(state.position) / Double(max(state.total, 1)))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: state.position)
            Text("NO DESCONECTAR")
                .font(.lcd(6.5))
                .tracking(1)
                .opacity(0.7)
        }
        .padding(.horizontal, 16)
        .foregroundStyle(Theme.lcdInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Barra delgada con MB copiados y totales. Es la única vista que lee el progreso, así que
/// solo ella se redibuja con cada avance (no el LCD completo ni la biblioteca).
private struct LCDTransferProgress: View {
    let progress: TransferProgress
    let finished: Bool
    let sizeMB: Double

    var body: some View {
        let value = finished ? 1 : progress.value
        VStack(spacing: 3) {
            Rectangle()
                .strokeBorder(Theme.lcdInk, lineWidth: 1)
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.lcdInk)
                            .frame(width: geo.size.width * min(max(value, 0), 1))
                    }
                }
            HStack {
                Text(megabytes(sizeMB * value))
                Spacer()
                Text(megabytes(sizeMB))
            }
            .font(.lcd(6.5))
            .monospacedDigit()
        }
        .accessibilityHidden(true)
    }

    private func megabytes(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " MB"
    }
}

struct LCDSegmentedBar: View {
    let progress: Double
    var segments = 14

    var body: some View {
        let filled = Int((progress * Double(segments)).rounded(.down))
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(Theme.lcdInk.opacity(i < filled ? 1 : 0.12))
                    .frame(width: 8, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Espacio

struct LCDStorageView: View {
    let simulator: IPodSimulator

    var body: some View {
        VStack(spacing: 9) {
            Text("USADO \(Int((simulator.usedFraction * 100).rounded()))%")
                .font(.lcd(6.5, weight: .bold))
                .tracking(1)
            LCDSegmentedBar(progress: simulator.usedFraction)
            Text(simulator.freeSpaceText.uppercased())
                .font(.lcd(8.5))
                .tracking(1)
            Text("\(simulator.onDeviceSongs.count) CANCIONES")
                .font(.lcd(6.5))
                .tracking(1)
                .opacity(0.7)
        }
        .foregroundStyle(Theme.lcdInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Batería y retícula

struct BatteryIndicator: View {
    let level: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(Theme.lcdInk.opacity(i < level ? 1 : 0.25))
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PixelGrid: View {
    var spacing: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: 0, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Theme.lcdInk.opacity(0.06)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("LCDScreen · menú") {
    LCDScreen(simulator: IPodSimulator())
        .frame(width: 204, height: 152)
        .padding()
}

#Preview("LCDScreen · desconectado") {
    let sim = IPodSimulator()
    sim.eject()
    return LCDScreen(simulator: sim)
        .frame(width: 204, height: 152)
        .padding()
}

#Preview("LCDScreen · enviando (corre solo)") {
    let sim = IPodSimulator()
    sim.sendAll(sim.songs.filter { !$0.isOnDevice }.prefix(2).map(\.id))
    return LCDScreen(simulator: sim)
        .frame(width: 204, height: 152)
        .padding()
}

#Preview("LCDListView · lista") {
    let sim = IPodSimulator()
    return LCDListView(rows: sim.rows(for: .main), selection: 1, scroll: 0, background: Theme.lcdBackground)
        .frame(width: 204, height: 133)
        .background(Theme.lcdBackground)
        .padding()
}

#Preview("LCDMenuRow · fila normal y seleccionada") {
    VStack(spacing: 0) {
        LCDMenuRow(row: LCDRow(id: "a", title: "Canciones", value: "3"), isSelected: false, background: Theme.lcdBackground)
        LCDMenuRow(row: LCDRow(id: "b", title: "Artistas", value: "3"), isSelected: true, background: Theme.lcdBackground)
    }
    .frame(width: 204)
    .background(Theme.lcdBackground)
    .padding()
}

#Preview("LCDScrollBar · barra de desplazamiento") {
    LCDScrollBar(total: 20, scroll: 6, visible: 7)
        .frame(width: 6, height: 130)
        .padding()
        .background(Theme.lcdBackground)
}

#Preview("LCDTransferView · recibiendo canción") {
    LCDTransferView(state: TransferState(songID: MockLibrary.songs[1].id, title: MockLibrary.songs[1].title, position: 1, total: 3),
                    progress: TransferProgress(0.48), simulator: IPodSimulator())
        .frame(width: 204, height: 133)
        .background(Theme.lcdBackground)
        .padding()
}

#Preview("LCDTransferView · listo") {
    LCDTransferView(state: TransferState(songID: MockLibrary.songs[1].id, title: MockLibrary.songs[1].title, position: 3, total: 3, finished: true),
                    progress: TransferProgress(1), simulator: IPodSimulator())
        .frame(width: 204, height: 133)
        .background(Theme.lcdBackground)
        .padding()
}

#Preview("LCDSegmentedBar · bloques de progreso") {
    LCDSegmentedBar(progress: 0.6)
        .padding()
        .background(Theme.lcdBackground)
}

#Preview("LCDStorageView · espacio") {
    LCDStorageView(simulator: IPodSimulator())
        .frame(width: 204, height: 133)
        .background(Theme.lcdBackground)
        .padding()
}

#Preview("BatteryIndicator · batería") {
    BatteryIndicator(level: 3)
        .padding()
        .background(Theme.lcdBackground)
}

#Preview("PixelGrid · textura de píxeles") {
    PixelGrid()
        .frame(width: 204, height: 152)
        .background(Theme.lcdBackground)
        .padding()
}
