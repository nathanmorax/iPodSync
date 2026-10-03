//
//  TransferHUD.swift
//  iPodSync
//
//  Tarjeta bajo el iPod con la canción que se está enviando, la cola y el progreso.
//

import SwiftUI

struct TransferHUD: View {
    let simulator: IPodSimulator

    var body: some View {
        ZStack(alignment: .top) {
            if let transfer = simulator.transfer {
                card(transfer)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: simulator.transfer == nil)
    }

    private func card(_ t: TransferState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(t.song.artworkGradient)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(t.finished ? "Listo" : "Enviando \(t.song.title)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(detail(t))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if t.finished {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .font(.title3)
                        .accessibilityHidden(true)
                } else {
                    Text("\(Int(t.progress * 100)) %")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .contentTransition(.numericText())

                    Button {
                        simulator.cancelTransfers()
                    } label: {
                        Label("Cancelar envíos", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.borderless)
                    .help("Cancelar envíos (⌘.)")
                }
            }

            ProgressView(value: t.finished ? 1 : t.progress)
                .progressViewStyle(.linear)
                .tint(t.finished ? Color.green : Color.accentColor)
                .accessibilityLabel("Progreso del envío")
        }
        .padding(12)
        .frame(width: 300)
        .background(WindowDragArea())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func detail(_ t: TransferState) -> String {
        if t.finished {
            return t.total == 1 ? "1 canción enviada" : "\(t.total) canciones enviadas"
        }
        let left = t.total - t.position
        return left > 0
            ? "\(t.position) de \(t.total) · quedan \(left) en cola"
            : "\(t.position) de \(t.total)"
    }
}

#Preview("TransferHUD · progreso bajo el iPod (sin usar, corre solo)") {
    let sim = IPodSimulator()
    sim.sendAll(sim.songs.filter { !$0.isOnDevice }.prefix(2).map(\.id))
    return TransferHUD(simulator: sim)
        .frame(height: 90, alignment: .top)
        .padding(30)
        .background(Wallpaper())
}
