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

const PREFIXES = ['country.', 'layer.', 'legend.', 'status.', 'confidence.', 'drink.', 'time.', 'error.', 'err.', 'incident.', 'activity.', 'news.',
  'login.', 'notif.', 'popup.', 'profile.', 'guard.', 'game.', 'privacy.', 'settings.', 'remote.', 'confirm.', 'toast.', 'offline.', 'zonaOff.', 'gpx.', 'gpxIn.', 'newFont.', 'draft.', 'mission.', 'flag.', 'update.', 'comment.', 'report.', 'gallery.', 'dup.', 'image.', 'maint.', 'hidden.', 'badges.', 'celebrate.', 'waterHelp.', 'drinkHelp.', 'sourceLimit.', 'carousel.', 'approach.', 'detail.badges.', 'exif.', 'user.']
const KEYS = [
  'map.geoDenied', 'map.geoUnavailable',
  'detail.edit', 'detail.editInfoHint', 'detail.editInfoNote', 'detail.editingTitle', 'detail.replacePhoto',
  'form.save', 'form.saving', 'form.discard', 'form.discardTitle', 'form.discardBody', 'form.keepEditing',
  'relocate.title', 'relocate.useMyLocation', 'relocate.locating', 'relocate.undo', 'relocate.moved',
  'relocate.notYours', 'relocate.accuracy', 'relocate.poorAccuracy',
  'cap.blocked.restricted', 'cap.blocked.optedOut', 'cap.blocked.unavailable',
  'cap.blocked.recentlyVoided', 'cap.blocked.activeDays',
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
  'detail.addPhoto', 'detail.firstPhotoNote', 'nav.logout', 'nav.enter', 'staff.tag', 'settings.account', 'photo.failed',
  'profile.deleteAccount', 'profile.confirmDelete', 'profile.dangerZone', 'profile.dangerZoneHint',
  'maintenance.recovered', 'favorite.save', 'favorite.saved',
  'detail.noPhotoYet', 'detail.viewOnMap', 'detail.share', 'detail.shareText', 'detail.nearWaterTitle', 'detail.nearWaterGo', 'form.cancel', 'detail.createdBy', 'detail.pioneerBy', 'detail.mayorBy', 'detail.mayorReviews', 'detail.mayorHelp', 'detail.confirmDeleteFont', 'detail.delete', 'detail.newUpdate', 'detail.confirmDeleteIncident', 'review.confirmDelete', 'detail.useAsMainPhoto', 'detail.photoSetAsMain', 'form.undo', 'form.create', 'detail.municipality', 'detail.region', 'detail.country', 'detail.stale',
]

const IOS_ONLY = {
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

// Inside an entry Xcode sorts plainly: languages, then "state" before "value".
function sortKeys(value) {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return value
  return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])]))
}

function xcodeOrder(a, b) {
  const x = a.toLowerCase(), y = b.toLowerCase()
  return x < y ? -1 : x > y ? 1 : 0
}
