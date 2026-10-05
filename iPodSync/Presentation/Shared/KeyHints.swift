//
//  KeyHints.swift
//  iPodSync
//
//  Atajos de teclado que se muestran bajo el iPod.
//

import SwiftUI
import AppKit

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flechas arriba y abajo para navegar, Return para abrir, Escape para regresar. Arrastra canciones al iPod.")
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

#Preview("KeyHints · atajos bajo el iPod") {
    KeyHints()
        .padding()
}
