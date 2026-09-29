import MapKit
import SwiftUI

/// "Without signal": save what the map shows, then optionally its map and photos; and the
/// zones already saved.
struct OfflineZonesSheet: View {
    let controller: MapController

    @Environment(OfflineZones.self) private var zones
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .idle
    @State private var justSaved: OfflineZone?
    @State private var clearedMaps = false

    private static let cacheSize = ByteCountFormatter.string(fromByteCount: Int64(MapTileCache.maxBytes), countStyle: .file)

    enum Step: Equatable {
        case idle
        case savingFountains
        case savingTiles(fraction: Double, of: Int)
        case savingPhotos(done: Int, of: Int)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.t("zonaOff.intro")).foregroundStyle(.secondary)
                    Button(action: saveFountains) {
                        HStack {
                            Label(L10n.t("zonaOff.save"), systemImage: "arrow.down.circle.fill")
                            if step == .savingFountains { Spacer(); ProgressView() }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(isBusy)
                    if case .failed(let message) = step {
                        Text(message).foregroundStyle(.red)
                    }
                }
                if let zone = justSaved.flatMap({ z in zones.zones.first { $0.id == z.id } }) {
                    extras(for: zone)
                }
                if !zones.zones.isEmpty {
                    Section(L10n.t("ios.offline.saved")) {
                        ForEach(zones.zones) { ZoneRow(zone: $0) }
                            .onDelete { offsets in
                                let ids = offsets.map { zones.zones[$0].id }
                                Task { for id in ids { await zones.delete(id) } }
                            }
                    }
                }
                // The tiles the map has drawn stay on the phone and are not asked for twice.
                Section(L10n.t("ios.mapCache.title")) {
                    Text(L10n.t("ios.mapCache.body", ["size": Self.cacheSize])).font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.t("ios.mapCache.clear")) {
                        Task { await MapTileCache.clear(); clearedMaps = true }
                    }
                    .frame(minHeight: 44)
                    .disabled(clearedMaps)
                }
                Section {
                    Text(L10n.t("zonaOff.note")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.t("zonaOff.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .interactiveDismissDisabled(isBusy)
        }
    }

    /// Step two, offered with its size once the fountains are saved.
    @ViewBuilder private func extras(for zone: OfflineZone) -> some View {
        Section {
            Label(L10n.t("zonaOff.saved", ["n": zone.fonts.count]), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            tilesRow(for: zone)
            photosRow(for: zone)
        }
    }

    @ViewBuilder private func tilesRow(for zone: OfflineZone) -> some View {
        let layer = controller.layer
        if zone.tileLayer != nil {
            Label(L10n.t("zonaOff.tilesSaved", ["n": zone.tileResources ?? zone.tiles.count, "mb": megabytes(zone.tileBytes)]),
                  systemImage: "map.fill")
        } else if case .savingTiles(let fraction, let total) = step {
            ProgressView(value: fraction) {
                Text(L10n.t("zonaOff.savingTiles", ["n": total]))
            }
        } else if !layer.canSaveOffline {
            // Apple's map cannot be kept, and OpenTopoMap asks not to be bulk-downloaded.
            Text(L10n.t("ios.offline.layerCannot", ["layer": L10n.t(layer.labelKey)]))
                .font(.footnote).foregroundStyle(.secondary)
        } else if let box = zone.box {
            let plan = OfflineZones.tilePlan(box: box, zoom: controller.zoom, layer: layer)
            if plan.tiles > OfflineZones.maxTiles {
                Text(L10n.t("ios.offline.tooManyTiles")).font(.footnote).foregroundStyle(.secondary)
            } else {
                Button {
                    saveTiles(plan, layer: layer, zone: zone)
                } label: {
                    Label(L10n.t("zonaOff.saveTiles", ["n": plan.tiles, "mb": megabytes(plan.estimatedBytes)]),
                          systemImage: "map")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disabled(isBusy)
            }
        }
    }

    @ViewBuilder private func photosRow(for zone: OfflineZone) -> some View {
        let count = zone.fonts.filter { $0.image != nil }.count
        if !zone.photos.isEmpty {
            Label(L10n.t("zonaOff.photosSaved", ["n": zone.photos.count, "mb": megabytes(zone.photoBytes)]),
                  systemImage: "photo.fill")
        } else if case .savingPhotos(let done, let total) = step {
            ProgressView(value: Double(done), total: Double(total)) {
                Text(L10n.t("zonaOff.savingPhotos", ["n": total]))
            }
        } else if count > 0 {
            Button {
                savePhotos(zone: zone, count: count)
            } label: {
                Label(L10n.t("zonaOff.savePhotos", ["n": count, "mb": megabytes(count * OfflineZones.photoKB * 1024)]),
                      systemImage: "photo")
                    .frame(minHeight: 44, alignment: .leading)
            }
            .disabled(isBusy)
        }
    }

    private var isBusy: Bool {
        switch step {
        case .savingFountains, .savingTiles, .savingPhotos: true
        default: false
        }
    }

    private func saveFountains() {
        guard let box = controller.visibleBox else { return }
        step = .savingFountains
        Task {
            let name = await placeName(for: box)
            do {
                justSaved = try await zones.saveFountains(in: box, name: name)
                step = .idle
            } catch OfflineZones.SaveError.empty {
                step = .failed(L10n.t("zonaOff.empty"))
            } catch {
                step = .failed(L10n.t("zonaOff.failed"))
            }
        }
    }

    private func saveTiles(_ plan: OfflineZones.TilePlan, layer: MapLayer, zone: OfflineZone) {
        step = .savingTiles(fraction: 0, of: plan.tiles)
        Task {
            do {
                try await zones.saveTiles(plan, layer: layer, for: zone.id) { done in
                    step = .savingTiles(fraction: done, of: plan.tiles)
                }
                step = .idle
            } catch {
                step = .failed(L10n.t("zonaOff.tilesFailed"))
            }
        }
    }

    private func savePhotos(zone: OfflineZone, count: Int) {
        step = .savingPhotos(done: 0, of: count)
        Task {
            do {
                try await zones.saveThePhotos(of: zone.id) { done in
                    Task { @MainActor in step = .savingPhotos(done: done, of: count) }
                }
                step = .idle
            } catch {
                step = .failed(L10n.t("zonaOff.photosFailed"))
            }
        }
    }

    /// The town at the centre, so a list of zones reads "Moià" and not two dates.
    private func placeName(for box: MapBox) async -> String {
        let center = CLLocation(latitude: (box.minLat + box.maxLat) / 2, longitude: (box.minLong + box.maxLong) / 2)
        if let request = MKReverseGeocodingRequest(location: center),
           let item = try? await request.mapItems.first,
           let city = item.addressRepresentations?.cityName ?? item.name {
            return city
        }
        return Date.now.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ZoneRow: View {
    let zone: OfflineZone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(zone.name).font(.headline)
            Text(details).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        var parts = [L10n.t("zonaOff.saved", ["n": zone.fonts.count])]
        if let raw = zone.tileLayer, let layer = MapLayer(rawValue: raw) {
            parts.append("\(L10n.t(layer.labelKey)) · \(megabytes(zone.tileBytes)) MB")
        }
        if !zone.photos.isEmpty { parts.append("\(zone.photos.count) 📷") }
        parts.append(zone.savedAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}

private func megabytes(_ bytes: Int) -> String {
    (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(1)))
}
