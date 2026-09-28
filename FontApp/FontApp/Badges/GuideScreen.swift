import SwiftUI

/// "How FontApp works", the web's `/guia` told for the iPhone. Long prose, so it lives
/// here and not in the dictionaries, as on the web: Catalan, Spanish and English.
/// Galician and Basque readers get Spanish, and French, Portuguese and Italian readers
/// English, rather than the web's Catalan fallback, which fewer of them read.
///
/// The drawings are schematic on purpose, not screenshots: a screenshot goes stale in
/// silence and would be per language. Pin colours and the three chips are stable domain,
/// drawn from `WaterStatus` itself.
struct GuideScreen: View {
    private struct Section_ { let title: String; let paragraphs: [String]; let drawing: Drawing? }
    private enum Drawing { case pins, chips }
    private struct Content { let title: String; let intro: String; let sections: [Section_]; let closing: String }

    private static let ca = Content(
        title: "Com funciona FontApp",
        intro: "FontApp diu si una font raja abans que t’hi desviïs. Ho fa la gent que hi passa: cadascú apunta si en surt aigua, si en surt poca o si està seca, i el següent ja ho sap. Aquí tens com fer-la servir en un minut.",
        sections: [
            .init(title: "1. Trobar aigua a prop teu", paragraphs: [
                "Obre el mapa i deixa que et situï. Cada xinxeta és una font, i el color diu com està l’aigua: verd si raja, groc si en surt poca, vermell si està seca i blau si encara no ho ha comprovat ningú. Toca’n una i veuràs l’últim que se’n va dir i quan.",
            ], drawing: .pins),
            .init(title: "2. Dir com està una font", paragraphs: [
                "És el més important i costa un toc. A la fitxa, digues si raja, si en surt poca o si està seca. El color canvia per a tothom i el següent excursionista ho sap abans de desviar-se. Si algú ja ho havia dit i segueix igual, compta com a confirmació.",
                "Mirar no demana res; per aportar, un compte de mig minut. I funciona sense cobertura: es guarda al mòbil i s’envia sol quan torna la xarxa.",
                "Quan hi ets, si a la font li falta alguna dada (si és potable, de quin tipus és, el nom), l’app te la preguntarà un cop. Només si ho saps.",
            ], drawing: .chips),
            .init(title: "3. Aigua a la teva ruta", paragraphs: [
                "Si planifiques rutes (Wikiloc, Strava, Komoot…), al mapa toca el botó GPX i tria el fitxer. FontApp et diu quines fonts hi ha pel camí, en quin quilòmetre i a quina distància del traçat. El fitxer no surt del teu mòbil.",
                "I el que decideix si portes un bidó o dos: el tram més llarg sense aigua. Això ho vols saber abans de sortir, no a mig camí.",
            ], drawing: nil),
            .init(title: "4. Emporta-te-la a la muntanya", paragraphs: [
                "Abans de sortir, guarda la zona des del botó de baixada del mapa: el mapa, les fonts i les fotos funcionen sense cobertura.",
                "Segueix les fonts que t’importen amb l’estrella i t’avisarem si s’assequen o tenen una incidència. Només això: la resta, a la campaneta.",
            ], drawing: nil),
        ],
        closing: "És gratuïta i col·laborativa: com més gent digui com està l’aigua, més serveix a tothom. Si te la fas teva, passa-la a qui fa rutes —és així com creix.")

    private static let es = Content(
        title: "Cómo funciona FontApp",
        intro: "FontApp te dice si una fuente mana antes de que te desvíes. Lo hace la gente que pasa: cada uno apunta si sale agua, si sale poca o si está seca, y el siguiente ya lo sabe. Aquí tienes cómo usarla en un minuto.",
        sections: [
            .init(title: "1. Encontrar agua cerca de ti", paragraphs: [
                "Abre el mapa y deja que te sitúe. Cada chincheta es una fuente, y el color dice cómo está el agua: verde si mana, amarillo si sale poca, rojo si está seca y azul si aún no lo ha comprobado nadie. Toca una y verás lo último que se dijo y cuándo.",
            ], drawing: .pins),
            .init(title: "2. Decir cómo está una fuente", paragraphs: [
                "Es lo más importante y cuesta un toque. En la ficha, di si mana, si sale poca o si está seca. El color cambia para todo el mundo y el siguiente excursionista lo sabe antes de desviarse. Si alguien ya lo había dicho y sigue igual, cuenta como confirmación.",
                "Mirar no pide nada; para aportar, una cuenta de medio minuto. Y funciona sin cobertura: se guarda en el móvil y se envía solo cuando vuelve la red.",
                "Cuando estás allí, si a la fuente le falta algún dato (si es potable, de qué tipo es, el nombre), la app te lo preguntará una vez. Solo si lo sabes.",
            ], drawing: .chips),
            .init(title: "3. Agua en tu ruta", paragraphs: [
                "Si planificas rutas (Wikiloc, Strava, Komoot…), en el mapa toca el botón GPX y elige el archivo. FontApp te dice qué fuentes hay por el camino, en qué kilómetro y a qué distancia del trazado. El archivo no sale de tu móvil.",
                "Y lo que decide si llevas un bidón o dos: el tramo más largo sin agua. Eso lo quieres saber antes de salir, no a medio camino.",
            ], drawing: nil),
            .init(title: "4. Llévatela al monte", paragraphs: [
                "Antes de salir, guarda la zona desde el botón de descarga del mapa: el mapa, las fuentes y las fotos funcionan sin cobertura.",
                "Sigue las fuentes que te importan con la estrella y te avisaremos si se secan o tienen una incidencia. Solo eso: lo demás, en la campana.",
            ], drawing: nil),
        ],
        closing: "Es gratuita y colaborativa: cuanta más gente diga cómo está el agua, más sirve a todo el mundo. Si te la haces tuya, pásasela a quien hace rutas —es así como crece.")

