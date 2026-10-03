//
//  IPodDevice.swift
//  iPodSync
//
//  Un iPod real conectado: el disco que macOS montó y lo que sabemos de él.
//

import Foundation

struct IPodDevice: Identifiable, Equatable {
    /// UUID del volumen (o su nombre si no tiene). Sirve para recordar el permiso de acceso.
    let id: String
    /// Nombre del iPod tal como aparece en el Finder ("iPod de Nathan").
    let name: String
    /// Raíz del disco, p. ej. /Volumes/IPOD.
    let volumeURL: URL
    let totalBytes: Int64
    let freeBytes: Int64
    /// Fabricante y modelo que reporta el USB (Disk Arbitration), p. ej. "Apple" / "iPod".
    let vendor: String?
    let model: String?
    /// true cuando pudimos ver la carpeta iPod_Control (prueba de que es un iPod con música).
    let hasIPodControl: Bool

    /// GB como los cuenta el Finder (1 GB = 1.000.000.000 bytes).
    var totalGB: Double { Double(totalBytes) / 1_000_000_000 }
    var freeGB: Double { Double(freeBytes) / 1_000_000_000 }
}
