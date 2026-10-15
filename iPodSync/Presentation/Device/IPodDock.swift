//
//  IPodDock.swift
//  iPodSync
//
//  Diseño BO3 "dock vacío": un dock blanco siempre visible. Sin iPod se ve vacío con
//  "Conecta tu iPod"; al conectarlo, el iPod baja y se asienta en la ranura.
//  Mientras se envía música, el cable que sale del dock lleva puntitos azules hacia el iPod.
//

import SwiftUI

/// El dock blanco con su ranura y el cable de 30 pines que sale por detrás hacia la orilla.
struct IPodDock: View {
    var isTransferring: Bool
    static let size = CGSize(width: 236, height: 44)

    var body: some View {
        ZStack {
            // Sombra suave sobre el "piso".
            Ellipse()
                .fill(.black.opacity(0.55))
                .frame(width: Self.size.width * 1.05, height: 18)
                .blur(radius: 10)
                .offset(y: Self.size.height / 2 + 2)

            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.925), Color(white: 0.83)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 20,
                                           bottomTrailingRadius: 20, topTrailingRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 0.5)
                )
                .frame(width: Self.size.width, height: Self.size.height)

            // Ranura de arriba (donde entra el conector del iPod).
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.78)],
                                     startPoint: .top, endPoint: .bottom))
                // Mientras se envía música, la ranura brilla azul.
                .overlay(Capsule().fill(.blue.opacity(isTransferring ? 0.5 : 0)))
                .shadow(color: .blue.opacity(isTransferring ? 0.7 : 0), radius: 5)
                .animation(.easeInOut(duration: 0.3), value: isTransferring)
                .frame(width: 64, height: 7)
                .offset(y: -Self.size.height / 2 + 9)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

/// Cable blanco que sale del dock por la izquierda hasta la orilla de la ventana.
/// Con un envío en curso, puntitos azules viajan por el cable hacia el dock.
struct DockCable: View {
    var isTransferring: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.35))
                p.addCurve(to: CGPoint(x: w, y: h * 0.75),
                           control1: CGPoint(x: w * 0.45, y: h * 0.35),
                           control2: CGPoint(x: w * 0.55, y: h * 0.75))
            }
            ZStack {
                path.stroke(Color(white: 0.86), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                if isTransferring && !reduceMotion {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        Canvas { ctx, _ in
                            for i in 0..<4 {
                                let f = (t * 0.6 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
                                if let pt = path.trimmedPath(from: 0, to: f).currentPoint {
                                    let r: CGFloat = 3
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                                             with: .color(.blue))
                                }
                            }
                        }
                    }
                    .shadow(color: .blue.opacity(0.8), radius: 4)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lo que se ve encima del dock vacío.
struct EmptyDockMessage: View {
    let simulated: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Conecta tu iPod")
                .font(.title3.weight(.semibold))
            Text("Ponlo en su dock o conecta el cable.\nSe detecta solo.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(simulated ? "Conectar" : "Elegir iPod…", action: action)
                .buttonStyle(.link)
                .padding(.top, 2)
        }
        .frame(width: 260)
    }
}
