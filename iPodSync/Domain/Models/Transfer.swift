//
//  Transfer.swift
//  iPodSync
//
//  Estado de un envío en curso.
//

import SwiftUI
import Observation

struct TransferState: Equatable {
    var song: Song
    var position: Int
    var total: Int
    var progress: Double
    var finished = false
}
