//
//  DeleteConfirmation.swift
//  iPodSync
//
//  "¿Eliminar … del iPod?" antes de borrar. Es una ventana de alerta aparte (NSAlert):
//  una hoja oscurecería toda la ventana transparente del emulador.
//

import AppKit
import SwiftUI

enum DeleteConfirmation {
    /// Devuelve true si la persona elige eliminar.
    /// - missingOnMac: cuántas de esas canciones NO están en la biblioteca de la Mac
    ///   (esas se perderían para siempre).
    @MainActor
    static func ask(titles: [String], bytes: Int64, missingOnMac: Int) -> Bool {
        guard let first = titles.first else { return false }
        let alert = NSAlert()
        alert.alertStyle = missingOnMac > 0 ? .critical : .warning
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)

        if titles.count == 1 {
            alert.messageText = "¿Eliminar “\(first)” del iPod?"
            alert.informativeText = missingOnMac > 0
                ? "Esta canción no está en tu Mac: si la eliminas ya no la vas a tener."
                : "Se borra del iPod y de sus listas. La canción sigue en tu Mac y la puedes volver a enviar."
        } else {
            let shown = titles.prefix(3).map { "“\($0)”" }
            let names = titles.count > 3
                ? shown.joined(separator: ", ") + " y \(titles.count - 3) más"
                : ListFormatter.localizedString(byJoining: shown)
            var text = "\(names) · \(size)."
            if missingOnMac == titles.count {
                text += "\nNinguna está en tu Mac: si las eliminas ya no las vas a tener."
            } else if missingOnMac > 0 {
                text += "\n\(missingOnMac) de ellas no \(missingOnMac == 1 ? "está" : "están") en tu Mac: si las eliminas ya no las vas a tener."
            } else {
                text += "\nSiguen en tu Mac y las puedes volver a enviar."
            }
            alert.messageText = "¿Eliminar \(titles.count) canciones del iPod?"
            alert.informativeText = text
        }
        alert.informativeText += "\n\nAntes se guarda una copia de la base del iPod."

        let delete = alert.addButton(withTitle: titles.count == 1 ? "Eliminar del iPod" : "Eliminar \(titles.count) canciones")
        delete.hasDestructiveAction = true
        // Return no borra por accidente: hay que dar clic en el botón rojo.
        delete.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancelar")
        cancel.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Borrar del iPod lo seleccionado en "En mi iPod" (tecla Delete o clic derecho).
@MainActor
enum IPodDeletion {
    /// Tecla Delete: si hay canciones seleccionadas en "En mi iPod", pregunta y las borra.
    /// Devuelve true si la tecla se usó para esto (si no, sigue siendo "atrás" en el iPod).
    static func deleteSelection(library: LibraryState, simulator: IPodSimulator, monitor: IPodMonitor) -> Bool {
        guard library.source == .iPod else { return false }
        if simulator.isSimulated {
            let songs = simulator.onDeviceSongs.filter { library.selection.contains($0.id) }
            guard !songs.isEmpty else { return false }
            // Después de la tecla: la alerta no debe abrirse dentro del manejo del teclado.
            DispatchQueue.main.async { deleteSimulated(songs, simulator: simulator, library: library) }
            return true
        }
        let tracks = monitor.tracks.filter { library.iPodSelection.contains($0.id) }
        guard !tracks.isEmpty else { return false }
        DispatchQueue.main.async {
            if monitor.confirmAndDelete(tracks) { library.clearIPodSelection() }
        }
        return true
    }

    /// iPod de prueba: la misma pregunta, y solo se quita la marca de "en el iPod".
    static func deleteSimulated(_ songs: [Song], simulator: IPodSimulator, library: LibraryState?) {
        guard !songs.isEmpty else { return }
        let bytes = Int64(songs.map(\.sizeMB).reduce(0, +) * 1_048_576)
        guard DeleteConfirmation.ask(titles: songs.map(\.title), bytes: bytes, missingOnMac: 0) else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            simulator.removeFromSimulatedIPod(Set(songs.map(\.id)))
        }
        library?.clearSelection()
    }
}
