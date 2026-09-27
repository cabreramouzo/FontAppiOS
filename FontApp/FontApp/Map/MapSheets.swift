import SwiftUI

/// Choosing the base map. A grid of cards, as in Apple Maps' own layer picker.
struct LayersSheet: View {
    @Bindable var controller: MapController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(MapLayer.allCases) { layer in
                        Button {
                            controller.layer = layer
                            dismiss()
                        } label: {
                            LayerCard(layer: layer, selected: controller.layer == layer)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle(L10n.t("map.layers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
    }
}

private struct LayerCard: View {
    let layer: MapLayer
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LayerPreview(layer: layer)
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Label(L10n.t(layer.labelKey), systemImage: layer.systemImage)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(2)
                .frame(minHeight: 36, alignment: .topLeading)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A real tile of the layer, over Moià, so the choice is made by looking and not by name.
private struct LayerPreview: View {
    let layer: MapLayer

    var body: some View {
        if let url = layer.tileURL(z: 14, x: 8286, y: 6060) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.tertiarySystemFill)
            }
        } else {
            ZStack {
                Color(layer == .appleSatellite ? .systemGreen : .systemTeal).opacity(0.25)
                Image(systemName: layer.systemImage).font(.largeTitle).foregroundStyle(.secondary)
            }
        }
    }
}

/// Filters, and the legend of the pin colours next to them.
struct FiltersSheet: View {
    @Binding var filters: MapFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $filters.onlyWithWater) {
                        Label(L10n.plain("map.onlyWater"), systemImage: "drop.fill")
                    }
                    Toggle(isOn: $filters.onlyReliable) {
                        Label(L10n.plain("map.onlyReliable"), systemImage: "checkmark.seal")
                    }
                    Toggle(isOn: $filters.hideNonPotable) {
                        Label {
                            Text(L10n.plain("map.hideNonPotable"))
                            Text(L10n.t("map.hideNonPotableTitle"))
                        } icon: {
                            Image(systemName: "nosign")
                        }
                    }
                    Picker(selection: $filters.source) {
                        Text(L10n.t("map.allTypes")).tag(WaterSource?.none)
                        ForEach([WaterSource.tap, .mountain, .spring, .well, .fountain, .other], id: \.self) { source in
                            Text(L10n.t("source.\(source.rawValue)")).tag(WaterSource?.some(source))
                        }
                    } label: {
                        Label(L10n.t("map.filterType"), systemImage: "square.grid.2x2")
                    }
                }
                Section(L10n.t("legend.waterStatus")) {
                    ForEach(WaterStatus.allCases, id: \.self) { status in
                        LegendRow(color: status.color, text: "\(status.emoji) \(L10n.t(status.labelKey))")
                    }
                    LegendRow(color: WaterStatus.noStatusColor, text: L10n.t("confidence.unverified"))
                }
            }
            .navigationTitle(L10n.t("map.filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if filters.activeCount > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.t("ios.filters.clear")) { filters = MapFilters() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, color)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}
