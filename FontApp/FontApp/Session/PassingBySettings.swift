import CoreLocation
import MapKit
import SwiftUI

/// The person's limits on the passing-by notices, shown under the switch in Settings:
/// pause, days, hours, how many a day and places without notices. Each one can only make
/// the app ask less. Changes are saved at once, as in the iOS settings.
struct PassingByLimitsRows: View {
    @Bindable private var passing = PassingBy.shared

    var body: some View {
        pauseRow
        NavigationLink {
            PassingByDaysPicker()
        } label: {
            LabeledContent(L10n.t("ios.passingBy.days"), value: PassingByDays.summary(passing.prefs.days))
        }
        .frame(minHeight: 44)
        NavigationLink {
            PassingByHoursPicker()
        } label: {
            LabeledContent(L10n.t("ios.passingBy.hours"),
                           value: PassingByDays.window(passing.prefs.from, passing.prefs.until))
        }
        .frame(minHeight: 44)
        Picker(L10n.t("ios.passingBy.perDay"), selection: $passing.prefs.perDay) {
            ForEach(1...PassingByRules.perDay, id: \.self) { Text("\($0)").tag($0) }
        }
        .frame(minHeight: 44)
        NavigationLink {
            QuietPlacesScreen()
        } label: {
            LabeledContent(L10n.t("ios.passingBy.places"),
                           value: passing.prefs.quietPlaces.isEmpty ? L10n.t("ios.passingBy.placesNone")
                               : "\(passing.prefs.quietPlaces.count)")
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder private var pauseRow: some View {
        if let until = passing.prefs.pausedUntil, passing.prefs.isPaused(at: .now) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("ios.passingBy.paused"))
                Text(until == .distantFuture ? L10n.t("ios.passingBy.pausedUntilResumed")
                     : L10n.t("ios.passingBy.pausedUntil", ["date": until.formatted(
                        .dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(PassingByDays.locale))]))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            Button(L10n.t("ios.passingBy.resume")) { passing.resume() }.frame(minHeight: 44)
        } else {
            Menu {
                ForEach(PassingByPause.allCases, id: \.self) { length in
                    Button(PassingByDays.pauseLabel(length)) { passing.pause(length) }
                }
            } label: {
                Label(L10n.t("ios.passingBy.pause"), systemImage: "pause.circle")
            }
            .frame(minHeight: 44)
        }
    }
}

/// Which weekdays may bring a notice: a list with checkmarks, as the Clock app's "Repeat".
private struct PassingByDaysPicker: View {
    @Bindable private var passing = PassingBy.shared

