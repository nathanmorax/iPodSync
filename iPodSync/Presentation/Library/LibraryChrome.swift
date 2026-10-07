//
//  LibraryChrome.swift
//  iPodSync
//
//  Piezas de la biblioteca que en el diseño AT1 ("una sola ventana de vidrio") viven fuera del
//  panel: el selector En mi Mac | En mi iPod (debajo del iPod) y el buscador (en la barra de arriba).
//

import SwiftUI

/// En mi Mac | En mi iPod, con cuántas canciones hay en cada lado.
struct LibrarySourcePicker: View {
    @Bindable var library: LibraryState
    let simulator: IPodSimulator
    let monitor: IPodMonitor

    @Namespace private var namespace

    private var iPodCount: Int {
        simulator.isSimulated ? simulator.onDeviceSongs.count : monitor.tracks.count
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibrarySource.allCases) { source in
                button(source, count: source == .mac ? simulator.songs.count : iPodCount)
            }
        }
        .padding(2)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ver música")
    }

    private func button(_ source: LibrarySource, count: Int) -> some View {
        let isOn = library.source == source
        return Button {
            withAnimation(.snappy(duration: 0.2)) { library.source = source }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 13))
                Text(source.title)
                    .font(.system(size: 12.5, weight: isOn ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .matchedGeometryEffect(id: "source", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.title), \(count) canciones")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Buscador de la biblioteca (⌘F lo enfoca; Esc lo borra).
struct LibrarySearchField: View {
    @Bindable var library: LibraryState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Buscar", text: $library.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand {
                    library.query = ""
                    focused = false
                }
            if !library.query.isEmpty {
                Button {
                    library.query = ""
                } label: {
                    Label("Borrar búsqueda", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 120, maxWidth: .infinity)
        .frame(height: 30)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Buscar (⌘F)")
        .onChange(of: library.searchFocusRequest) { focused = true }
    }
}
