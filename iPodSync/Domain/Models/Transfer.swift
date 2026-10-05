//
//  Transfer.swift
//  iPodSync
//
//  Estado de un envío en curso.
//

import Foundation
import Observation

/// Qué canción se envía y en qué posición de la cola. Cambia una vez por canción.
/// (Ya no guarda la canción completa: copiaba su portada en cada cambio.)
struct TransferState: Equatable {
    var songID: Song.ID
    var title: String
    var position: Int
    var total: Int
    var finished = false
}

/// Progreso (0…1) de la canción que se está enviando. Va aparte porque cambia muchas veces
/// por segundo: así solo lo leen la barra y el porcentaje, no las ~700 filas de la biblioteca.
@Observable
final class TransferProgress {
    var value: Double = 0

    init(_ value: Double = 0) {
        self.value = value
    }
}