    var body: some View {
        List {
            Section {
                ForEach(PassingByDays.ordered, id: \.self) { day in
                    let on = passing.prefs.days.contains(day)
                    Button {
                        if on { passing.prefs.days.remove(day) } else { passing.prefs.days.insert(day) }
                    } label: {
                        HStack {
                            Text(PassingByDays.name(day)).foregroundStyle(.primary)
                            Spacer()
                            if on { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
                        }
                        .contentShape(Rectangle())
                    }
                    .frame(minHeight: 44)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            } footer: {
                Text(L10n.t("ios.passingBy.daysHint"))
            }
        }
        .navigationTitle(L10n.t("ios.passingBy.days"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// From and until, inside 7:00–22:00: never at night stays a rule, not a preference.
private struct PassingByHoursPicker: View {
    @Bindable private var passing = PassingBy.shared

    var body: some View {
        Form {
            Section {
                DatePicker(L10n.t("ios.passingBy.from"), selection: time(\.from),
                           in: bound(PassingByRules.dayStarts)...bound(passing.prefs.until - 15),
                           displayedComponents: .hourAndMinute)
                    .frame(minHeight: 44)
                DatePicker(L10n.t("ios.passingBy.until"), selection: time(\.until),
                           in: bound(passing.prefs.from + 15)...bound(PassingByRules.dayEnds),
                           displayedComponents: .hourAndMinute)
                    .frame(minHeight: 44)
            } footer: {
                Text(L10n.t("ios.passingBy.hoursHint"))
            }
            if passing.prefs.from != PassingByRules.dayStarts || passing.prefs.until != PassingByRules.dayEnds {
                Button(L10n.t("ios.passingBy.hoursReset")) {
                    passing.prefs.from = PassingByRules.dayStarts
                    passing.prefs.until = PassingByRules.dayEnds
                }
                .frame(minHeight: 44)
            }
        }
        .environment(\.locale, PassingByDays.locale)
        .navigationTitle(L10n.t("ios.passingBy.hours"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bound(_ minutes: Int) -> Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func time(_ key: WritableKeyPath<PassingByPrefs, Int>) -> Binding<Date> {
        Binding {
            bound(passing.prefs[keyPath: key])
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            passing.prefs[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// Places where passing a fountain is everyday life (home, work): no notices around them.
private struct QuietPlacesScreen: View {
    @Bindable private var passing = PassingBy.shared
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(passing.prefs.quietPlaces) { place in
                    Label(place.name, systemImage: "house").frame(minHeight: 44)
                }
                .onDelete { passing.prefs.quietPlaces.remove(atOffsets: $0) }
                if passing.prefs.quietPlaces.count < PassingByPrefs.maxQuietPlaces {
                    Button {
                        adding = true
                    } label: {
                        Label(L10n.t("ios.passingBy.placesAdd"), systemImage: "plus")
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                Text(L10n.t("ios.passingBy.placesHint"))
            }
        }
        .navigationTitle(L10n.t("ios.passingBy.places"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !passing.prefs.quietPlaces.isEmpty { EditButton() } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                QuietPlacePicker { place in
                    passing.prefs.quietPlaces.append(place)
                    adding = false
                } cancel: {
                    adding = false
                }
            }
        }
    }
}

/// Moves the map under a fixed circle, as Find My's "Notify me" does. Starts where the
/// phone last was, if location is already allowed; it never asks for it.
private struct QuietPlacePicker: View {
    let save: (QuietPlace) -> Void
    let cancel: () -> Void

    @State private var name = ""
    @State private var center: CLLocationCoordinate2D
    @State private var position: MapCameraPosition

    init(save: @escaping (QuietPlace) -> Void, cancel: @escaping () -> Void) {
        self.save = save
        self.cancel = cancel
        // Barcelona when there is no fix: most fountains are in Catalonia.
        let start = CLLocationManager().location?.coordinate ?? CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
        _center = State(initialValue: start)
        _position = State(initialValue: .region(MKCoordinateRegion(center: start, latitudinalMeters: 1500,
                                                                   longitudinalMeters: 1500)))
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                MapCircle(center: center, radius: QuietPlace.radius)
                    .foregroundStyle(.tint.opacity(0.2))
                    .stroke(.tint, lineWidth: 2)
                UserAnnotation()
            }
            .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
            .overlay {
                Image(systemName: "house.circle.fill")
                    .font(.title).foregroundStyle(.white, .tint)
                    .accessibilityHidden(true)
            }
            Form {
                TextField(L10n.t("ios.passingBy.placeName"), text: $name)
                    .frame(minHeight: 44)
            }
            .frame(maxHeight: 120)
        }
        .navigationTitle(L10n.t("ios.passingBy.placesAdd"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L10n.t("form.cancel"), action: cancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.t("form.save")) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    save(QuietPlace(name: trimmed.isEmpty ? L10n.t("ios.passingBy.placeDefault") : trimmed,
                                    latitude: center.latitude, longitude: center.longitude))
                }
            }
        }
    }
}

/// Weekday names, hours and summaries, in the app's language (not the phone's).
enum PassingByDays {
    static var locale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "ca") }

    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    /// The week as the person's region starts it (Monday in Europe), like Clock.
    static var ordered: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func name(_ day: Int) -> String {
        calendar.standaloneWeekdaySymbols[day - 1].capitalized(with: locale)
    }

    static func summary(_ days: Set<Int>) -> String {
        switch days {
        case PassingByRules.allDays: L10n.t("ios.passingBy.everyDay")
        case []: L10n.t("ios.passingBy.never")
        case [2, 3, 4, 5, 6]: L10n.t("ios.passingBy.weekdays")
        case [1, 7]: L10n.t("ios.passingBy.weekends")
        default: ordered.filter(days.contains)
            .map { calendar.shortStandaloneWeekdaySymbols[$0 - 1].capitalized(with: locale) }
            .formatted(.list(type: .and).locale(locale))
        }
    }

    /// "7:00–22:00", in the clock style of the app's language.
    static func window(_ from: Int, _ until: Int) -> String {
        let start = Calendar.current.startOfDay(for: .now)
        let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        return "\(start.addingTimeInterval(TimeInterval(from * 60)).formatted(style))–"
            + start.addingTimeInterval(TimeInterval(until * 60)).formatted(style)
    }

    static func pauseLabel(_ length: PassingByPause) -> String {
        switch length {
        case .day: L10n.t("ios.passingBy.pauseDay")
        case .week: L10n.t("ios.passingBy.pauseWeek")
        case .untilResumed: L10n.t("ios.passingBy.pauseUntilResumed")
        }
    }
}
