//
//  IPodWriteLock.swift
//  iPodSync
//
//  Una sola escritura a la vez en la base del iPod (iTunesDB / ArtworkDB).
//  Cada escritura lee la base, la cambia y la guarda; si dos corrieran juntas (enviar canciones
//  y poner portadas, o dos portadas a la vez) la segunda pisaría lo que hizo la primera.
//

import Foundation

actor IPodWriteLock {
    static let shared = IPodWriteLock()

    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Espera su turno y ejecuta `work`; las demás escrituras esperan a que termine.
    func run<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try work()
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()   // pasa el turno directo al siguiente
        }
    }
}
