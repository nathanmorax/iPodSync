//
//  DevicePane.swift
//  iPodSync
//
//  Mitad derecha: el iPod (pantalla + rueda) y su estado. Expulsar está en la barra de herramientas.
//

import SwiftUI
import AppKit

struct DevicePane: View {
    let simulator: IPodSimulator
    @AppStorage(SettingsKey.showKeyHints) private var showKeyHints = true

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                IPodDeviceView(simulator: simulator)
                    .opacity(simulator.isConnected ? 1 : 0.55)
                    .saturation(simulator.isConnected ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: simulator.isConnected)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if simulator.isConnected && showKeyHints {
                    KeyHints()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .background(Theme.stage)
        .contentShape(Rectangle())
        .onTapGesture {
            // Quita el foco del buscador para que las flechas del teclado lleguen al iPod.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private var caption: String {
        guard simulator.isConnected else { return "iPod expulsado · ya puedes desconectarlo" }
        let pending = simulator.pendingCount
        return pending > 0
            ? "Cola: \(pending) · \(simulator.freeSpaceText)"
            : "iPod classic · \(simulator.freeSpaceText)"
    }
}

/// Atajos de teclado visibles bajo el iPod.
struct KeyHints: View {
    var body: some View {
        HStack(spacing: 14) {
            hint(["↑", "↓"], "navegar")
            hint(["↩"], "abrir")
            hint(["esc"], "atrás")
            Text("arrastra al iPod")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.cardStroke, lineWidth: 0.5)
                    )
            }
            Text(label)
        }
    }
}

#Preview {
    DevicePane(simulator: IPodSimulator())
        .frame(width: 520, height: 660)
}
