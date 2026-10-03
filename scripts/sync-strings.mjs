// Builds FontApp/FontApp/Localizable.xcstrings from the web app's dictionaries.
//
// The web wording has been refined over months; the app reuses it instead of keeping a
// copy that goes stale. Run again after changing the key list or when the web texts move:
//
//   node scripts/sync-strings.mjs [/path/to/FontAppBE]
//
// Keys keep the web names (`status.flowing`) and the web placeholders (`{n}`), which
// `L10n.t` fills in. Strings that exist only in the app live in IOS_ONLY below.

import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const backend = process.argv[2] ?? '/Users/mac/src/FontAppBE'
const { dictionaries } = await import(join(backend, 'web/src/i18n/dictionaries.ts'))

// Web language code → Apple localization. The web's Portuguese is European.
const LANGS = { ca: 'ca', es: 'es', gl: 'gl', eu: 'eu', en: 'en', fr: 'fr', pt: 'pt-PT', it: 'it' }

const PREFIXES = ['country.', 'layer.', 'legend.', 'status.', 'confidence.', 'drink.', 'time.', 'error.', 'err.', 'incident.', 'activity.', 'news.', 'places.', 'place.', 'muni.', 'support.', 'donate.', 'feedback.', 'welcome.',
  'login.', 'notif.', 'popup.', 'profile.', 'guard.', 'game.', 'privacy.', 'settings.', 'remote.', 'confirm.', 'toast.', 'offline.', 'zonaOff.', 'gpx.', 'gpxIn.', 'newFont.', 'draft.', 'mission.', 'flag.', 'update.', 'comment.', 'report.', 'gallery.', 'dup.', 'image.', 'maint.', 'hidden.', 'badges.', 'celebrate.', 'waterHelp.', 'drinkHelp.', 'sourceLimit.', 'carousel.', 'approach.', 'detail.badges.', 'exif.', 'user.', 'gamePage.', 'gameHelp.', 'passkey.', 'pulse.']
const KEYS = [
  'map.geoDenied', 'map.geoUnavailable',
  'detail.edit', 'detail.editInfoHint', 'detail.editInfoNote', 'detail.editingTitle', 'detail.replacePhoto',
  'form.save', 'form.saving', 'form.discard', 'form.discardTitle', 'form.discardBody', 'form.keepEditing',
  'relocate.title', 'relocate.useMyLocation', 'relocate.locating', 'relocate.undo', 'relocate.moved',
  'relocate.notYours', 'relocate.accuracy', 'relocate.poorAccuracy',
  'cap.blocked.restricted', 'cap.blocked.optedOut', 'cap.blocked.unavailable',
  'cap.blocked.recentlyVoided', 'cap.blocked.activeDays',
  'search.recent', 'search.clearHistory',
  'zones.allCountries', 'font.unnamed', 'nav.map', 'nav.profile', 'zones.title', 'review.anon',
  'report.resolved', 'report.resolvedBy',
  'source.tap', 'source.mountain', 'source.spring', 'source.well', 'source.fountain', 'source.other',
  'map.layers', 'map.filters', 'map.onlyWater', 'map.onlyReliable', 'map.hideNonPotable',
  'map.hideNonPotableTitle', 'map.filterType', 'map.allTypes', 'map.addFont', 'map.searchPlaceholder',
  'map.nearbyTitle', 'map.nearbyEmpty', 'zones.neverChecked',
  'profile.usernameRules', 'profile.usernameNotEmail', 'profile.nameEmpty',
  'map.recenter', 'map.loading', 'map.rateLimited', 'map.rateLimitedBody', 'map.clusterCount',
  'detail.type', 'detail.drinkability', 'detail.unknownType', 'detail.unknownDrink',
  'detail.description', 'detail.lastUpdate', 'detail.currentStatus', 'detail.lastReportedStatus',
  'detail.confirmedByOne', 'detail.confirmedByMany', 'detail.statusReviews', 'detail.beFirst',
  'detail.incidents', 'detail.noIncidents', 'detail.loading', 'detail.directions',
  'detail.addPhoto', 'detail.firstPhotoNote', 'nav.logout', 'logout.confirmTitle', 'nav.enter', 'staff.tag', 'settings.account', 'photo.failed',
  'profile.deleteAccount', 'profile.confirmDelete', 'profile.dangerZone', 'profile.dangerZoneHint',
  'maintenance.recovered', 'favorite.save', 'favorite.saved',
  'detail.noPhotoYet', 'detail.viewOnMap', 'detail.share', 'detail.shareText', 'detail.nearWaterTitle', 'detail.nearWaterGo', 'form.cancel', 'detail.createdBy', 'detail.pioneerBy', 'detail.mayorBy', 'detail.mayorReviews', 'detail.mayorHelp', 'detail.confirmDeleteFont', 'detail.delete', 'detail.newUpdate', 'detail.confirmDeleteIncident', 'review.confirmDelete', 'detail.useAsMainPhoto', 'detail.photoSetAsMain', 'form.undo', 'form.create', 'detail.municipality', 'footer.legal', 'nav.guide', 'detail.region', 'detail.country', 'detail.stale',
  'detail.changed', 'detail.viewPreviousReviews', 'detail.reportStatus',
]

