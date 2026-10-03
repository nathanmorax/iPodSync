//
//  IPodDeviceView.swift
//  iPodSync
//
//  iPod plano: pantalla LCD arriba y rueda de clic abajo.
//

import SwiftUI

struct IPodDeviceView: View {
    let simulator: IPodSimulator

    var body: some View {
        VStack(spacing: 26) {
            LCDScreen(simulator: simulator)
                .frame(width: 204, height: 152)
            ClickWheel(simulator: simulator)
        }
        .padding(16)
        .frame(width: 236, height: 392, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Theme.ipodBody)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.ipodRing, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 30, y: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("iPod classic")
    }
}

// MARK: - Rueda de clic

#Preview("IPodDeviceView · iPod completo") {
    IPodDeviceView(simulator: IPodSimulator())
        .padding(40)
        .background(Theme.stage)
}
