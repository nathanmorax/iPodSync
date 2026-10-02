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

struct ClickWheel: View {
    let simulator: IPodSimulator
    private let size: CGFloat = 168

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.wheel)
                .overlay(Circle().strokeBorder(Theme.ipodRing, lineWidth: 1))

            wheelButton("Menú, regresar", offset: CGSize(width: 0, height: -62), action: simulator.back) {
                Text("MENU")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
            }
            wheelButton("Subir", offset: CGSize(width: -62, height: 0), action: simulator.moveUp) {
                Image(systemName: "backward.fill")
            }
            wheelButton("Bajar", offset: CGSize(width: 62, height: 0), action: simulator.moveDown) {
                Image(systemName: "forward.fill")
            }
            wheelButton("Luz", offset: CGSize(width: 0, height: 62), action: simulator.toggleBacklight) {
                Image(systemName: "playpause.fill")
            }

            Button(action: simulator.select) {
                Circle()
                    .fill(Theme.ipodBody)
                    .overlay(Circle().strokeBorder(Theme.ipodRing, lineWidth: 1))
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Seleccionar")
        }
        .frame(width: size, height: size)
        .disabled(!simulator.isConnected)
    }

    private func wheelButton<Label: View>(_ name: String,
                                          offset: CGSize,
                                          action: @escaping () -> Void,
                                          @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 11))
                .foregroundStyle(Theme.wheelLabel)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .offset(offset)
        .accessibilityLabel(name)
    }
}

/// Oscurece ligeramente al presionar, sin el fondo de botón estándar.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview {
    IPodDeviceView(simulator: IPodSimulator())
        .padding(40)
        .background(Theme.stage)
}
