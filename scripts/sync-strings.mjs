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
  'login.', 'notif.', 'popup.', 'profile.', 'guard.', 'game.', 'privacy.', 'settings.', 'remote.', 'confirm.', 'toast.', 'offline.', 'zonaOff.', 'gpx.', 'gpxIn.', 'newFont.', 'draft.', 'mission.', 'flag.', 'update.', 'comment.', 'report.', 'gallery.', 'dup.', 'image.', 'maint.', 'hidden.', 'badges.', 'celebrate.', 'waterHelp.', 'drinkHelp.', 'sourceLimit.', 'carousel.', 'approach.', 'detail.badges.', 'exif.', 'user.', 'gamePage.', 'gameHelp.', 'passkey.']
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
  'detail.addPhoto', 'detail.firstPhotoNote', 'nav.logout', 'nav.enter', 'staff.tag', 'settings.account', 'photo.failed',
  'profile.deleteAccount', 'profile.confirmDelete', 'profile.dangerZone', 'profile.dangerZoneHint',
  'maintenance.recovered', 'favorite.save', 'favorite.saved',
  'detail.noPhotoYet', 'detail.viewOnMap', 'detail.share', 'detail.shareText', 'detail.nearWaterTitle', 'detail.nearWaterGo', 'form.cancel', 'detail.createdBy', 'detail.pioneerBy', 'detail.mayorBy', 'detail.mayorReviews', 'detail.mayorHelp', 'detail.confirmDeleteFont', 'detail.delete', 'detail.newUpdate', 'detail.confirmDeleteIncident', 'review.confirmDelete', 'detail.useAsMainPhoto', 'detail.photoSetAsMain', 'form.undo', 'form.create', 'detail.municipality', 'footer.legal', 'nav.guide', 'detail.region', 'detail.country', 'detail.stale',
  'detail.changed', 'detail.viewPreviousReviews', 'detail.reportStatus',
]

const IOS_ONLY = {
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
