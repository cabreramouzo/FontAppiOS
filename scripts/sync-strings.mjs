// Builds FontApp/FontApp/Localizable.xcstrings from the web app's dictionaries.
//
// The web wording has been refined over months; the app reuses it instead of keeping a
// copy that goes stale. Run again after changing the key list or when the web texts move:
//
//   node scripts/sync-strings.mjs [/path/to/FontAppBE]
//
// Keys keep the web names (`status.flowing`) and the web placeholders (`{n}`), which
// `L10n.t` fills in. Strings that exist only in the app live in IOS_ONLY below.

import { writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const backend = process.argv[2] ?? '/Users/mac/src/FontAppBE'
const { dictionaries } = await import(join(backend, 'web/src/i18n/dictionaries.ts'))

// Web language code → Apple localization. The web's Portuguese is European.
const LANGS = { ca: 'ca', es: 'es', gl: 'gl', eu: 'eu', en: 'en', fr: 'fr', pt: 'pt-PT', it: 'it' }

const PREFIXES = ['status.', 'confidence.', 'drink.', 'time.', 'error.', 'err.', 'incident.', 'activity.', 'news.',
  'login.', 'popup.', 'remote.', 'confirm.', 'toast.']
const KEYS = [
  'font.unnamed', 'nav.map', 'nav.profile', 'zones.title', 'review.anon',
  'report.resolved', 'report.resolvedBy',
  'source.tap', 'source.mountain', 'source.spring', 'source.well', 'source.fountain', 'source.other',
  'map.recenter', 'map.loading', 'map.rateLimited', 'map.rateLimitedBody', 'map.clusterCount',
  'detail.type', 'detail.drinkability', 'detail.unknownType', 'detail.unknownDrink',
  'detail.description', 'detail.lastUpdate', 'detail.currentStatus', 'detail.lastReportedStatus',
  'detail.confirmedByOne', 'detail.confirmedByMany', 'detail.statusReviews', 'detail.beFirst',
  'detail.incidents', 'detail.noIncidents', 'detail.loading', 'detail.directions',
  'detail.addPhoto', 'detail.firstPhotoNote', 'nav.logout', 'nav.enter', 'staff.tag', 'settings.account', 'photo.failed',
  'detail.noPhotoYet', 'detail.municipality', 'detail.region', 'detail.country', 'detail.stale',
]

const IOS_ONLY = {
  'ios.comingSoon': {
    ca: 'Aviat', es: 'Próximamente', gl: 'Proximamente', eu: 'Laster', en: 'Coming soon',
    fr: 'Bientôt', pt: 'Brevemente', it: 'Prossimamente',
  },
  'ios.comingSoonBody': {
    ca: 'Aquesta secció encara no és a l’app. De moment la trobaràs a fontapp.net.',
    es: 'Esta sección aún no está en la app. Mientras tanto la tienes en fontapp.net.',
    gl: 'Esta sección aínda non está na app. Mentres tanto tela en fontapp.net.',
    eu: 'Atal hau oraindik ez dago aplikazioan. Bitartean, fontapp.net-en duzu.',
    en: 'This section isn’t in the app yet. Meanwhile you’ll find it at fontapp.net.',
    fr: 'Cette section n’est pas encore dans l’app. En attendant, elle est sur fontapp.net.',
    pt: 'Esta secção ainda não está na app. Entretanto, encontra-a em fontapp.net.',
    it: 'Questa sezione non è ancora nell’app. Nel frattempo la trovi su fontapp.net.',
  },
  'ios.signInPrompt': {
    ca: 'Entra per explicar com raja una font i afegir-hi fotos.',
    es: 'Entra para contar cómo mana una fuente y añadirle fotos.',
    gl: 'Entra para contar como bota unha fonte e engadirlle fotos.',
    eu: 'Sartu iturri batek nola dakarren ura kontatzeko eta argazkiak gehitzeko.',
    en: 'Sign in to say how a fountain is flowing and add photos.',
    fr: 'Connecte-toi pour dire comment coule une fontaine et ajouter des photos.',
    pt: 'Entra para contar como está a correr uma fonte e juntar fotografias.',
    it: 'Accedi per raccontare come scorre una fontana e aggiungere foto.',
  },
  'ios.takePhoto': {
    ca: 'Fes una foto', es: 'Hacer una foto', gl: 'Facer unha foto', eu: 'Atera argazki bat',
    en: 'Take a photo', fr: 'Prendre une photo', pt: 'Tirar uma fotografia', it: 'Scatta una foto',
  },
  'ios.choosePhoto': {
    ca: 'Tria una foto', es: 'Elegir una foto', gl: 'Escoller unha foto', eu: 'Aukeratu argazki bat',
    en: 'Choose a photo', fr: 'Choisir une photo', pt: 'Escolher uma fotografia', it: 'Scegli una foto',
  },
  'ios.uploading': {
    ca: 'Pujant la foto…', es: 'Subiendo la foto…', gl: 'Subindo a foto…', eu: 'Argazkia igotzen…',
    en: 'Uploading the photo…', fr: 'Envoi de la photo…', pt: 'A enviar a fotografia…', it: 'Caricamento della foto…',
  },
  // Apple draws the base map and credits it; the fountains come from these sources.
  'ios.dataAttribution': {
    ca: 'Fonts: © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
    es: 'Fuentes: © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
    gl: 'Fontes: © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
    eu: 'Iturriak: © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
    en: 'Fountains: © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
    fr: 'Fontaines : © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
    pt: 'Fontes: © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
    it: 'Fontane: © OpenStreetMap (ODbL) · ICGC/ACA (CC BY 4.0)',
  },
}

const wanted = Object.keys(dictionaries.ca)
  .filter((k) => KEYS.includes(k) || PREFIXES.some((p) => k.startsWith(p)))
const missing = KEYS.filter((k) => !(k in dictionaries.ca))
if (missing.length) throw new Error(`Keys not in the web dictionaries: ${missing.join(', ')}`)

const unit = (value) => ({ stringUnit: { state: 'translated', value } })
const strings = {}
for (const key of wanted.sort()) {
  const localizations = {}
  for (const [web, apple] of Object.entries(LANGS)) {
    const value = dictionaries[web][key]
    if (value) localizations[apple] = unit(value)
  }
  strings[key] = { extractionState: 'manual', localizations }
}
for (const [key, texts] of Object.entries(IOS_ONLY)) {
  const localizations = {}
  for (const [web, apple] of Object.entries(LANGS)) localizations[apple] = unit(texts[web])
  strings[key] = { extractionState: 'manual', localizations }
}

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '../FontApp/FontApp/Localizable.xcstrings')
writeFileSync(out, JSON.stringify({ sourceLanguage: 'ca', strings, version: '1.0' }, null, 2) + '\n')
console.log(`${Object.keys(strings).length} keys → ${out}`)
