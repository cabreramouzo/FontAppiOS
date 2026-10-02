import SwiftUI

extension View {
    /// A round (or capsule) glass button that answers on its whole shape. With the glass
    /// applied over a plain button, only the drawn pixels of the label took the tap — the
    /// glyph of "…" or the star — and the rest of the 48 pt circle did nothing (field
    /// test, 02/10/2026). The content shape outside the glass is what gives the area back.
    func glassButton(_ glass: Glass = .regular, in shape: some Shape) -> some View {
        buttonStyle(.plain)
            .glassEffect(glass.interactive(), in: shape)
            .contentShape(shape)
    }
}
