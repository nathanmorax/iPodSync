//
//  DarkSegmented.swift
//  iPodSync
//
//  Control segmentado oscuro (mismo estilo que "En mi Mac | En mi iPod"):
//  fondo negro translúcido y la opción elegida en blanco suave que se desliza.
//

import SwiftUI

struct DarkSegmented<Value: Hashable, Content: View>: View {
    @Binding var selection: Value
    let options: [Value]
    var height: CGFloat = 26
    /// true = las opciones se reparten el ancho; false = cada una mide lo que su contenido.
    var fillsWidth = true
    /// Nombre del grupo para VoiceOver ("Ver por", "Álbumes por fila").
    var title: String = ""
    let label: (Value, Bool) -> Content

    @Namespace private var namespace

    init(selection: Binding<Value>,
         options: [Value],
         height: CGFloat = 26,
         fillsWidth: Bool = true,
         title: String = "",
         @ViewBuilder label: @escaping (Value, Bool) -> Content) {
        _selection = selection
        self.options = options
        self.height = height
        self.fillsWidth = fillsWidth
        self.title = title
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func segment(_ option: Value) -> some View {
        let isOn = selection == option
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = option }
        } label: {
            label(option, isOn)
                .foregroundStyle(isOn ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, fillsWidth ? 0 : 8)
                .frame(height: height)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.white.opacity(0.16))
                            .matchedGeometryEffect(id: "selected", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
