//
//  SettingsView.swift
//  iPodSync
//
//  Ventana de Ajustes (iPodSync › Ajustes…, ⌘,).
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.rowDensity) private var density = "regular"
    @AppStorage(SettingsKey.lcdTint) private var lcdTint = "green"
    @AppStorage(SettingsKey.showKeyHints) private var showKeyHints = true

    var body: some View {
        Form {
            Section {
                Picker("Tamaño de las filas:", selection: $density) {
                    Text("Normal").tag("regular")
                    Text("Compacto").tag("compact")
                }
                .pickerStyle(.radioGroup)
                Text("El color de acento y el tamaño del texto siguen lo que elijas en Ajustes del Sistema › Apariencia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Biblioteca")
            }

            Section {
                Picker("Luz de la pantalla:", selection: $lcdTint) {
                    Label("Verde", systemImage: "circle.fill").foregroundStyle(Theme.lcdBacklight(for: "green")).tag("green")
                    Label("Azul", systemImage: "circle.fill").foregroundStyle(Theme.lcdBacklight(for: "blue")).tag("blue")
                    Label("Ámbar", systemImage: "circle.fill").foregroundStyle(Theme.lcdBacklight(for: "amber")).tag("amber")
                }
                Toggle("Mostrar atajos de teclado bajo el iPod", isOn: $showKeyHints)
            } header: {
                Text("iPod")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("Ajustes")
    }
}

#Preview("SettingsView · Ajustes (⌘,)") {
    SettingsView()
}
