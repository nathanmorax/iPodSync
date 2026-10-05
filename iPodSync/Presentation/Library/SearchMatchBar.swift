//
//  SearchMatchBar.swift
//  iPodSync
//
//  Dentro de un artista o álbum mientras buscas, como en iTunes: dice cuántas canciones
//  coinciden y deja elegir entre ver solo esas o todas (las que coinciden quedan resaltadas).
//

import SwiftUI

struct SearchMatchBar: View {
    let query: String
    let matchCount: Int
    let total: Int
    @Binding var onlyMatches: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(matchCount) de \(total) coinciden con “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            DarkSegmented(selection: $onlyMatches, options: [true, false], height: 22,
                          fillsWidth: false, title: "Mostrar") { only, isOn in
                Text(only ? "Coincidencias" : "Todas")
                    .font(.system(size: 11, weight: isOn ? .semibold : .regular))
            }
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Qué canciones mostrar dentro de un artista o álbum según la búsqueda.
struct SearchScopedList<Item: LibraryItem & Identifiable> {
    /// Las que se muestran (todas, o solo las que coinciden).
    let shown: [Item]
    /// IDs que coinciden (vacío si no se busca o si coinciden todas).
    let matches: Set<Item.ID>
    let total: Int
    /// Mostrar la barra: se está buscando y no coinciden todas.
    var showsBar: Bool { !matches.isEmpty }

    init(_ items: [Item], query: String, onlyMatches: Bool) {
        total = items.count
        guard SearchMatch.isSearching(query) else {
            shown = items; matches = []; return
        }
        let ids = Set(items.filter { $0.searchMatch(query) != nil }.map(\.id))
        guard ids.count < items.count else {        // coinciden todas: nada que filtrar
            shown = items; matches = []; return
        }
        matches = ids
        shown = onlyMatches ? items.filter { ids.contains($0.id) } : items
    }

    /// Resaltar la fila (solo cuando se ven todas).
    func highlights(_ item: Item) -> Bool {
        shown.count != matches.count && matches.contains(item.id)
    }
}
