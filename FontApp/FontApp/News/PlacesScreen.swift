import SwiftUI

/// Public directory, grouped by region. Opening a region asks for all its places.
struct PlacesScreen: View {
    var region: String? = nil
    @State private var places: [PlaceSummary]?
    @State private var error: String?
    @State private var country = "*"
    @State private var search = ""

    private var countries: [String] {
        Array(Set((places ?? []).compactMap(\.country))).sorted()
    }

    private var visible: [PlaceSummary] {
        (places ?? []).filter { place in
            (country == "*" || place.country == country) &&
            (search.isEmpty || place.name.localizedStandardContains(search) ||
             (place.region?.localizedStandardContains(search) ?? false))
        }
    }

    private var regions: [String] {
        Array(Set(visible.compactMap(\.region))).sorted()
    }

    var body: some View {
        List {
            Section { Text(L10n.t("places.intro")).font(.subheadline).foregroundStyle(.secondary) }
            if region == nil {
                Section {
                    NavigationLink { MunicipalitySearchScreen() } label: {
                        Label(L10n.t("muni.inventory"), systemImage: "building.2.crop.circle")
                    }
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button(L10n.t("error.retry")) { Task { await load() } }
                }
            } else if places == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                if region == nil && countries.count > 1 {
                    Section {
                        Picker(L10n.t("activity.country"), selection: $country) {
                            Text(L10n.t("zones.allCountries")).tag("*")
                            ForEach(countries, id: \.self) { code in
                                Text(L10n.lookup("country.\(code)") ?? code).tag(code)
                            }
                        }
                    }
                }
                if visible.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    ForEach(regions, id: \.self) { name in
                        Section {
                            ForEach(visible.filter { $0.region == name }) { place in
                                NavigationLink {
                                    PlaceScreen(slug: place.slug)
                                } label: {
                                    HStack {
                                        Text(place.name)
                                        Spacer()
                                        Text(place.fontCount.formatted()).foregroundStyle(.secondary)
                                    }
                                    .frame(minHeight: 44)
                                }
                            }
                        } header: {
                            if region == nil {
                                NavigationLink(name) { PlacesScreen(region: name) }
                            } else { Text(name) }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: L10n.t("zones.search"))
        .navigationTitle(region ?? L10n.t("places.title"))
        .refreshable { await load() }
        .task(id: region) { await load() }
    }

    private func load() async {
        do {
            places = try await APIClient.shared.places(region: region, limit: region == nil ? 600 : 1000)
            error = nil
        } catch { self.error = ErrorText.describe(error) }
    }
}

struct PlaceScreen: View {
    let slug: String
    @Environment(\.showOnMap) private var showOnMap
    @State private var page: PlacePage?
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button(L10n.t("error.retry")) { Task { await load() } }
                }
            } else if let page {
                Section {
                    Text(L10n.t("place.intro", ["n": page.place.fontCount, "place": page.place.name]))
                    let checked = page.fonts.filter { $0.lastWaterStatus != nil }.count
                    Text(checked > 0
                         ? L10n.t("place.checked", ["n": checked, "total": page.fonts.count])
                         : L10n.t("place.noneChecked"))
                        .foregroundStyle(.secondary)
                }
                Section(L10n.t("place.list")) {
                    ForEach(page.fonts) { font in
                        NavigationLink {
                            FontDetailView(fontID: font.id)
                        } label: {
                            HStack {
                                Text(Confidence.level(of: font.evidence).emoji)
                                Text(L10n.fontName(font.name))
                            }
                            .frame(minHeight: 44)
                        }
                        .swipeActions {
                            if let showOnMap {
                                Button { showOnMap(font) } label: {
                                    Label(L10n.t("detail.viewOnMap"), systemImage: "map")
                                }
                            }
                        }
                    }
                }
                if !page.nearby.isEmpty {
                    Section(L10n.t("place.nearby")) {
                        ForEach(page.nearby) { place in
                            NavigationLink {
                                PlaceScreen(slug: place.slug)
                            } label: {
                                HStack {
                                    Text(place.name)
                                    Spacer()
                                    Text(place.fontCount.formatted()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else { ProgressView().frame(maxWidth: .infinity) }
        }
        .navigationTitle(page.map { data in
            data.place.region.map { L10n.t("place.titleWithRegion", ["place": data.place.name, "region": $0]) }
            ?? L10n.t("place.title", ["place": data.place.name])
        } ?? L10n.t("places.title"))
        .refreshable { await load() }
        .task(id: slug) { await load() }
    }

    private func load() async {
        do { page = try await APIClient.shared.place(slug); error = nil }
        catch { self.error = ErrorText.describe(error) }
    }
}
