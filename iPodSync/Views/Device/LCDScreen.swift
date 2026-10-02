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
    }

    @ViewBuilder
    private var content: some View {
        if let transfer = simulator.transfer {
            LCDTransferView(state: transfer)
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

struct LCDTransferView: View {
    let state: TransferState

    var body: some View {
        VStack(spacing: 8) {
            Text(state.finished ? "LISTO" : "RECIBIENDO \(state.position)/\(state.total)")
                .font(.lcd(6.5, weight: .bold))
                .tracking(1)
            Text(state.song.title.uppercased())
                .font(.lcd(9))
                .tracking(1.5)
                .lineLimit(1)
                .padding(.horizontal, 8)
            LCDSegmentedBar(progress: state.finished ? 1 : state.progress)
            HStack(spacing: 2) {
                Text("\(state.finished ? 100 : Int(state.progress * 100))%")
                    .font(.lcd(16, weight: .heavy))
                    .monospacedDigit()
                if !state.finished { BlinkingCursor() }
            }
        }
        .foregroundStyle(Theme.lcdInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct BlinkingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            Rectangle()
                .fill(Theme.lcdInk.opacity(on ? 0.4 : 0.08))
                .frame(width: 8, height: 14)
        }
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

#Preview("Menú") {
    LCDScreen(simulator: IPodSimulator())
        .frame(width: 204, height: 152)
        .padding()
}
