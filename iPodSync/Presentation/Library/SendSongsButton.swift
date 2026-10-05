//
//  SendSongsButton.swift
//  iPodSync
//
//  Botón "Enviar N" de un álbum o artista. Se queda en su lugar mientras se envía
//  (cambia a "Enviando… faltan 5") en vez de desaparecer y volver a aparecer con cada canción.
//

import SwiftUI

struct SendSongsButton: View {
    let songs: [Song]
    let simulator: IPodSimulator
    var prominent = true
    var compact = false
    var help: String = "Enviar al iPod las canciones que faltan"

    /// Las que todavía no están en el iPod (pendientes, en cola o enviándose).
    private var missing: [Song] { songs.filter { simulator.status(of: $0) != .onDevice } }
    private var sendable: [Song.ID] { missing.filter { simulator.status(of: $0) == .notOnDevice }.map(\.id) }
    private var inFlight: Int { missing.count - sendable.count }

    var body: some View {
        let missingCount = missing.count
        // Solo se oculta cuando ya no falta nada; mientras se envía se queda visible.
        if missingCount > 0 {
            let ids = sendable
            let sending = inFlight > 0
            Button {
                simulator.sendAll(ids)
            } label: {
                Text(title(missing: missingCount, sending: sending, sendable: ids.count))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .modifier(SendButtonStyle(prominent: prominent && !sending))
            .controlSize(compact ? .small : .regular)
            .disabled(ids.isEmpty || !simulator.isConnected)
            .animation(.easeOut(duration: 0.2), value: missingCount)
            .help(sending ? "Enviando al iPod…" : help)
        }
    }

    private func title(missing: Int, sending: Bool, sendable: Int) -> String {
        if sending {
            return missing == 1 ? "Enviando la última…" : "Enviando… faltan \(missing)"
        }
        if songs.count == 1 { return "Enviar al iPod" }
        return compact ? "Enviar \(sendable)" : "Enviar \(sendable) al iPod"
    }
}

private struct SendButtonStyle: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