    private static let en = Content(
        title: "How FontApp works",
        intro: "FontApp tells you whether a fountain is running before you go out of your way. The people who pass do it: each one notes whether water is flowing, trickling or dry, so the next person already knows. Here’s how to use it in a minute.",
        sections: [
            .init(title: "1. Find water near you", paragraphs: [
                "Open the map and let it locate you. Each pin is a fountain, and the colour tells you how the water is: green if it’s flowing, amber if it’s trickling, red if it’s dry, and blue if nobody has checked it yet. Tap one to see the last report and when.",
            ], drawing: .pins),
            .init(title: "2. Say how a fountain is", paragraphs: [
                "It’s the most important thing and it takes one tap. On the fountain’s page, say whether it’s flowing, trickling or dry. The colour changes for everyone, and the next hiker knows before going out of their way. If someone already said so and it’s still the same, it counts as a confirmation.",
                "Looking needs nothing; to contribute, an account that takes half a minute. And it works without signal: it is kept on the phone and sent by itself when the network is back.",
                "When you are there, if the fountain lacks something (whether it’s drinkable, its kind, its name), the app will ask you once. Only if you know.",
            ], drawing: .chips),
            .init(title: "3. Water on your route", paragraphs: [
                "If you plan routes (Wikiloc, Strava, Komoot…), tap the GPX button on the map and choose the file. FontApp tells you which fountains are along the way, at which kilometre and how far from the track. The file never leaves your phone.",
                "And what decides whether you carry one bottle or two: the longest stretch without water. You want to know that before setting off, not halfway.",
            ], drawing: nil),
            .init(title: "4. Take it to the mountains", paragraphs: [
                "Before setting off, save the area with the map’s download button: the map, the fountains and the photos work without signal.",
                "Follow the fountains that matter to you with the star and we’ll tell you if they go dry or have an incident. Only that: everything else goes to the bell.",
            ], drawing: nil),
        ],
        closing: "It’s free and collaborative: the more people say how the water is, the more useful it is to everyone. If it becomes yours, pass it on to people who do routes — that’s how it grows.")

    private var content: Content {
        switch Bundle.main.preferredLocalizations.first.map({ String($0.prefix(2)) }) {
        case "ca": Self.ca
        case "es", "gl", "eu": Self.es
        default: Self.en
        }
    }

    var body: some View {
        let c = content
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(c.intro).font(.title3).foregroundStyle(.secondary)
                ForEach(c.sections.indices, id: \.self) { i in
                    let s = c.sections[i]
                    VStack(alignment: .leading, spacing: 10) {
                        Text(s.title).font(.title3.bold())
                        if let drawing = s.drawing { self.drawing(drawing) }
                        ForEach(s.paragraphs, id: \.self) { Text($0) }
                    }
                }
                Text(c.closing).font(.callout).foregroundStyle(.secondary)
                NavigationLink {
                    GamificationGuideScreen()
                } label: {
                    Label(L10n.t("gamePage.title"), systemImage: "drop.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .navigationTitle(c.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func drawing(_ d: Drawing) -> some View {
        switch d {
        case .pins:
            // The map's own colours: the last reported state, and blue for never checked.
            let pins: [(Color, String)] = [WaterStatus.flowing, .trickle, .dry]
                .map { ($0.color, L10n.t($0.labelKey)) } + [(WaterStatus.noStatusColor, L10n.t("confidence.unverified"))]
            HStack(spacing: 14) {
                ForEach(pins.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 34))
                            .foregroundStyle(.white, pins[i].0)
                        Text(pins[i].1).font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
        case .chips:
            HStack(spacing: 8) {
                ForEach([WaterStatus.flowing, .trickle, .dry], id: \.self) { s in
                    VStack(spacing: 2) {
                        Text(s.emoji)
                        Text(L10n.t(s.labelKey)).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(s.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .accessibilityHidden(true)
        }
    }
}