const IOS_ONLY = {
  'ios.login.google': {
    ca: 'Continua amb Google', es: 'Continuar con Google', gl: 'Continuar con Google', eu: 'Jarraitu Googlerekin',
    en: 'Continue with Google', fr: 'Continuer avec Google', pt: 'Continuar com o Google', it: 'Continua con Google',
  },
  'ios.donate.qr': {
    ca: 'Mostra el codi QR', es: 'Mostrar el código QR', gl: 'Amosar o código QR', eu: 'Erakutsi QR kodea',
    en: 'Show QR code', fr: 'Afficher le code QR', pt: 'Mostrar o código QR', it: 'Mostra il codice QR',
  },
  'ios.newFont.saveDraft': {
    ca: "Desa l'esborrany",
    es: "Guardar borrador",
    gl: "Gardar borrador",
    eu: "Gorde zirriborroa",
    en: "Save Draft",
    fr: "Enregistrer le brouillon",
    pt: "Guardar rascunho",
    it: "Salva bozza",
  },
  'ios.newFont.keepEditing': {
    ca: "Continua editant",
    es: "Seguir editando",
    gl: "Seguir editando",
    eu: "Jarraitu editatzen",
    en: "Keep Editing",
    fr: "Continuer la saisie",
    pt: "Continuar a editar",
    it: "Continua a modificare",
  },
  'ios.quick.notNow': {
    ca: "Ara no",
    es: "Ahora no",
    gl: "Agora non",
    eu: "Orain ez",
    en: "Not now",
    fr: "Pas maintenant",
    pt: "Agora não",
    it: "Non ora",
  },
  'ios.mapHelp.title': {
    ca: 'Ajuda del mapa', es: 'Ayuda del mapa', gl: 'Axuda do mapa', eu: 'Maparen laguntza',
    en: 'Map help', fr: 'Aide de la carte', pt: 'Ajuda do mapa', it: 'Aiuto mappa',
  },
  'ios.mapHelp.layers': {
    ca: 'Canvia el mapa de fons i consulta les capes disponibles.',
    es: 'Cambia el mapa de fondo y consulta las capas disponibles.',
    gl: 'Cambia o mapa de fondo e consulta as capas dispoñibles.',
    eu: 'Aldatu atzeko mapa eta ikusi eskuragarri dauden geruzak.',
    en: 'Change the base map and browse the available layers.',
    fr: 'Changez le fond de carte et consultez les calques disponibles.',
    pt: 'Muda o mapa de fundo e consulta as camadas disponíveis.',
    it: 'Cambia la mappa di base e consulta i livelli disponibili.',
  },
  'ios.mapHelp.filters': {
    ca: 'Mostra només les fonts que t’interessen i consulta què vol dir cada color.',
    es: 'Muestra solo las fuentes que te interesan y consulta qué significa cada color.',
    gl: 'Mostra só as fontes que che interesan e consulta o que significa cada cor.',
    eu: 'Erakutsi interesatzen zaizkizun iturriak eta ikusi kolore bakoitzaren esanahia.',
    en: 'Show only the fountains you want and see what each colour means.',
    fr: 'Affichez les fontaines qui vous intéressent et découvrez la signification des couleurs.',
    pt: 'Mostra só as fontes que te interessam e vê o significado de cada cor.',
    it: 'Mostra solo le fontane che ti interessano e scopri il significato dei colori.',
  },
  'ios.mapHelp.legend': {
    ca: "Què vol dir el color de cada font. Toca per amagar o mostrar la llegenda.", es: "Qué significa el color de cada fuente. Toca para ocultar o mostrar la leyenda.", gl: "Que significa a cor de cada fonte. Toca para ocultar ou amosar a lenda.", eu: "Iturri bakoitzaren koloreak zer esan nahi duen. Ukitu legenda ezkutatzeko edo erakusteko.", en: "What each fountain’s colour means. Tap to hide or show the legend.", fr: "Ce que signifie la couleur de chaque fontaine. Touchez pour masquer ou afficher la légende.", pt: "O que significa a cor de cada fonte. Toque para ocultar ou mostrar a legenda.", it: "Cosa significa il colore di ogni fontana. Tocca per nascondere o mostrare la legenda.",
  },
  'ios.mapHelp.missions': {
    ca: 'Descobreix passejades amb fonts per revisar pel camí.',
    es: 'Descubre paseos con fuentes para revisar por el camino.',
    gl: 'Descubre paseos con fontes para revisar polo camiño.',
    eu: 'Aurkitu bidean egiaztatzeko iturriak dituzten ibilaldiak.',
    en: 'Discover walks with fountains to check along the way.',
    fr: 'Découvrez des promenades avec des fontaines à vérifier en chemin.',
    pt: 'Descobre passeios com fontes para verificar pelo caminho.',
    it: 'Scopri passeggiate con fontane da controllare lungo il percorso.',
  },
  'ios.mapHelp.offline': {
    ca: 'Desa mapes i dades de fonts per consultar-los sense cobertura.',
    es: 'Guarda mapas y datos de fuentes para consultarlos sin cobertura.',
    gl: 'Garda mapas e datos de fontes para consultalos sen cobertura.',
    eu: 'Gorde mapak eta iturrien datuak estaldurarik gabe ikusteko.',
    en: 'Save maps and fountain details to use without a connection.',
    fr: 'Enregistrez les cartes et les données des fontaines pour les consulter hors ligne.',
    pt: 'Guarda mapas e dados das fontes para consultar sem rede.',
    it: 'Salva mappe e dati delle fontane per consultarli senza connessione.',
  },
  'ios.mapHelp.gpx': {
    ca: 'Importa una ruta GPX o exporta les fonts que veus al mapa.',
    es: 'Importa una ruta GPX o exporta las fuentes que ves en el mapa.',
    gl: 'Importa unha ruta GPX ou exporta as fontes que ves no mapa.',
    eu: 'Inportatu GPX ibilbide bat edo esportatu mapan ikusten dituzun iturriak.',
    en: 'Import a GPX route or export the fountains in the map view.',
    fr: 'Importez un itinéraire GPX ou exportez les fontaines visibles sur la carte.',
    pt: 'Importa um percurso GPX ou exporta as fontes visíveis no mapa.',
    it: 'Importa un percorso GPX o esporta le fontane visibili sulla mappa.',
  },
  'ios.mapHelp.location': {
    ca: 'Centra el mapa en tu. Torna a tocar-lo per canviar el seguiment.',
    es: 'Centra el mapa en ti. Tócalo de nuevo para cambiar el seguimiento.',
    gl: 'Centra o mapa en ti. Tócao de novo para cambiar o seguimento.',
    eu: 'Zentratu mapa zure kokapenean. Ukitu berriro jarraipena aldatzeko.',
    en: 'Centre the map on you. Tap again to change tracking mode.',
    fr: 'Centrez la carte sur vous. Touchez à nouveau pour changer le suivi.',
    pt: 'Centra o mapa em ti. Toca novamente para mudar o seguimento.',
    it: 'Centra la mappa su di te. Tocca di nuovo per cambiare la modalità di tracciamento.',
  },
  'ios.mapHelp.add': {
    ca: 'Afegeix una font que falta al mapa. Si no has iniciat sessió, t’ho demanarem abans.',
    es: 'Añade una fuente que falta en el mapa. Si no has iniciado sesión, te lo pediremos antes.',
    gl: 'Engade unha fonte que falta no mapa. Se non iniciaches sesión, pedirémoscho antes.',
    eu: 'Gehitu mapan falta den iturri bat. Saioa hasi ez baduzu, lehenik hori eskatuko dizugu.',
    en: 'Add a fountain missing from the map. We will ask you to sign in first if needed.',
    fr: 'Ajoutez une fontaine manquante sur la carte. Nous vous demanderons de vous connecter si nécessaire.',
    pt: 'Adiciona uma fonte que falta no mapa. Se necessário, pedimos primeiro que inicies sessão.',
    it: 'Aggiungi una fontana che manca sulla mappa. Se necessario, ti chiederemo prima di accedere.',
  },
  'ios.permission.continue': {
    ca: 'Continua', es: 'Continuar', gl: 'Continuar', eu: 'Jarraitu',
    en: 'Continue', fr: 'Continuer', pt: 'Continuar', it: 'Continua',
  },
  'ios.permission.notNow': {
    ca: 'Ara no', es: 'Ahora no', gl: 'Agora non', eu: 'Orain ez',
    en: 'Not now', fr: 'Pas maintenant', pt: 'Agora não', it: 'Non ora',
  },
  'ios.permission.locationTitle': {
    ca: 'Troba fonts a prop teu', es: 'Encuentra fuentes cerca de ti', gl: 'Atopa fontes preto de ti',
    eu: 'Aurkitu inguruko iturriak', en: 'Find fountains near you',
    fr: 'Trouvez des fontaines près de vous', pt: 'Encontra fontes perto de ti', it: 'Trova fontane vicino a te',
  },
  'ios.permission.locationBody': {
    ca: 'Amb la ubicació mentre fas servir l’app, el mapa et pot centrar i mostrar distàncies i fonts properes. Pots continuar sense donar-hi accés.',
    es: 'Con la ubicación mientras usas la app, el mapa puede centrarte y mostrar distancias y fuentes cercanas. Puedes continuar sin dar acceso.',
    gl: 'Coa localización mentres usas a app, o mapa pode centrarte e mostrar distancias e fontes próximas. Podes continuar sen dar acceso.',
    eu: 'Aplikazioa erabiltzean kokapena emanez gero, mapak inguruko iturriak eta distantziak erakutsiko dizkizu. Baimenik gabe ere jarrai dezakezu.',
    en: 'While you use the app, location can centre the map and show distances and nearby fountains. You can continue without it.',
    fr: 'Pendant l’utilisation, la position permet de centrer la carte et d’afficher les distances et les fontaines proches. Vous pouvez continuer sans elle.',
    pt: 'Ao usar a app, a localização permite centrar o mapa e mostrar distâncias e fontes próximas. Podes continuar sem ela.',
    it: 'Mentre usi l’app, la posizione centra la mappa e mostra distanze e fontane vicine. Puoi continuare senza concederla.',
  },
  'ios.permission.notificationsTitle': {
    ca: 'Avisos que importen', es: 'Avisos que importan', gl: 'Avisos que importan',
    eu: 'Garrantzitsuak diren abisuak', en: 'Notices that matter', fr: 'Des alertes utiles',
    pt: 'Avisos importantes', it: 'Avvisi importanti',
  },
  'ios.permission.notificationsBody': {
    ca: 'T’avisarem si una font que segueixes es queda seca, té una incidència o algú et respon. La resta queda a la campana de l’app.',
    es: 'Te avisaremos si una fuente que sigues se queda seca, tiene una incidencia o alguien te responde. El resto queda en la campana de la app.',
    gl: 'Avisarémoste se unha fonte que segues queda seca, ten unha incidencia ou alguén che responde. O resto queda na campá da app.',
    eu: 'Jarraitzen duzun iturri bat lehortzen bada, arazo bat badu edo norbaitek erantzuten badizu, abisatuko dizugu. Besteak aplikazioko kanpaian geratzen dira.',
    en: 'Get an alert if a fountain you follow runs dry, has a problem, or someone replies to you. Other updates stay in the in-app bell.',
    fr: 'Recevez une alerte si une fontaine suivie est à sec, a un problème ou si quelqu’un vous répond. Le reste reste dans la cloche de l’app.',
    pt: 'Recebe um aviso se uma fonte que segues ficar seca, tiver um problema ou alguém te responder. O resto fica na campainha da app.',
    it: 'Ricevi un avviso se una fontana che segui si prosciuga, ha un problema o qualcuno ti risponde. Il resto rimane nella campanella dell’app.',
  },
  'ios.permission.passingTitle': {
    ca: 'Quan passis per una font', es: 'Cuando pases por una fuente', gl: 'Cando pases por unha fonte',
    eu: 'Iturri baten ondotik pasatzean', en: 'When you pass a fountain', fr: 'Quand vous passez près d’une fontaine',
    pt: 'Quando passares por uma fonte', it: 'Quando passi vicino a una fontana',
  },
  'ios.permission.passingBody': {
    ca: 'Si actives aquesta funció, l’iPhone pot detectar fonts properes amb la ubicació «Sempre» i enviar-te un avís local per confirmar si ragen. Pots deixar-la desactivada.',
    es: 'Si activas esta función, el iPhone puede detectar fuentes cercanas con la ubicación «Siempre» y enviarte un aviso local para confirmar si manan. Puedes dejarla desactivada.',
    gl: 'Se activas esta función, o iPhone pode detectar fontes próximas coa localización «Sempre» e enviarche un aviso local para confirmar se botan auga. Podes deixala desactivada.',
    eu: 'Funtzio hau aktibatuz gero, iPhoneak inguruko iturriak antzeman ditzake «Beti» kokapenarekin, eta tokiko abisu bat bidali ura darien galdetzeko. Desaktibatuta utz dezakezu.',
    en: 'If you turn this on, your iPhone can detect nearby fountains using Always location and send a local notice to ask if water is flowing. You can leave it off.',
    fr: 'Si vous activez cette fonction, l’iPhone peut détecter les fontaines proches avec la position « Toujours » et demander par alerte locale si l’eau coule. Vous pouvez la laisser désactivée.',
    pt: 'Se ativares esta função, o iPhone pode detetar fontes próximas com localização «Sempre» e enviar um aviso local para confirmar se corre água. Podes deixá-la desligada.',
    it: 'Se attivi questa funzione, l’iPhone può rilevare le fontane vicine con la posizione «Sempre» e chiederti con un avviso locale se scorre acqua. Puoi lasciarla disattivata.',
  },
  'ios.permission.cameraTitle': {
    ca: 'Fotografia una font', es: 'Fotografía una fuente', gl: 'Fotografía unha fonte',
    eu: 'Atera argazkia iturriari', en: 'Photograph a fountain', fr: 'Photographiez une fontaine',
    pt: 'Fotografa uma fonte', it: 'Fotografa una fontana',
  },
  'ios.permission.cameraBody': {
    ca: 'La càmera et permet afegir una foto nova a una font o a un avís. També pots triar una foto existent sense donar accés a tota la fototeca.',
    es: 'La cámara te permite añadir una foto nueva a una fuente o un aviso. También puedes elegir una foto existente sin dar acceso a toda la fototeca.',
    gl: 'A cámara permíteche engadir unha foto nova a unha fonte ou aviso. Tamén podes escoller unha foto existente sen dar acceso a toda a fototeca.',
    eu: 'Kamerarekin argazki berria gehi diezaiokezu iturri edo abisu bati. Lehendik dagoen argazki bat ere aukera dezakezu fototeka osoaren baimenik gabe.',
    en: 'Use the camera to add a new photo to a fountain or report. You can also choose an existing photo without giving access to your whole library.',
    fr: 'L’appareil photo permet d’ajouter une nouvelle image à une fontaine ou un signalement. Vous pouvez aussi choisir une photo existante sans ouvrir toute la photothèque.',
    pt: 'A câmara permite juntar uma foto nova a uma fonte ou aviso. Também podes escolher uma foto existente sem dar acesso à biblioteca toda.',
    it: 'La fotocamera permette di aggiungere una nuova foto a una fontana o segnalazione. Puoi anche scegliere una foto esistente senza aprire tutta la libreria.',
  },
  'ios.permission.photosTitle': {
    ca: 'Desa una foto teva', es: 'Guarda una foto tuya', gl: 'Garda unha foto túa',
    eu: 'Gorde zure argazkia', en: 'Save your photo', fr: 'Enregistrez votre photo',
    pt: 'Guarda uma foto tua', it: 'Salva una tua foto',
  },
  'ios.permission.photosBody': {
    ca: 'Si tens una aportació pendent, pots desar-ne la foto a Fotos. Només demanem permís per afegir-la; no llegim la teva fototeca.',
    es: 'Si tienes una aportación pendiente, puedes guardar su foto en Fotos. Solo pedimos permiso para añadirla; no leemos tu fototeca.',
    gl: 'Se tes unha achega pendente, podes gardar a súa foto en Fotos. Só pedimos permiso para engadila; non lemos a túa fototeca.',
    eu: 'Bidaltzeko ekarpen bat baduzu, haren argazkia Argazkiak aplikazioan gorde dezakezu. Gehitzeko baimena baino ez dugu eskatzen; ez dugu zure fototeka irakurtzen.',
    en: 'If you have a contribution waiting to send, you can save its photo to Photos. We only ask to add it; we cannot read your library.',
    fr: 'Si une contribution attend l’envoi, vous pouvez enregistrer sa photo dans Photos. Nous demandons seulement l’ajout ; nous ne lisons pas votre photothèque.',
    pt: 'Se tiveres uma contribuição por enviar, podes guardar a foto em Fotografias. Só pedimos permissão para a adicionar; não lemos a tua biblioteca.',
    it: 'Se hai un contributo in attesa di invio, puoi salvare la foto in Foto. Chiediamo solo di aggiungerla; non leggiamo la tua libreria.',
  },
  'ios.welcome.waterTitle': {
    ca: 'Consulta si raja abans d’anar-hi', es: 'Consulta si mana antes de ir',
    gl: 'Consulta se bota auga antes de ir', eu: 'Begiratu ura dabilen joan aurretik',
    en: 'Know before you go', fr: 'Vérifiez si l’eau coule avant de partir',
    pt: 'Veja se corre água antes de ir', it: 'Controlla se c’è acqua prima di andare',
  },
  'ios.welcome.reportTitle': {
    ca: 'Actualitza l’estat en un toc', es: 'Actualiza el estado en un toque',
    gl: 'Actualiza o estado cun toque', eu: 'Eguneratu egoera ukitu batekin',
    en: 'Update the status in one tap', fr: 'Actualisez l’état en un geste',
    pt: 'Atualiza o estado com um toque', it: 'Aggiorna lo stato con un tocco',
  },
  'ios.welcome.routeTitle': {
    ca: 'Troba aigua a la teva ruta', es: 'Encuentra agua en tu ruta',
    gl: 'Atopa auga na túa ruta', eu: 'Aurkitu ura zure ibilbidean',
    en: 'Find water along your route', fr: 'Trouvez de l’eau sur votre itinéraire',
    pt: 'Encontra água no teu percurso', it: 'Trova acqua lungo il percorso',
  },
  'ios.welcome.routeBody': {
    ca: 'Importa una ruta GPX i mira les fonts del camí i els darrers avisos abans de sortir.',
    es: 'Importa una ruta GPX y mira las fuentes del camino y los últimos avisos antes de salir.',
    gl: 'Importa unha ruta GPX e mira as fontes do camiño e os últimos avisos antes de saír.',
    eu: 'Inportatu GPX ibilbide bat eta ikusi bideko iturriak eta azken oharrak abiatu aurretik.',
    en: 'Import a GPX route to see fountains along the way and recent reports before you leave.',
    fr: 'Importez un itinéraire GPX pour voir les fontaines du trajet et les derniers signalements avant de partir.',
    pt: 'Importa um percurso GPX para veres as fontes pelo caminho e os avisos recentes antes de saíres.',
    it: 'Importa un percorso GPX per vedere le fontane lungo la strada e le ultime segnalazioni prima di partire.',
  },
  'ios.welcome.openTitle': {
    ca: 'Dades de tothom, per sempre', es: 'Datos de todos, para siempre', gl: 'Datos de todos, para sempre',
    eu: 'Denon datuak, betiko', en: 'Everyone’s data, for good', fr: 'Des données à tous, pour toujours',
    pt: 'Dados de todos, para sempre', it: 'Dati di tutti, per sempre',
  },
  'ios.welcome.openBody': {
    ca: "A diferència d'altres apps d'aigua, les dades no són nostres: el mapa i les fotos es comparteixen amb llicència lliure de compartir igual i mai no en bloquejarem l'accés.",
    es: 'A diferencia de otras apps de agua, los datos no son nuestros: el mapa y las fotos se comparten con licencia libre de compartir igual y nunca bloquearemos su acceso.',
    gl: 'A diferenza doutras apps de auga, os datos non son nosos: o mapa e as fotos compártense con licenza libre de compartir igual e nunca bloquearemos o seu acceso.',
    eu: 'Beste ur-aplikazio batzuek ez bezala, datuak ez dira gureak: mapa eta argazkiak berdin partekatzeko lizentzia librearekin partekatzen dira, eta ez dugu inoiz haietarako sarbidea blokeatuko.',
    en: 'Unlike other water apps, we don’t own the data: the map and the photos are shared under an open share-alike licence, and we will never lock away access to them.',
    fr: "Contrairement à d'autres apps d'eau, les données ne nous appartiennent pas : la carte et les photos sont partagées sous licence libre de partage à l'identique, et nous n'en bloquerons jamais l'accès.",
    pt: 'Ao contrário de outras apps de água, os dados não são nossos: o mapa e as fotografias são partilhados com uma licença livre de partilha nos mesmos termos e nunca bloquearemos o acesso a eles.',
    it: "A differenza di altre app sull'acqua, i dati non sono nostri: la mappa e le foto sono condivise con licenza libera di condivisione allo stesso modo e non ne bloccheremo mai l'accesso.",
  },
  // Under the chips when the latest report is yours and fresh: that chip is already
  // said; the others (it changed) are still there.
  'ios.quick.youSaid': {
    ca: 'Ho vas dir {when}. Si ha canviat, toca el nou estat.',
    es: 'Lo dijiste {when}. Si ha cambiado, toca el nuevo estado.',
    gl: 'Dixéchelo {when}. Se cambiou, toca o novo estado.',
    eu: '{when} esan zenuen. Aldatu bada, sakatu egoera berria.',
    en: 'You said so {when}. If it has changed, tap the new state.',
    fr: 'Vous l’avez dit {when}. Si ça a changé, touchez le nouvel état.',
    pt: 'Disseste-o {when}. Se mudou, toca no novo estado.',
    it: 'L’hai detto {when}. Se è cambiato, tocca il nuovo stato.',
  },
  // The web's `report.add` ("report an issue") read as if only breakdowns belonged
  // there; the section is for notes too, as its title says.
  'ios.report.add': {
    ca: 'Informa d’un avís o incidència',
    es: 'Reportar un aviso o incidencia',
    gl: 'Informar dun aviso ou incidencia',
    eu: 'Jakinarazi ohar edo gorabehera bat',
    en: 'Report a note or issue',
    fr: 'Signaler une remarque ou un problème',
    pt: 'Reportar um aviso ou incidente',
    it: 'Segnala un avviso o un problema',
  },
  'ios.deleteAccount.pending': {
    ca: 'Abans s’enviarà el que tens pendent en aquest telèfon ({n}); el que no es pugui enviar es perdrà.',
    es: 'Antes se enviará lo que tienes pendiente en este teléfono ({n}); lo que no se pueda enviar se perderá.',
    gl: 'Antes enviarase o que tes pendente neste teléfono ({n}); o que non se poida enviar perderase.',
    eu: 'Lehenik, telefono honetan zain duzuna bidaliko da ({n}); bidali ezin dena galdu egingo da.',
    en: 'What is still waiting on this phone ({n}) is sent first; anything that can’t be sent is lost.',
    fr: 'Ce qui attend encore sur ce téléphone ({n}) est d’abord envoyé ; ce qui ne peut pas l’être est perdu.',
    pt: 'Primeiro é enviado o que tens pendente neste telemóvel ({n}); o que não for possível enviar perde-se.',
    it: 'Prima viene inviato ciò che hai in sospeso su questo telefono ({n}); ciò che non si può inviare va perso.',
  },
  'ios.bell.empty': {
    ca: 'Aquí veuràs quan algú et mencioni, confirmi la teva ressenya o passi alguna cosa a una font que segueixes.',
    es: 'Aquí verás cuándo alguien te menciona, confirma tu reseña o pasa algo en una fuente que sigues.',
    gl: 'Aquí verás cando alguén te menciona, confirma a túa reseña ou pasa algo nunha fonte que segues.',
    eu: 'Hemen ikusiko duzu norbaitek aipatzen zaituenean, zure iritzia berresten duenean edo jarraitzen duzun iturri batean zerbait gertatzen denean.',
    en: 'Here you’ll see when someone mentions you, confirms your review or something happens at a fountain you follow.',
    fr: 'Ici, vous verrez quand quelqu’un vous mentionne, confirme votre avis ou quand il se passe quelque chose à une fontaine que vous suivez.',
    pt: 'Aqui vais ver quando alguém te menciona, confirma a tua avaliação ou acontece algo numa fonte que segues.',
    it: 'Qui vedrai quando qualcuno ti menziona, conferma la tua recensione o succede qualcosa a una fontana che segui.',
  },
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
  'ios.layer.world': {
    ca: 'Mapa (OpenStreetMap)', es: 'Mapa (OpenStreetMap)', gl: 'Mapa (OpenStreetMap)', eu: 'Mapa (OpenStreetMap)',
    en: 'Map (OpenStreetMap)', fr: 'Carte (OpenStreetMap)', pt: 'Mapa (OpenStreetMap)', it: 'Mappa (OpenStreetMap)',
  },
  'ios.tab.favorites': {
    ca: 'Preferides', es: 'Favoritas', gl: 'Favoritas', eu: 'Gogokoak', en: 'Favourites',
    fr: 'Favoris', pt: 'Favoritas', it: 'Preferiti',
  },
  'ios.favorites.signedOut': {
    ca: 'Entra per desar fonts amb l’estrella i tenir-les aquí, també sense cobertura.',
    es: 'Entra para guardar fuentes con la estrella y tenerlas aquí, también sin cobertura.',
    gl: 'Entra para gardar fontes coa estrela e telas aquí, tamén sen cobertura.',
    eu: 'Sartu iturriak izarrarekin gordetzeko eta hemen izateko, estaldurarik gabe ere.',
    en: 'Sign in to star fountains and keep them here, even without signal.',
    fr: 'Connecte-toi pour garder des fontaines avec l’étoile et les avoir ici, même sans réseau.',
    pt: 'Entra para guardar fontes com a estrela e tê-las aqui, também sem rede.',
    it: 'Accedi per salvare fontane con la stella e averle qui, anche senza campo.',
  },
  'ios.favorites.pinned': {
    ca: 'Fixades', es: 'Fijadas', gl: 'Fixadas', eu: 'Finkatuak', en: 'Pinned', fr: 'Épinglées', pt: 'Fixadas', it: 'Fissate',
  },
  'ios.favorites.pin': {
    ca: 'Fixa-la', es: 'Fijar', gl: 'Fixar', eu: 'Finkatu', en: 'Pin', fr: 'Épingler', pt: 'Fixar', it: 'Fissa',
  },
  'ios.favorites.unpin': {
    ca: 'Deixa de fixar-la', es: 'Dejar de fijar', gl: 'Deixar de fixar', eu: 'Kendu finkapena', en: 'Unpin',
    fr: 'Désépingler', pt: 'Deixar de fixar', it: 'Non fissare più',
  },
  'ios.favorites.remove': {
    ca: 'Treu de preferides', es: 'Quitar de favoritas', gl: 'Quitar de favoritas', eu: 'Kendu gogokoetatik',
    en: 'Remove from favourites', fr: 'Retirer des favoris', pt: 'Tirar das favoritas', it: 'Togli dai preferiti',
  },
  'ios.favorites.removeN': {
    ca: 'Treu-ne {n}', es: 'Quitar {n}', gl: 'Quitar {n}', eu: 'Kendu {n}', en: 'Remove {n}', fr: 'Retirer {n}',
    pt: 'Tirar {n}', it: 'Togli {n}',
  },
  'ios.favorites.sort': {
    ca: 'Ordena', es: 'Ordenar', gl: 'Ordenar', eu: 'Ordenatu', en: 'Sort', fr: 'Trier', pt: 'Ordenar', it: 'Ordina',
  },
  'ios.favorites.sortMine': {
    ca: 'El meu ordre', es: 'Mi orden', gl: 'A miña orde', eu: 'Nire ordena', en: 'My order', fr: 'Mon ordre',
    pt: 'A minha ordem', it: 'Il mio ordine',
  },
  'ios.favorites.sortNearest': {
    ca: 'Més a prop', es: 'Más cerca', gl: 'Máis preto', eu: 'Hurbilenak', en: 'Nearest', fr: 'Les plus proches',
    pt: 'Mais perto', it: 'Più vicine',
  },
  'ios.favorites.sortName': {
    ca: 'Per nom', es: 'Por nombre', gl: 'Por nome', eu: 'Izenaren arabera', en: 'By name', fr: 'Par nom',
    pt: 'Por nome', it: 'Per nome',
  },
  'ios.favorites.filter': {
    ca: 'Filtra per nom o poble', es: 'Filtrar por nombre o pueblo', gl: 'Filtrar por nome ou vila',
    eu: 'Iragazi izenaren edo herriaren arabera', en: 'Filter by name or town', fr: 'Filtrer par nom ou commune',
    pt: 'Filtrar por nome ou localidade', it: 'Filtra per nome o paese',
  },
  'ios.favorites.manageHint': {
    ca: 'Llisca a la dreta per fixar-ne una a dalt i a l’esquerra per treure-la. Amb Edita, arrossega-les per ordenar-les.',
    es: 'Desliza a la derecha para fijar una arriba y a la izquierda para quitarla. Con Editar, arrástralas para ordenarlas.',
    gl: 'Esvara á dereita para fixar unha arriba e á esquerda para quitala. Con Editar, arrástraas para ordenalas.',
    eu: 'Irristatu eskuinera bat goian finkatzeko eta ezkerrera kentzeko. Editatu sakatuta, arrastatu ordenatzeko.',
    en: 'Swipe right to pin one to the top, left to remove it. With Edit, drag them into your order.',
    fr: 'Glisse vers la droite pour en épingler une en haut, vers la gauche pour la retirer. Avec Modifier, fais-les glisser pour les ordonner.',
    pt: 'Desliza para a direita para fixar uma no topo e para a esquerda para a tirar. Com Editar, arrasta-as para as ordenar.',
    it: 'Scorri a destra per fissarne una in alto, a sinistra per toglierla. Con Modifica, trascinale per ordinarle.',
  },
  'ios.favorites.howTo': {
    ca: 'Toca l’estrella a la fitxa d’una font per afegir-la aquí.',
    es: 'Toca la estrella en la ficha de una fuente para añadirla aquí.',
    gl: 'Toca a estrela na ficha dunha fonte para engadila aquí.',
    eu: 'Ukitu izarra iturri baten fitxan hona gehitzeko.',
    en: 'Tap the star on a fountain’s page to add it here.',
    fr: 'Touche l’étoile sur la fiche d’une fontaine pour l’ajouter ici.',
    pt: 'Toca na estrela na ficha de uma fonte para a juntar aqui.',
    it: 'Tocca la stella nella scheda di una fontana per aggiungerla qui.',
  },
  'ios.layer.outside': {
    ca: '{layer} no cobreix aquesta zona.', es: '{layer} no cubre esta zona.', gl: '{layer} non cobre esta zona.',
    eu: '{layer} geruzak ez du eremu hau hartzen.', en: '{layer} doesn’t cover this area.',
    fr: '{layer} ne couvre pas cette zone.', pt: '{layer} não cobre esta zona.', it: '{layer} non copre questa zona.',
  },
  'ios.layer.useWorld': {
    ca: 'Mapa mundial', es: 'Mapa mundial', gl: 'Mapa mundial', eu: 'Munduko mapa', en: 'World map',
    fr: 'Carte du monde', pt: 'Mapa-múndi', it: 'Mappa del mondo',
  },
  'ios.layer.ignBase': {
    ca: 'Mapa base IGN (ES)', es: 'Mapa base IGN (ES)', gl: 'Mapa base IGN (ES)', eu: 'IGN oinarrizko mapa (ES)',
    en: 'IGN base map (ES)', fr: 'Carte de base IGN (ES)', pt: 'Mapa base IGN (ES)', it: 'Mappa di base IGN (ES)',
  },
  'ios.filters.clear': {
    ca: 'Treu els filtres', es: 'Quitar filtros', gl: 'Quitar filtros', eu: 'Kendu iragazkiak',
    en: 'Clear filters', fr: 'Effacer les filtres', pt: 'Limpar filtros', it: 'Rimuovi filtri',
  },
  'ios.search.prompt': {
    ca: 'Cerca font o lloc', es: 'Buscar fuente o lugar', gl: 'Buscar fonte ou lugar', eu: 'Bilatu iturria edo lekua',
    en: 'Search fountain or place', fr: 'Chercher une fontaine ou un lieu', pt: 'Procurar fonte ou local',
    it: 'Cerca fontana o luogo',
  },
  'ios.search.title': {
    ca: 'Cerca', es: 'Buscar', gl: 'Buscar', eu: 'Bilatu', en: 'Search', fr: 'Rechercher', pt: 'Pesquisar', it: 'Cerca',
  },
  'ios.close': {
    ca: 'Tanca', es: 'Cerrar', gl: 'Pechar', eu: 'Itxi', en: 'Close', fr: 'Fermer', pt: 'Fechar', it: 'Chiudi',
  },
  'ios.fill.ask.drinkable': {
    ca: 'Saps si l’aigua és potable?', es: '¿Sabes si el agua es potable?', gl: 'Sabes se a auga é potable?', eu: 'Badakizu ura edangarria den?', en: 'Do you know if the water is drinkable?', fr: 'Savez-vous si l’eau est potable ?', pt: 'Sabe se a água é potável?', it: 'Sai se l’acqua è potabile?',
  },
  'ios.fill.ask.source': {
    ca: 'Quin tipus de font és?', es: '¿Qué tipo de fuente es?', gl: 'Que tipo de fonte é?', eu: 'Zer iturri mota da?', en: 'What kind of fountain is it?', fr: 'Quel type de fontaine est-ce ?', pt: 'Que tipo de fonte é?', it: 'Che tipo di fontana è?',
  },
  'ios.fill.ask.name': {
    ca: 'Té nom aquesta font?', es: '¿Tiene nombre esta fuente?', gl: 'Ten nome esta fonte?', eu: 'Iturri honek izenik al du?', en: 'Does this fountain have a name?', fr: 'Cette fontaine a-t-elle un nom ?', pt: 'Esta fonte tem nome?', it: 'Questa fontana ha un nome?',
  },
  'ios.fill.add.drinkable': {
    ca: 'Afegeix la potabilitat', es: 'Añadir potabilidad', gl: 'Engadir potabilidade', eu: 'Gehitu edangarritasuna', en: 'Add drinkability', fr: 'Ajouter la potabilité', pt: 'Adicionar potabilidade', it: 'Aggiungi potabilità',
  },
  'ios.fill.add.source': {
    ca: 'Afegeix el tipus', es: 'Añadir tipo', gl: 'Engadir tipo', eu: 'Gehitu mota', en: 'Add kind', fr: 'Ajouter le type', pt: 'Adicionar tipo', it: 'Aggiungi tipo',
  },
  'ios.fill.add.name': {
    ca: 'Afegeix el nom', es: 'Añadir nombre', gl: 'Engadir nome', eu: 'Gehitu izena', en: 'Add name', fr: 'Ajouter le nom', pt: 'Adicionar nome', it: 'Aggiungi nome',
  },
  'ios.fill.nameLabel': {
    ca: 'Nom', es: 'Nombre', gl: 'Nome', eu: 'Izena', en: 'Name', fr: 'Nom', pt: 'Nome', it: 'Nome',
  },
  'ios.fill.namePlaceholder': {
    ca: 'El nom de la font', es: 'El nombre de la fuente', gl: 'O nome da fonte', eu: 'Iturriaren izena', en: 'The fountain’s name', fr: 'Le nom de la fontaine', pt: 'O nome da fonte', it: 'Il nome della fontana',
  },
  'ios.fill.dontKnow': {
    ca: 'No ho sé', es: 'No lo sé', gl: 'Non o sei', eu: 'Ez dakit', en: 'I don’t know', fr: 'Je ne sais pas', pt: 'Não sei', it: 'Non lo so',
  },
  'ios.push.on': {
    ca: 'Avisos activats en aquest iPhone', es: 'Avisos activados en este iPhone', gl: 'Avisos activados neste iPhone', eu: 'Abisuak aktibatuta iPhone honetan', en: 'Notifications on for this iPhone', fr: 'Notifications activées sur cet iPhone', pt: 'Avisos ativados neste iPhone', it: 'Avvisi attivi su questo iPhone',
  },
  'ios.push.enable': {
    ca: 'Activa els avisos en aquest iPhone', es: 'Activar los avisos en este iPhone', gl: 'Activar os avisos neste iPhone', eu: 'Aktibatu abisuak iPhone honetan', en: 'Turn on notifications for this iPhone', fr: 'Activer les notifications sur cet iPhone', pt: 'Ativar os avisos neste iPhone', it: 'Attiva gli avvisi su questo iPhone',
  },
  'ios.push.denied': {
    ca: 'Les notificacions de FontApp estan desactivades. Es poden tornar a activar als Ajustos de l’iPhone.', es: 'Las notificaciones de FontApp están desactivadas. Se pueden volver a activar en los Ajustes del iPhone.', gl: 'As notificacións de FontApp están desactivadas. Pódense volver activar nos Axustes do iPhone.', eu: 'FontApp-en jakinarazpenak desaktibatuta daude. iPhonearen Ezarpenetan aktiba daitezke berriro.', en: 'FontApp notifications are off. They can be turned back on in the iPhone’s Settings.', fr: 'Les notifications de FontApp sont désactivées. Vous pouvez les réactiver dans les Réglages de l’iPhone.', pt: 'As notificações da FontApp estão desativadas. Pode voltar a ativá-las nas Definições do iPhone.', it: 'Le notifiche di FontApp sono disattivate. Puoi riattivarle nelle Impostazioni dell’iPhone.',
  },
  'ios.push.openSettings': {
    ca: 'Obre els Ajustos', es: 'Abrir Ajustes', gl: 'Abrir Axustes', eu: 'Ireki Ezarpenak', en: 'Open Settings', fr: 'Ouvrir Réglages', pt: 'Abrir Definições', it: 'Apri Impostazioni',
  },
  'ios.push.hint': {
    ca: 'Només el que pot canviar el que estàs a punt de fer: una font que segueixes s’ha assecat o té una incidència, o algú et parla. La resta, a la campaneta.', es: 'Solo lo que puede cambiar lo que vas a hacer: una fuente que sigues se ha secado o tiene una incidencia, o alguien te habla. Lo demás, en la campana.', gl: 'Só o que pode cambiar o que vas facer: unha fonte que segues secou ou ten unha incidencia, ou alguén che fala. O demais, na campá.', eu: 'Egitera zoazena alda dezakeena bakarrik: jarraitzen duzun iturri bat lehortu da edo gorabehera bat du, edo norbaitek hitz egiten dizu. Gainerakoa, kanpaian.', en: 'Only what can change what you are about to do: a fountain you follow went dry or has an incident, or someone is talking to you. Everything else goes to the bell.', fr: 'Seulement ce qui peut changer ce que vous allez faire : une fontaine que vous suivez est à sec ou a un incident, ou quelqu’un vous parle. Le reste, dans la cloche.', pt: 'Só o que pode mudar o que vai fazer: uma fonte que segue secou ou tem um incidente, ou alguém fala consigo. O resto, no sino.', it: 'Solo ciò che può cambiare quello che stai per fare: una fontana che segui è asciutta o ha un problema, o qualcuno ti scrive. Il resto, nella campanella.',
  },
  // Sign in with Apple exists only in the app; the codes come from POST /auth/apple.
  'err.auth.appleInvalid': {
    ca: 'La identificació d’Apple no és vàlida.', es: 'La identificación de Apple no es válida.', gl: 'A identificación de Apple non é válida.', eu: 'Appleren identifikazioa ez da baliozkoa.', en: 'Apple’s sign-in could not be verified.', fr: 'L’identification Apple n’est pas valide.', pt: 'A identificação da Apple não é válida.', it: 'L’identificazione di Apple non è valida.',
  },
  'err.auth.appleLinkRequired': {
    ca: 'Aquest correu ja té un compte. Entra amb la contrasenya.', es: 'Este correo ya tiene cuenta. Entra con tu contraseña.', gl: 'Este correo xa ten conta. Entra co teu contrasinal.', eu: 'Posta honek badu kontu bat. Sartu zure pasahitzarekin.', en: 'This email already has an account. Sign in with your password.', fr: 'Cet e-mail a déjà un compte. Connectez-vous avec votre mot de passe.', pt: 'Este e-mail já tem conta. Entre com a sua palavra-passe.', it: 'Questa email ha già un account. Accedi con la password.',
  },
  'err.auth.appleNoEmail': {
    ca: 'Apple no ha compartit cap correu. Torna-ho a provar i deixa que en comparteixi un (pot ser l’ocult).', es: 'Apple no ha compartido ningún correo. Vuelve a probar y deja que comparta uno (puede ser el oculto).', gl: 'Apple non compartiu ningún correo. Téntao de novo e deixa que comparta un (pode ser o oculto).', eu: 'Applek ez du posta elektronikorik partekatu. Saiatu berriro eta utzi bat partekatzen (ezkutukoa izan daiteke).', en: 'Apple did not share an email. Try again and let it share one (the hidden one is fine).', fr: 'Apple n’a partagé aucun e-mail. Réessayez en le laissant en partager un (l’adresse masquée convient).', pt: 'A Apple não partilhou nenhum e-mail. Tente de novo e deixe partilhar um (pode ser o oculto).', it: 'Apple non ha condiviso alcuna email. Riprova e lascia che ne condivida una (va bene quella nascosta).',
  },
  'ios.passingBy.title': {
    ca: 'Avisa’m quan passi per una font', es: 'Avísame cuando pase por una fuente', gl: 'Avísame cando pase por unha fonte', eu: 'Abisatu iturri baten ondotik pasatzean', en: 'Tell me when I pass a fountain', fr: 'Me prévenir quand je passe près d’une fontaine', pt: 'Avisar-me quando passar por uma fonte', it: 'Avvisami quando passo vicino a una fontana',
  },
  'ios.passingBy.hint': {
    ca: 'Quan passis a prop d’una font de la qual se sap poc, et preguntarem si raja i podràs respondre des del mateix avís. Com a molt tres al dia, mai de nit ni dues vegades la mateixa font en un mes. Cal el permís d’ubicació «Sempre»; la teva ubicació no es desa enlloc.',
    es: 'Cuando pases cerca de una fuente de la que se sabe poco, te preguntaremos si mana y podrás responder desde el mismo aviso. Como mucho tres al día, nunca de noche ni dos veces la misma fuente en un mes. Necesita el permiso de ubicación «Siempre»; tu ubicación no se guarda en ningún sitio.',
    gl: 'Cando pases preto dunha fonte da que se sabe pouco, preguntarémosche se bota auga e poderás responder desde o mesmo aviso. Como moito tres ao día, nunca de noite nin dúas veces a mesma fonte nun mes. Precisa o permiso de localización «Sempre»; a túa localización non se garda en ningún sitio.',
    eu: 'Gutxi dakigun iturri baten ondotik pasatzean, ura ateratzen den galdetuko dizugu eta abisutik bertatik erantzun ahal izango duzu. Egunean hiru gehienez, inoiz ez gauez ezta iturri bera bi aldiz hilabetean ere. «Beti» kokapen-baimena behar du; zure kokapena ez da inon gordetzen.',
    en: 'When you pass near a fountain little is known about, we’ll ask whether it’s flowing and you can answer from the notice itself. At most three a day, never at night, and never the same fountain twice in a month. Needs the “Always” location permission; your location is not stored anywhere.',
    fr: 'Quand vous passez près d’une fontaine dont on sait peu de chose, nous vous demanderons si elle coule et vous pourrez répondre depuis la notification. Trois par jour au plus, jamais la nuit ni deux fois la même fontaine dans le mois. Nécessite l’autorisation de localisation « Toujours » ; votre position n’est enregistrée nulle part.',
    pt: 'Quando passar perto de uma fonte de que se sabe pouco, perguntamos se está a correr e pode responder no próprio aviso. No máximo três por dia, nunca à noite nem duas vezes a mesma fonte num mês. Precisa da permissão de localização «Sempre»; a sua localização não é guardada em lado nenhum.',
    it: 'Quando passi vicino a una fontana di cui si sa poco, ti chiederemo se scorre e potrai rispondere dalla notifica stessa. Al massimo tre al giorno, mai di notte né due volte la stessa fontana in un mese. Richiede il permesso di posizione «Sempre»; la tua posizione non viene salvata da nessuna parte.',
  },
  'ios.passingBy.needsAlways': {
    ca: 'Perquè funcioni, a Ajustes > FontApp > Ubicació tria «Sempre».', es: 'Para que funcione, en Ajustes > FontApp > Ubicación elige «Siempre».', gl: 'Para que funcione, en Axustes > FontApp > Localización escolle «Sempre».', eu: 'Funtziona dezan, Ezarpenak > FontApp > Kokapena atalean aukeratu «Beti».', en: 'For this to work, choose “Always” in Settings > FontApp > Location.', fr: 'Pour que cela fonctionne, choisissez « Toujours » dans Réglages > FontApp > Position.', pt: 'Para funcionar, em Definições > FontApp > Localização escolha «Sempre».', it: 'Perché funzioni, in Impostazioni > FontApp > Posizione scegli «Sempre».',
  },
  'ios.passingBy.days': {
    ca: 'Dies', es: 'Días', gl: 'Días', eu: 'Egunak', en: 'Days', fr: 'Jours', pt: 'Dias', it: 'Giorni',
  },
  'ios.passingBy.daysHint': {
    ca: 'Tria quins dies vols aquests avisos. Els altres dies no et preguntarem res, encara que passis a prop d’una font.',
    es: 'Elige qué días quieres estos avisos. Los demás días no te preguntaremos nada, aunque pases cerca de una fuente.',
    gl: 'Escolle que días queres estes avisos. Os demais días non che preguntaremos nada, aínda que pases preto dunha fonte.',
    eu: 'Aukeratu zein egunetan nahi dituzun abisu hauek. Beste egunetan ez dizugu ezer galdetuko, iturri baten ondotik pasatu arren.',
    en: 'Choose which days you want these notices. On the other days we won’t ask you anything, even if you pass a fountain.',
    fr: 'Choisissez les jours où vous voulez ces notifications. Les autres jours, nous ne vous demanderons rien, même si vous passez près d’une fontaine.',
    pt: 'Escolha em que dias quer estes avisos. Nos outros dias não lhe perguntamos nada, mesmo que passe perto de uma fonte.',
    it: 'Scegli in quali giorni vuoi questi avvisi. Negli altri giorni non ti chiederemo nulla, anche se passi vicino a una fontana.',
  },
  'ios.passingBy.everyDay': {
    ca: 'Cada dia', es: 'Todos los días', gl: 'Todos os días', eu: 'Egunero', en: 'Every day', fr: 'Tous les jours', pt: 'Todos os dias', it: 'Ogni giorno',
  },
  'ios.passingBy.weekdays': {
    ca: 'Entre setmana', es: 'Entre semana', gl: 'Entre semana', eu: 'Astegunetan', en: 'Weekdays', fr: 'En semaine', pt: 'Dias úteis', it: 'Giorni feriali',
  },
  'ios.passingBy.weekends': {
    ca: 'Caps de setmana', es: 'Fines de semana', gl: 'Fins de semana', eu: 'Asteburuetan', en: 'Weekends', fr: 'Le week-end', pt: 'Fins de semana', it: 'Fine settimana',
  },
  'ios.passingBy.never': {
    ca: 'Mai', es: 'Nunca', gl: 'Nunca', eu: 'Inoiz ez', en: 'Never', fr: 'Jamais', pt: 'Nunca', it: 'Mai',
  },
  'ios.passingBy.hours': {
    ca: "Horari", es: "Horario", gl: "Horario", eu: "Ordutegia", en: "Hours", fr: "Horaires", pt: "Horário", it: "Orario",
  },
  'ios.passingBy.from': {
    ca: "Des de", es: "Desde", gl: "Desde", eu: "Noiztik", en: "From", fr: "De", pt: "Das", it: "Dalle",
  },
  'ios.passingBy.until': {
    ca: "Fins a", es: "Hasta", gl: "Ata", eu: "Noiz arte", en: "Until", fr: "À", pt: "Até", it: "Alle",
  },
  'ios.passingBy.hoursHint': {
    ca: "Només et preguntarem dins d’aquestes hores. Mai abans de les 7:00 ni després de les 22:00.", es: "Solo te preguntaremos dentro de estas horas. Nunca antes de las 7:00 ni después de las 22:00.", gl: "Só che preguntaremos dentro destas horas. Nunca antes das 7:00 nin despois das 22:00.", eu: "Ordu hauen barruan bakarrik galdetuko dizugu. Inoiz ez 7:00ak baino lehen ezta 22:00ak ondoren ere.", en: "We’ll only ask within these hours. Never before 7:00 or after 22:00.", fr: "Nous ne vous demanderons rien en dehors de ces heures. Jamais avant 7 h ni après 22 h.", pt: "Só perguntamos dentro destas horas. Nunca antes das 7:00 nem depois das 22:00.", it: "Ti chiederemo solo in questa fascia oraria. Mai prima delle 7:00 né dopo le 22:00.",
  },
  'ios.passingBy.hoursReset': {
    ca: "Torna a 7:00–22:00", es: "Volver a 7:00–22:00", gl: "Volver a 7:00–22:00", eu: "Itzuli 7:00–22:00 ordutegira", en: "Back to 7:00–22:00", fr: "Revenir à 7:00–22:00", pt: "Voltar a 7:00–22:00", it: "Torna a 7:00–22:00",
  },
  'ios.passingBy.perDay': {
    ca: "Màxim al dia", es: "Máximo al día", gl: "Máximo ao día", eu: "Egunean gehienez", en: "Most per day", fr: "Maximum par jour", pt: "Máximo por dia", it: "Massimo al giorno",
  },
  'ios.passingBy.pause': {
    ca: "Pausa els avisos", es: "Pausar avisos", gl: "Pausar avisos", eu: "Pausatu abisuak", en: "Pause notices", fr: "Suspendre les notifications", pt: "Pausar avisos", it: "Sospendi gli avvisi",
  },
  'ios.passingBy.pauseDay': {
    ca: "Durant 1 dia", es: "Durante 1 día", gl: "Durante 1 día", eu: "Egun batez", en: "For 1 day", fr: "Pendant 1 jour", pt: "Durante 1 dia", it: "Per 1 giorno",
  },
  'ios.passingBy.pauseWeek': {
    ca: "Durant 1 setmana", es: "Durante 1 semana", gl: "Durante 1 semana", eu: "Aste batez", en: "For 1 week", fr: "Pendant 1 semaine", pt: "Durante 1 semana", it: "Per 1 settimana",
  },
  'ios.passingBy.pauseUntilResumed': {
    ca: "Fins que els reprengui", es: "Hasta que los reanude", gl: "Ata que os retome", eu: "Berriro aktibatu arte", en: "Until I resume them", fr: "Jusqu’à ce que je les réactive", pt: "Até os retomar", it: "Finché non li riattivo",
  },
  'ios.passingBy.paused': {
    ca: "Avisos en pausa", es: "Avisos en pausa", gl: "Avisos en pausa", eu: "Abisuak pausatuta", en: "Notices paused", fr: "Notifications suspendues", pt: "Avisos em pausa", it: "Avvisi in pausa",
  },
  'ios.passingBy.pausedUntil': {
    ca: "Fins {date}", es: "Hasta {date}", gl: "Ata {date}", eu: "Noiz arte: {date}", en: "Until {date}", fr: "Jusqu’au {date}", pt: "Até {date}", it: "Fino a {date}",
  },
  'ios.passingBy.pausedUntilResumed': {
    ca: "Fins que els reprenguis", es: "Hasta que los reanudes", gl: "Ata que os retomes", eu: "Berriro aktibatu arte", en: "Until you resume them", fr: "Jusqu’à ce que vous les réactiviez", pt: "Até os retomar", it: "Finché non li riattivi",
  },
  'ios.passingBy.resume': {
    ca: "Reprèn els avisos", es: "Reanudar avisos", gl: "Retomar avisos", eu: "Berriro aktibatu abisuak", en: "Resume notices", fr: "Réactiver les notifications", pt: "Retomar avisos", it: "Riattiva gli avvisi",
  },
  'ios.passingBy.places': {
    ca: "Llocs sense avisos", es: "Lugares sin avisos", gl: "Lugares sen avisos", eu: "Abisurik gabeko lekuak", en: "Places without notices", fr: "Lieux sans notifications", pt: "Locais sem avisos", it: "Luoghi senza avvisi",
  },
  'ios.passingBy.placesNone': {
    ca: "Cap", es: "Ninguno", gl: "Ningún", eu: "Bat ere ez", en: "None", fr: "Aucun", pt: "Nenhum", it: "Nessuno",
  },
  'ios.passingBy.placesAdd': {
    ca: "Afegeix un lloc", es: "Añadir un lugar", gl: "Engadir un lugar", eu: "Gehitu leku bat", en: "Add a place", fr: "Ajouter un lieu", pt: "Adicionar um local", it: "Aggiungi un luogo",
  },
  'ios.passingBy.placesHint': {
    ca: "Per les fonts del teu barri hi passes cada dia: no et preguntarem per les que siguin a menys de 300 m d’aquests llocs. Es desen només al telèfon.", es: "Por las fuentes de tu barrio pasas cada día: no te preguntaremos por las que estén a menos de 300 m de estos lugares. Se guardan solo en el teléfono.", gl: "Polas fontes do teu barrio pasas cada día: non che preguntaremos polas que estean a menos de 300 m destes lugares. Gárdanse só no teléfono.", eu: "Zure auzoko iturrien ondotik egunero pasatzen zara: leku hauetatik 300 m baino gutxiagora daudenei buruz ez dizugu galdetuko. Telefonoan bakarrik gordetzen dira.", en: "You pass the fountains in your neighbourhood every day: we won’t ask about those within 300 m of these places. They are stored only on your phone.", fr: "Vous passez chaque jour devant les fontaines de votre quartier : nous ne vous demanderons rien sur celles à moins de 300 m de ces lieux. Ils ne sont enregistrés que sur le téléphone.", pt: "Passa todos os dias pelas fontes do seu bairro: não perguntamos pelas que estejam a menos de 300 m destes locais. São guardados apenas no telemóvel.", it: "Passi ogni giorno davanti alle fontane del tuo quartiere: non ti chiederemo di quelle a meno di 300 m da questi luoghi. Sono salvati solo sul telefono.",
  },
  'ios.passingBy.placeName': {
    ca: "Nom (p. ex. Casa)", es: "Nombre (p. ej. Casa)", gl: "Nome (p. ex. Casa)", eu: "Izena (adib. Etxea)", en: "Name (e.g. Home)", fr: "Nom (p. ex. Maison)", pt: "Nome (p. ex. Casa)", it: "Nome (es. Casa)",
  },
  'ios.passingBy.placeDefault': {
    ca: "Lloc", es: "Lugar", gl: "Lugar", eu: "Lekua", en: "Place", fr: "Lieu", pt: "Local", it: "Luogo",
  },
  'ios.intent.focusTitle': {
    ca: "Avisos en passar per fonts", es: "Avisos al pasar por fuentes", gl: "Avisos ao pasar por fontes", eu: "Iturrien ondotik pasatzean abisuak", en: "Notices when passing fountains", fr: "Notifications près des fontaines", pt: "Avisos ao passar por fontes", it: "Avvisi passando vicino alle fontane",
  },
  'ios.intent.focusDescription': {
    ca: "Silencia les preguntes en passar a prop d’una font mentre aquesta concentració estigui activa.", es: "Silencia las preguntas al pasar cerca de una fuente mientras este modo de concentración esté activo.", gl: "Silencia as preguntas ao pasar preto dunha fonte mentres este modo de concentración estea activo.", eu: "Isilarazi iturri baten ondotik pasatzean egiten diren galderak kontzentrazio modu hau aktibo dagoen bitartean.", en: "Silences the questions when you pass a fountain while this Focus is on.", fr: "Coupe les questions près d’une fontaine tant que ce mode de concentration est actif.", pt: "Silencia as perguntas ao passar perto de uma fonte enquanto este modo de foco estiver ativo.", it: "Silenzia le domande vicino a una fontana mentre questa modalità Full immersion è attiva.",
  },
  'ios.intent.focusMute': {
    ca: "Silencia els avisos", es: "Silenciar avisos", gl: "Silenciar avisos", eu: "Isilarazi abisuak", en: "Silence notices", fr: "Couper les notifications", pt: "Silenciar avisos", it: "Silenzia gli avvisi",
  },
  'ios.intent.focusMuted': {
    ca: "Avisos de fonts silenciats", es: "Avisos de fuentes silenciados", gl: "Avisos de fontes silenciados", eu: "Iturrien abisuak isilduta", en: "Fountain notices silenced", fr: "Notifications de fontaines coupées", pt: "Avisos de fontes silenciados", it: "Avvisi delle fontane silenziati",
  },
  'ios.intent.focusAllowed': {
    ca: "Avisos de fonts permesos", es: "Avisos de fuentes permitidos", gl: "Avisos de fontes permitidos", eu: "Iturrien abisuak baimenduta", en: "Fountain notices allowed", fr: "Notifications de fontaines autorisées", pt: "Avisos de fontes permitidos", it: "Avvisi delle fontane consentiti",
  },
  'ios.intent.pauseLength': {
    ca: "Durada", es: "Duración", gl: "Duración", eu: "Iraupena", en: "Duration", fr: "Durée", pt: "Duração", it: "Durata",
  },
  'ios.intent.pauseTitle': {
    ca: "Pausa els avisos de fonts", es: "Pausar avisos de fuentes", gl: "Pausar avisos de fontes", eu: "Pausatu iturrien abisuak", en: "Pause fountain notices", fr: "Suspendre les notifications de fontaines", pt: "Pausar avisos de fontes", it: "Sospendi gli avvisi delle fontane",
  },
  'ios.intent.pauseDescription': {
    ca: "Deixa de preguntar en passar per fonts durant un temps.", es: "Deja de preguntar al pasar por fuentes durante un tiempo.", gl: "Deixa de preguntar ao pasar por fontes durante un tempo.", eu: "Denbora batez, utzi iturrien ondotik pasatzean galdetzeari.", en: "Stops asking when you pass fountains for a while.", fr: "Arrête de demander près des fontaines pendant un moment.", pt: "Deixa de perguntar ao passar por fontes durante algum tempo.", it: "Smette di chiedere vicino alle fontane per un po’.",
  },
  'ios.intent.pausedDialog': {
    ca: "Avisos de fonts en pausa.", es: "Avisos de fuentes en pausa.", gl: "Avisos de fontes en pausa.", eu: "Iturrien abisuak pausatuta.", en: "Fountain notices paused.", fr: "Notifications de fontaines suspendues.", pt: "Avisos de fontes em pausa.", it: "Avvisi delle fontane in pausa.",
  },
  'ios.intent.resumeTitle': {
    ca: "Reprèn els avisos de fonts", es: "Reanudar avisos de fuentes", gl: "Retomar avisos de fontes", eu: "Berriro aktibatu iturrien abisuak", en: "Resume fountain notices", fr: "Réactiver les notifications de fontaines", pt: "Retomar avisos de fontes", it: "Riattiva gli avvisi delle fontane",
  },
  'ios.intent.resumeDescription': {
    ca: "Torna a preguntar en passar per fonts.", es: "Vuelve a preguntar al pasar por fuentes.", gl: "Volve preguntar ao pasar por fontes.", eu: "Berriro galdetu iturrien ondotik pasatzean.", en: "Asks again when you pass fountains.", fr: "Recommence à demander près des fontaines.", pt: "Volta a perguntar ao passar por fontes.", it: "Torna a chiedere vicino alle fontane.",
  },
  'ios.intent.resumedDialog': {
    ca: "Avisos de fonts represos.", es: "Avisos de fuentes reanudados.", gl: "Avisos de fontes retomados.", eu: "Iturrien abisuak berriro aktibatuta.", en: "Fountain notices resumed.", fr: "Notifications de fontaines réactivées.", pt: "Avisos de fontes retomados.", it: "Avvisi delle fontane riattivati.",
  },
  'ios.passingBy.noticeTitle': {
    ca: 'Passes a prop de: {name}', es: 'Pasas cerca de: {name}', gl: 'Pasas preto de: {name}', eu: 'Hemendik gertu zaude: {name}', en: 'You’re passing near {name}', fr: 'Vous passez près de : {name}', pt: 'Está a passar perto de: {name}', it: 'Stai passando vicino a: {name}',
  },
  'ios.passingBy.noticeTitleUnnamed': {
    ca: 'Passes a prop d’una font', es: 'Pasas cerca de una fuente', gl: 'Pasas preto dunha fonte', eu: 'Iturri baten ondotik pasatzen ari zara', en: 'You’re passing near a fountain', fr: 'Vous passez près d’une fontaine', pt: 'Está a passar perto de uma fonte', it: 'Stai passando vicino a una fontana',
  },
  'ios.passingBy.noticeBody': {
    ca: 'Hi raja aigua? Mantén premut per respondre sense obrir l’app.', es: '¿Sale agua? Mantén pulsado para responder sin abrir la app.', gl: 'Bota auga? Mantén premido para responder sen abrir a app.', eu: 'Ura ateratzen da? Luze sakatu aplikazioa ireki gabe erantzuteko.', en: 'Is water flowing? Press and hold to answer without opening the app.', fr: 'Est-ce que l’eau coule ? Appui long pour répondre sans ouvrir l’app.', pt: 'Está a sair água? Mantenha premido para responder sem abrir a app.', it: 'Esce acqua? Tieni premuto per rispondere senza aprire l’app.',
  },
  'ios.passingBy.notSeen': {
    ca: 'No l’he vista', es: 'No la he visto', gl: 'Non a vin', eu: 'Ez dut ikusi', en: 'I didn’t see it', fr: 'Je ne l’ai pas vue', pt: 'Não a vi', it: 'Non l’ho vista',
  },
  'ios.search.forget': {
    ca: 'Treu-la de les recents', es: 'Quitarla de recientes', gl: 'Quitala das recentes', eu: 'Kendu azkenetatik', en: 'Remove from recent', fr: 'Retirer des récentes', pt: 'Retirar das recentes', it: 'Rimuovi dalle recenti',
  },
  'ios.profile.stale': {
    ca: '{n} fonts que depenen de tu fa més de tres mesos que ningú hi torna', es: '{n} fuentes que dependen de ti llevan más de tres meses sin que nadie vuelva', gl: '{n} fontes que dependen de ti levan máis de tres meses sen que ninguén volva', eu: 'Zure menpeko {n} iturritara ez da inor itzuli hiru hilabete baino gehiagoan', en: '{n} fountains that depend on you have gone over three months without a visit', fr: '{n} fontaines qui dépendent de vous n’ont eu aucune visite depuis plus de trois mois', pt: '{n} fontes que dependem de si estão há mais de três meses sem visita', it: '{n} fontane che dipendono da te sono senza visite da più di tre mesi',
  },
  'ios.browse.next': {
    ca: 'Font més propera a la dreta', es: 'Fuente más cercana a la derecha', gl: 'Fonte máis próxima á dereita', eu: 'Eskuineko iturririk hurbilena', en: 'Nearest fountain to the right', fr: 'Fontaine la plus proche à droite', pt: 'Fonte mais próxima à direita', it: 'Fontana più vicina a destra',
  },
  'ios.browse.previous': {
    ca: 'Font més propera a l’esquerra', es: 'Fuente más cercana a la izquierda', gl: 'Fonte máis próxima á esquerda', eu: 'Ezkerreko iturririk hurbilena', en: 'Nearest fountain to the left', fr: 'Fontaine la plus proche à gauche', pt: 'Fonte mais próxima à esquerda', it: 'Fontana più vicina a sinistra',
  },
  'ios.showAll': {
    ca: 'Mostra-les totes ({n})', es: 'Mostrar todas ({n})', gl: 'Amosalas todas ({n})', eu: 'Erakutsi guztiak ({n})', en: 'Show all ({n})', fr: 'Tout afficher ({n})', pt: 'Mostrar todas ({n})', it: 'Mostra tutte ({n})',
  },
  'ios.more': {
    ca: 'Més', es: 'Más', gl: 'Máis', eu: 'Gehiago', en: 'More', fr: 'Plus', pt: 'Mais', it: 'Altro',
  },
  'ios.search.fountains': {
    ca: 'Fonts', es: 'Fuentes', gl: 'Fontes', eu: 'Iturriak', en: 'Fountains', fr: 'Fontaines', pt: 'Fontes', it: 'Fontane',
  },
  'ios.search.places': {
    ca: 'Llocs', es: 'Lugares', gl: 'Lugares', eu: 'Lekuak', en: 'Places', fr: 'Lieux', pt: 'Locais', it: 'Luoghi',
  },
  'ios.offline.title': {
    ca: 'Sense cobertura', es: 'Sin cobertura', gl: 'Sen cobertura', eu: 'Estaldurarik gabe',
    en: 'Offline', fr: 'Hors ligne', pt: 'Sem rede', it: 'Senza copertura',
  },
  'ios.offline.saved': {
    ca: 'Zones desades', es: 'Zonas guardadas', gl: 'Zonas gardadas', eu: 'Gordetako eremuak',
    en: 'Saved zones', fr: 'Zones enregistrées', pt: 'Zonas guardadas', it: 'Zone salvate',
  },
  'ios.offline.layerCannot': {
    ca: 'El mapa «{layer}» no es pot desar. Tria ICGC o IGN a Capes per endur-te el mapa.',
    es: 'El mapa «{layer}» no se puede guardar. Elige ICGC o IGN en Capas para llevarte el mapa.',
    gl: 'O mapa «{layer}» non se pode gardar. Escolle ICGC ou IGN en Capas para levar o mapa.',
    eu: '«{layer}» mapa ezin da gorde. Aukeratu ICGC edo IGN Geruzetan mapa eramateko.',
    en: 'The “{layer}” map can’t be saved. Choose ICGC or IGN in Layers to take the map with you.',
    fr: 'La carte « {layer} » ne peut pas être enregistrée. Choisis ICGC ou IGN dans Calques pour emporter la carte.',
    pt: 'O mapa «{layer}» não pode ser guardado. Escolhe ICGC ou IGN em Camadas para levares o mapa.',
    it: 'La mappa «{layer}» non si può salvare. Scegli ICGC o IGN in Livelli per portare con te la mappa.',
  },
  'ios.offline.tooManyTiles': {
    ca: 'La zona és massa gran per desar-ne el mapa. Apropa’t una mica i torna-ho a provar.',
    es: 'La zona es demasiado grande para guardar el mapa. Acércate un poco y vuelve a intentarlo.',
    gl: 'A zona é grande de máis para gardar o mapa. Achégate un pouco e téntao de novo.',
    eu: 'Eremua handiegia da mapa gordetzeko. Hurbildu pixka bat eta saiatu berriro.',
    en: 'The zone is too big to save its map. Zoom in a little and try again.',
    fr: 'La zone est trop grande pour enregistrer la carte. Rapproche-toi un peu et réessaie.',
    pt: 'A zona é demasiado grande para guardar o mapa. Aproxima-te um pouco e tenta de novo.',
    it: 'La zona è troppo grande per salvare la mappa. Avvicinati un po’ e riprova.',
  },
  'ios.gpx.import': {
    ca: 'Aigua a la meva ruta (GPX)', es: 'Agua en mi ruta (GPX)', gl: 'Auga na miña ruta (GPX)',
    eu: 'Ura nire ibilbidean (GPX)', en: 'Water on my route (GPX)', fr: 'De l’eau sur mon itinéraire (GPX)',
    pt: 'Água no meu percurso (GPX)', it: 'Acqua sul mio percorso (GPX)',
  },
  'ios.gpx.export': {
    ca: 'Baixa les fonts d’aquí en GPX', es: 'Descargar las fuentes de aquí en GPX', gl: 'Descargar as fontes de aquí en GPX',
    eu: 'Deskargatu hemengo iturriak GPXn', en: 'Download the fountains here as GPX',
    fr: 'Télécharger les fontaines d’ici en GPX', pt: 'Descarregar as fontes daqui em GPX',
    it: 'Scarica le fontane di qui in GPX',
  },
  'ios.gpx.privacy': {
    ca: 'El fitxer es llegeix al mòbil i no en surt. Al servidor només se li demanen les fonts de la zona.',
    es: 'El fichero se lee en el móvil y no sale de él. Al servidor solo se le piden las fuentes de la zona.',
    gl: 'O ficheiro lese no móbil e non sae del. Ao servidor só se lle piden as fontes da zona.',
    eu: 'Fitxategia mugikorrean irakurtzen da eta ez da handik ateratzen. Zerbitzariari eremuko iturriak baino ez zaizkio eskatzen.',
    en: 'The file is read on the phone and never leaves it. Only the fountains of the area are asked of the server.',
    fr: 'Le fichier est lu sur le téléphone et n’en sort pas. On ne demande au serveur que les fontaines de la zone.',
    pt: 'O ficheiro é lido no telemóvel e não sai dele. Ao servidor só se pedem as fontes da zona.',
    it: 'Il file viene letto sul telefono e non ne esce. Al server si chiedono solo le fontane della zona.',
  },
  'ios.newFont.moveMap': {
    ca: 'Mou el mapa fins que el punt quedi damunt la font.', es: 'Mueve el mapa hasta que el punto quede sobre la fuente.',
    gl: 'Move o mapa ata que o punto quede enriba da fonte.', eu: 'Mugitu mapa puntua iturriaren gainean geratu arte.',
    en: 'Move the map until the pin sits on the fountain.', fr: 'Déplace la carte jusqu’à ce que le repère soit sur la fontaine.',
    pt: 'Move o mapa até o ponto ficar sobre a fonte.', it: 'Sposta la mappa finché il segnaposto è sulla fontana.',
  },
  'ios.newFont.bigMap': {
    ca: 'Mapa gran', es: 'Mapa grande', gl: 'Mapa grande', eu: 'Mapa handia', en: 'Large map', fr: 'Grande carte',
    pt: 'Mapa grande', it: 'Mappa grande',
  },
  'ios.newFont.placeHere': {
    ca: 'Posa-la aquí', es: 'Ponerla aquí', gl: 'Poñela aquí', eu: 'Hemen jarri', en: 'Put it here', fr: 'La mettre ici',
    pt: 'Pô-la aqui', it: 'Mettila qui',
  },
  'ios.newFont.itIsDifferent': {
    ca: 'És una altra font', es: 'Es otra fuente', gl: 'É outra fonte', eu: 'Beste iturri bat da',
    en: 'It’s a different fountain', fr: 'C’est une autre fontaine', pt: 'É outra fonte', it: 'È un’altra fontana',
  },
  'ios.signUp.emailInvalid': {
    ca: 'Aquest correu no sembla vàlid.', es: 'Ese correo no parece válido.', gl: 'Ese correo non parece válido.',
    eu: 'Posta helbide hori ez dirudi baliozkoa.', en: 'That email doesn’t look valid.',
    fr: 'Cet e-mail ne semble pas valide.', pt: 'Esse e-mail não parece válido.', it: 'Questa email non sembra valida.',
  },
  'ios.signUp.passwordShort': {
    ca: 'La contrasenya ha de tenir almenys 8 caràcters.', es: 'La contraseña debe tener al menos 8 caracteres.',
    gl: 'O contrasinal debe ter polo menos 8 caracteres.', eu: 'Pasahitzak gutxienez 8 karaktere izan behar ditu.',
    en: 'The password needs at least 8 characters.', fr: 'Le mot de passe doit contenir au moins 8 caractères.',
    pt: 'A palavra-passe tem de ter pelo menos 8 caracteres.', it: 'La password deve avere almeno 8 caratteri.',
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
  // Kept here, not only in the catalog: this script rebuilds the catalog and drops what is not listed.
  'ios.mapCache.title': {
    ca: 'Mapes vistos',
    es: 'Mapas vistos',
    gl: 'Mapas vistos',
    eu: 'Ikusitako mapak',
    en: 'Maps seen',
    fr: 'Cartes vues',
    pt: 'Mapas vistos',
    it: 'Mappe viste',
  },
  'ios.mapCache.body': {
    ca: 'Els trossos de mapa que mires es queden en aquest mòbil: no es tornen a baixar i hi són sense cobertura. Fins a {size}; se\'n van els més antics. Les zones desades a dalt van a part i mai s\'esborren per fer lloc.',
    es: 'Los trozos de mapa que miras se quedan en este móvil: no se vuelven a descargar y están ahí sin cobertura. Hasta {size}; se van los más antiguos. Las zonas guardadas arriba van aparte y nunca se borran para hacer sitio.',
    gl: 'Os anacos de mapa que miras quedan neste móbil: non se volven descargar e están aí sen cobertura. Ata {size}; van saíndo os máis antigos. As zonas gardadas arriba van á parte e nunca se borran para facer sitio.',
    eu: 'Begiratzen dituzun mapa-zatiak telefono honetan gelditzen dira: ez dira berriro deskargatzen eta estalduraz kanpo ere hor daude. {size} arte; zaharrenak lehenago joaten dira. Goian gordetako guneak bereiz gordetzen dira eta ez dira sekula ezabatzen lekua egiteko.',
    en: 'The parts of the map you look at stay on this phone: they are not downloaded again and are there without signal. Up to {size}; the oldest go first. Zones saved above are kept apart and never removed to make room.',
    fr: 'Les morceaux de carte que vous regardez restent sur ce téléphone : ils ne sont pas retéléchargés et sont là sans réseau. Jusqu\'à {size} ; les plus anciens partent en premier. Les zones enregistrées ci-dessus sont à part et jamais supprimées pour faire de la place.',
    pt: 'Os pedaços de mapa que vê ficam neste telemóvel: não são descarregados de novo e estão lá sem rede. Até {size}; os mais antigos saem primeiro. As zonas guardadas acima ficam à parte e nunca são apagadas para dar espaço.',
    it: 'I pezzi di mappa che guardi restano su questo telefono: non vengono scaricati di nuovo e ci sono anche senza copertura. Fino a {size}; i più vecchi se ne vanno per primi. Le zone salvate sopra restano a parte e non vengono mai eliminate per fare spazio.',
  },
  'ios.mapCache.clear': {
    ca: 'Oblida els mapes vistos',
    es: 'Olvidar mapas vistos',
    gl: 'Esquecer os mapas vistos',
    eu: 'Ahaztu ikusitako mapak',
    en: 'Forget maps seen',
    fr: 'Oublier les cartes vues',
    pt: 'Esquecer os mapas vistos',
    it: 'Dimentica le mappe viste',
  },
  'ios.photo.unreadable': {
    ca: 'No s\'ha pogut llegir aquesta foto. Prova\'n una altra.',
    es: 'No se ha podido leer esa foto. Prueba con otra.',
    gl: 'Non se puido ler esa foto. Proba con outra.',
    eu: 'Ezin izan da argazki hori irakurri. Saiatu beste batekin.',
    en: 'That photo could not be read. Try another one.',
    fr: 'Cette photo n\'a pas pu être lue. Essayez-en une autre.',
    pt: 'Não foi possível ler essa foto. Tente outra.',
    it: 'Impossibile leggere questa foto. Prova con un\'altra.',
  },
  'ios.photoSaved': {
    ca: 'Desada a Fotos',
    es: 'Guardada en Fotos',
    gl: 'Gardada en Fotos',
    eu: 'Argazkietan gordeta',
    en: 'Saved to Photos',
    fr: 'Enregistrée dans Photos',
    pt: 'Guardada em Fotos',
    it: 'Salvata in Foto',
  },
  'ios.photoSaveDenied': {
    ca: 'Sense accés a Fotos. Permet-ho a Ajustos per desar la foto.',
    es: 'Sin acceso a Fotos. Permítelo en Ajustes para guardar la foto.',
    gl: 'Sen acceso a Fotos. Permítoo en Axustes para gardar a foto.',
    eu: 'Ez dago Argazkietarako sarbiderik. Baimendu Ezarpenetan argazkia gordetzeko.',
    en: 'No access to Photos. Allow it in Settings to save the photo.',
    fr: 'Pas d\'accès à Photos. Autorisez-le dans Réglages pour enregistrer la photo.',
    pt: 'Sem acesso a Fotos. Permita-o em Definições para guardar a foto.',
    it: 'Nessun accesso a Foto. Consentilo in Impostazioni per salvare la foto.',
  },
  'ios.photoSaveFailed': {
    ca: 'No s\'ha pogut desar la foto.',
    es: 'No se ha podido guardar la foto.',
    gl: 'Non se puido gardar a foto.',
    eu: 'Ezin izan da argazkia gorde.',
    en: 'The photo could not be saved.',
    fr: 'La photo n\'a pas pu être enregistrée.',
    pt: 'Não foi possível guardar a foto.',
    it: 'Impossibile salvare la foto.',
  },
  'ios.passingBy.motionTitle': {
    ca: 'Saber quan vas en cotxe',
    es: 'Saber cuándo vas en coche',
    gl: 'Saber cando vas en coche',
    eu: 'Autoan zoazenean jakitea',
    en: 'Know when you are driving',
    fr: 'Savoir quand vous êtes en voiture',
    pt: 'Saber quando vai de carro',
    it: 'Sapere quando sei in auto',
  },
  'ios.passingBy.motionBody': {
    ca: 'Per no preguntar-te per una font quan hi passes en cotxe, FontApp necessita «Moviment i forma física». Només es consulta en decidir l’avís i no es desa. Sense aquest permís, els avisos de pas quedaran en pausa.',
    es: 'Para no preguntarte por una fuente cuando pasas en coche, FontApp necesita «Movimiento y forma física». Solo se consulta al decidir el aviso y no se guarda. Sin este permiso, los avisos al pasar quedarán en pausa.',
    gl: 'Para non preguntarche por unha fonte cando pasas en coche, FontApp precisa «Movemento e forma física». Só se consulta ao decidir o aviso e non se garda. Sen este permiso, os avisos ao pasar quedarán en pausa.',
    eu: 'Autoan pasatzean abisurik ez bidaltzeko, FontApp-ek «Mugimendua eta sasoia» baimena behar du. Abisua erabakitzeko bakarrik erabiltzen da, eta ez da gordetzen. Baimenik gabe, igarotze-abisuak pausatuta egongo dira.',
    en: 'To avoid asking about a fountain when you drive past, FontApp needs Motion & Fitness. It is checked only when deciding on a notice and is not stored. Without it, passing-by notices are paused.',
    fr: 'Pour éviter les alertes quand vous passez en voiture, FontApp a besoin de « Mouvements et forme ». Cette donnée n’est consultée que pour décider de l’alerte et n’est pas conservée. Sans cette autorisation, les alertes de passage sont suspendues.',
    pt: 'Para evitar avisos quando passa de carro, a FontApp precisa de «Movimento e forma física». Só é consultado ao decidir o aviso e não é guardado. Sem esta permissão, os avisos de passagem ficam em pausa.',
    it: 'Per evitare avvisi quando passi in auto, FontApp richiede «Movimento e fitness». Viene consultato solo per decidere l’avviso e non viene conservato. Senza il permesso, gli avvisi di passaggio restano in pausa.',
  },
  'ios.passingBy.motionNeeded': {
    ca: 'Els avisos de pas s’ometen quan no podem descartar que vagis en cotxe. Dona accés a Moviment i forma física als Ajustos de l’iPhone.',
    es: 'Se omiten los avisos al pasar cuando no podemos descartar que vayas en coche. Da acceso a Movimiento y forma física en Ajustes del iPhone.',
    gl: 'Omítense os avisos ao pasar cando non podemos descartar que vaias en coche. Dá acceso a Movemento e forma física nos Axustes do iPhone.',
    eu: 'Autoan ez zoazela ziurtatu ezin dugunean, igarotze-abisuak baztertzen ditugu. Eman Mugimendua eta sasoia baimena iPhonearen Ezarpenetan.',
    en: 'Passing-by notices are skipped when we cannot rule out driving. Allow Motion & Fitness in iPhone Settings.',
    fr: 'Les alertes de passage sont ignorées si nous ne pouvons pas exclure la voiture. Autorisez « Mouvements et forme » dans les réglages de l’iPhone.',
    pt: 'Os avisos de passagem são ignorados quando não podemos excluir que vai de carro. Autorize Movimento e forma física nas Definições do iPhone.',
    it: 'Gli avvisi di passaggio vengono omessi quando non possiamo escludere che tu sia in auto. Consenti Movimento e fitness nelle Impostazioni dell’iPhone.',
  },
  'ios.passingBy.motionContinue': {
    ca: 'Continua',
    es: 'Continuar',
    gl: 'Continuar',
    eu: 'Jarraitu',
    en: 'Continue',
    fr: 'Continuer',
    pt: 'Continuar',
    it: 'Continua',
  },
  'ios.passingBy.motionNotNow': {
    ca: 'Ara no',
    es: 'Ahora no',
    gl: 'Agora non',
    eu: 'Orain ez',
    en: 'Not now',
    fr: 'Pas maintenant',
    pt: 'Agora não',
    it: 'Non ora',
  },
  'ios.photo.icloud': {
    ca: 'Aquesta foto no és en aquest mòbil (és a iCloud) i no hi ha connexió per baixar-la. Tria\'n una desada al mòbil o fes-ne una de nova.',
    es: 'Esa foto no está en este móvil (está en iCloud) y no hay conexión para descargarla. Elige una guardada en el móvil o haz una nueva.',
    gl: 'Esa foto non está neste móbil (está en iCloud) e non hai conexión para descargala. Escolle unha gardada no móbil ou fai unha nova.',
    eu: 'Argazki hori ez dago telefono honetan (iCloud-en dago) eta ez dago konexiorik deskargatzeko. Aukeratu telefonoan gordeta dagoen bat edo atera berri bat.',
    en: 'That photo is not on this phone (it is in iCloud) and there is no connection to download it. Choose one saved on the phone, or take a new one.',
    fr: 'Cette photo n\'est pas sur ce téléphone (elle est dans iCloud) et il n\'y a pas de connexion pour la télécharger. Choisissez-en une enregistrée sur le téléphone ou prenez-en une nouvelle.',
    pt: 'Essa foto não está neste telemóvel (está no iCloud) e não há ligação para a descarregar. Escolha uma guardada no telemóvel ou tire uma nova.',
    it: 'Quella foto non è su questo telefono (è su iCloud) e non c’è connessione per scaricarla. Scegline una salvata sul telefono o scattane una nuova.',
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
writeCatalog(join(here, '../FontApp/FontApp/Localizable.xcstrings'), strings)

// The widget is its own bundle and cannot read the app's catalog: it gets the few web
// strings it shows plus its own.
const WIDGET_KEYS = ['status.flowing', 'status.trickle', 'status.dry', 'status.broken', 'status.gone',
  'status.unknown', 'confidence.unverified', 'font.unnamed']
const WIDGET_ONLY = {
  'widget.name': {
    ca: 'Fonts a prop', es: 'Fuentes cerca', gl: 'Fontes preto', eu: 'Iturriak gertu', en: 'Fountains nearby', fr: 'Fontaines à proximité', pt: 'Fontes perto', it: 'Fontane vicine',
  },
  'widget.description': {
    ca: 'La font més propera i com està, sense obrir l’app.', es: 'La fuente más cercana y cómo está, sin abrir la app.', gl: 'A fonte máis próxima e como está, sen abrir a app.', eu: 'Iturririk hurbilena eta nola dagoen, aplikazioa ireki gabe.', en: 'The nearest fountain and how it is, without opening the app.', fr: 'La fontaine la plus proche et son état, sans ouvrir l’app.', pt: 'A fonte mais próxima e como está, sem abrir a app.', it: 'La fontana più vicina e com’è, senza aprire l’app.',
  },
  'widget.noLocation': {
    ca: 'Obre FontApp i permet la ubicació per veure les fonts properes.', es: 'Abre FontApp y permite la ubicación para ver las fuentes cercanas.', gl: 'Abre FontApp e permite a localización para ver as fontes próximas.', eu: 'Ireki FontApp eta baimendu kokapena inguruko iturriak ikusteko.', en: 'Open FontApp and allow location to see nearby fountains.', fr: 'Ouvrez FontApp et autorisez la localisation pour voir les fontaines proches.', pt: 'Abra a FontApp e permita a localização para ver as fontes próximas.', it: 'Apri FontApp e consenti la posizione per vedere le fontane vicine.',
  },
  'widget.nothing': {
    ca: 'No hi ha fonts conegudes a prop.', es: 'No hay fuentes conocidas cerca.', gl: 'Non hai fontes coñecidas preto.', eu: 'Ez dago iturri ezagunik gertu.', en: 'No known fountains nearby.', fr: 'Aucune fontaine connue à proximité.', pt: 'Não há fontes conhecidas perto.', it: 'Nessuna fontana conosciuta nelle vicinanze.',
  },
  'widget.offline': {
    ca: 'Sense connexió. Ho tornarem a provar aviat.', es: 'Sin conexión. Lo volveremos a intentar pronto.', gl: 'Sen conexión. Tentarémolo de novo pronto.', eu: 'Konexiorik gabe. Laster saiatuko gara berriro.', en: 'No connection. We’ll try again soon.', fr: 'Pas de connexion. Nouvel essai bientôt.', pt: 'Sem ligação. Voltamos a tentar em breve.', it: 'Nessuna connessione. Riproveremo presto.',
  },
}
const widget = {}
for (const key of WIDGET_KEYS) {
  if (!strings[key]) throw new Error(`Widget key not in the app catalog: ${key}`)
  widget[key] = strings[key]
}
for (const [key, texts] of Object.entries(WIDGET_ONLY)) {
  const localizations = {}
  for (const [web, apple] of Object.entries(LANGS)) localizations[apple] = unit(texts[web])
  widget[key] = { extractionState: 'manual', localizations }
}
writeCatalog(join(here, '../FontApp/FontAppWidget/Localizable.xcstrings'), widget)

function writeCatalog(out, source) {
  const strings = { ...source }

  // Keep what Xcode extracted by itself (format strings like "%lld km", with no
  // translations), and write the file the way Xcode does: same key order, " : " and
  // blank empty objects. Otherwise every run and every build rewrite the whole file.
  const previous = existsSync(out) ? JSON.parse(readFileSync(out, 'utf8')).strings : {}
  for (const [key, entry] of Object.entries(previous)) {
    if (!(key in strings) && entry.extractionState !== 'manual') strings[key] = entry
  }
  // Xcode's order is its own (roughly case-insensitive): keep the keys it placed where they
  // are, and slot new ones in before the first key that sorts after them.
  const order = Object.keys(previous).filter((k) => k in strings)
  for (const key of Object.keys(strings).sort(xcodeOrder)) {
    if (order.includes(key)) continue
    const at = order.findIndex((k) => xcodeOrder(k, key) > 0)
    order.splice(at === -1 ? order.length : at, 0, key)
  }
  const ordered = {}
  for (const key of order) ordered[key] = sortKeys(strings[key])
  const json = JSON.stringify({ sourceLanguage: 'ca', strings: ordered, version: '1.0' }, null, 2)
    .replace(/^(\s*"(?:[^"\\]|\\.)*"): /gm, '$1 : ')
    .replace(/^(\s*)(.*)\{\}(,?)$/gm, '$1$2{\n\n$1}$3')
  writeFileSync(out, json)
  console.log(`${Object.keys(ordered).length} keys → ${out}`)
}

// Inside an entry Xcode sorts plainly: languages, then "state" before "value".
function sortKeys(value) {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return value
  return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])]))
}

function xcodeOrder(a, b) {
  const x = a.toLowerCase(), y = b.toLowerCase()
  return x < y ? -1 : x > y ? 1 : 0
}
