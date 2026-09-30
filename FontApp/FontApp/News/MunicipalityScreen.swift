import MapKit
import SwiftUI

/// The municipal endpoint searches exact names and returns every matching INE code.
/// A name alone cannot safely choose between same-named municipalities.
struct MunicipalitySearchScreen: View {
    @State private var name = ""
    @State private var candidates: [MunicipalityCandidate]?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                TextField(L10n.t("zones.locality"), text: $name)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                Button {
                    Task { await search() }
                } label: {
                    Label(L10n.t("muni.search"), systemImage: "magnifyingglass")
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || loading)
            } footer: {
                Text(L10n.t("muni.lead"))
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let error { Text(error).foregroundStyle(.secondary) }
            if let candidates {
                if candidates.isEmpty {
                    ContentUnavailableView(L10n.t("muni.notFound"), systemImage: "building.2")
                } else {
                    Section {
                        ForEach(candidates) { candidate in
                            NavigationLink {
                                MunicipalityScreen(ine: candidate.ine)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(candidate.municipality)
                                    Text("INE \(candidate.ine) · \(L10n.t("zones.fonts", ["n": candidate.fonts.formatted()]))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.t("muni.inventory"))
    }

    private func search() async {
        loading = true
        defer { loading = false }
        do {
            candidates = try await APIClient.shared.municipalities(named: name.trimmingCharacters(in: .whitespacesAndNewlines))
            error = nil
        } catch { self.error = ErrorText.describe(error) }
    }
}

struct MunicipalityScreen: View {
    let ine: String
    @State private var report: MunicipalReport?
    @State private var error: String?
    @State private var filter = MunicipalFilter.all
    @State private var search = ""
    @State private var csvURL: URL?
    @State private var geoJSONURL: URL?

    private var visible: [MunicipalFont] {
        (report?.items ?? []).filter { filter.includes($0) &&
            (search.isEmpty || L10n.fontName($0.name).localizedStandardContains(search)) }
            .sorted { $0.priority > $1.priority }
    }

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button(L10n.t("error.retry")) { Task { await load() } }
                }
            } else if let report {
                Section {
                    Text(L10n.t("muni.lead")).foregroundStyle(.secondary)
                    LabeledContent(L10n.t("muni.inventory"), value: report.fonts.formatted())
                    LabeledContent(L10n.t("muni.neverChecked"), value: report.neverChecked.formatted())
                    LabeledContent(L10n.t("muni.noPhoto"), value: (report.fonts - report.withPhoto).formatted())
                    LabeledContent(L10n.t("muni.openReports"), value: report.openReports.formatted())
                    ProgressView(value: Double(report.checkedEver), total: Double(max(report.fonts, 1))) {
                        Text(L10n.t("muni.checked"))
                    }
                }
                Section(L10n.t("muni.priorities")) {
                    let urgent = report.items.filter { $0.openReports > 0 || $0.recentlyUnavailable || $0.needsReview }
                        .sorted { $0.priority > $1.priority }.prefix(6)
                    if urgent.isEmpty {
                        Text(L10n.t("muni.noPriorities")).foregroundStyle(.secondary)
                    } else {
                        ForEach(urgent) { font in fountainRow(font) }
                    }
                }
                Section(L10n.t("muni.map")) {
                    if !visible.isEmpty {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: visible[0].latitude, longitude: visible[0].longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))) {
                            ForEach(visible) { font in
                                Annotation(L10n.fontName(font.name), coordinate: CLLocationCoordinate2D(
                                    latitude: font.latitude, longitude: font.longitude)) {
                                        NavigationLink(value: font.id) {
                                            Image(systemName: "drop.fill")
                                                .padding(8)
                                                .background(.regularMaterial, in: Circle())
                                        }
                                    }
                            }
                        }
                        .frame(height: 260)
                    }
                }
                Section {
                    Picker(L10n.t("muni.list"), selection: $filter) {
                        ForEach(MunicipalFilter.allCases) { value in
                            Text(L10n.t(value.labelKey)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(L10n.t("muni.showing", ["n": visible.count, "total": report.fonts]))
                        .font(.caption).foregroundStyle(.secondary)
                    if visible.isEmpty {
                        Text(L10n.t("muni.noResults"))
                    } else {
                        ForEach(visible) { font in fountainRow(font) }
                    }
                } header: { Text(L10n.t("muni.list")) }
                Section { Text(L10n.t("muni.drinkableNote")).font(.footnote).foregroundStyle(.secondary) }
                Section {
                    Text(L10n.t("muni.downloadNote")).font(.footnote).foregroundStyle(.secondary)
                    if let csvURL {
                        ShareLink(item: csvURL) { Label("CSV", systemImage: "square.and.arrow.up") }
                    }
                    if let geoJSONURL {
                        ShareLink(item: geoJSONURL) { Label("GeoJSON", systemImage: "square.and.arrow.up") }
                    }
                    Text(L10n.t("muni.licence")).font(.caption).foregroundStyle(.secondary)
                } header: { Text(L10n.t("muni.download")) }
            } else { ProgressView().frame(maxWidth: .infinity) }
        }
        .searchable(text: $search, prompt: L10n.t("muni.search"))
        .navigationTitle(report.map { L10n.t("muni.title", ["name": $0.municipality]) } ?? L10n.t("muni.inventory"))
        .navigationDestination(for: UUID.self) { FontDetailView(fontID: $0) }
        .refreshable { await load() }
        .task(id: ine) { await load() }
    }

    private func fountainRow(_ font: MunicipalFont) -> some View {
        NavigationLink(value: font.id) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.fontName(font.name))
                Text(font.days.map { L10n.t("muni.checkedAgo", ["d": $0]) } ?? L10n.t("muni.neverCheckedRow"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
    }

    private func load() async {
        do {
            let result = try await APIClient.shared.municipality(ine)
            report = result
            csvURL = try? MunicipalExport.csv(result)
            geoJSONURL = try? MunicipalExport.geoJSON(result)
            error = nil
        }
        catch { self.error = ErrorText.describe(error) }
    }
}

private enum MunicipalExport {
    static func csv(_ report: MunicipalReport) throws -> URL {
        let header = "id,nombre,latitud,longitud,tipo,potabilidad_declarada,tiene_foto,resenas,ultimo_estado,dias_desde_la_ultima,incidencias_abiertas\n"
        let rows = report.items.map { font in
            [font.id.uuidString, font.name ?? "", String(font.latitude), String(font.longitude),
             font.source ?? "", font.drinkable ?? "", font.hasPhoto ? "sí" : "no",
             String(font.reviews), font.lastStatus ?? "", font.days.map(String.init) ?? "",
             String(font.openReports)].map(escape).joined(separator: ",")
        }.joined(separator: "\n")
        return try write(Data((header + rows + "\n").utf8), name: "\(report.ine)-fuentes.csv")
    }

    static func geoJSON(_ report: MunicipalReport) throws -> URL {
        let features: [[String: Any]] = report.items.map { font in
            ["type": "Feature",
             "geometry": ["type": "Point", "coordinates": [font.longitude, font.latitude]],
             "properties": ["id": font.id.uuidString, "nombre": font.name as Any? ?? NSNull(),
                            "tipo": font.source as Any? ?? NSNull(),
                            "potabilidad_declarada": font.drinkable as Any? ?? NSNull(),
                            "tiene_foto": font.hasPhoto, "resenas": font.reviews,
                            "ultimo_estado": font.lastStatus as Any? ?? NSNull(),
                            "incidencias_abiertas": font.openReports]]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "FeatureCollection",
            "name": "Fuentes de \(report.municipality) (INE \(report.ine))",
            "attribution": "FontApp y sus colaboradores · OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)",
            "features": features
        ], options: [.prettyPrinted, .sortedKeys])
        return try write(data, name: "\(report.ine)-fuentes.geojson")
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func write(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private enum MunicipalFilter: String, CaseIterable, Identifiable {
    case all, open, unavailable, review, never, stale, noPhoto, available

    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .all: "muni.filterAll"
        case .open: "muni.openReports"
        case .unavailable: "muni.unavailableRecent"
        case .review: "muni.needsReview"
        case .never: "muni.neverChecked"
        case .stale: "muni.staleShort"
        case .noPhoto: "muni.noPhoto"
        case .available: "muni.availableRecent"
        }
    }

    func includes(_ font: MunicipalFont) -> Bool {
        switch self {
        case .all: true
        case .open: font.openReports > 0
        case .unavailable: font.recentlyUnavailable
        case .review: font.needsReview
        case .never: font.days == nil
        case .stale: (font.days ?? 0) > 365
        case .noPhoto: !font.hasPhoto
        case .available: font.days.map { $0 <= 90 } == true && ["flowing", "trickle"].contains(font.lastStatus)
        }
    }
}

private extension MunicipalFont {
    var recentlyUnavailable: Bool {
        days.map { $0 <= 90 } == true && ["dry", "broken", "gone"].contains(lastStatus)
    }
    var needsReview: Bool { days == nil || (days ?? 0) > 365 }
    var priority: Int {
        (openReports > 0 ? 10_000 + openReports * 100 : 0)
        + (recentlyUnavailable ? 5_000 : 0)
        + (days.map { min($0, 1_500) } ?? 2_000)
        + (hasPhoto ? 0 : 100)
    }
}
