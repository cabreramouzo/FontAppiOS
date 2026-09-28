import Foundation
import Testing
@testable import FontApp

private func spanish() -> Bundle {
    Bundle(path: Bundle.main.path(forResource: "es", ofType: "lproj")!)!
}

private func notice(_ kind: String, excerpt: String = "", fontName: String? = "Font del Faig",
                    read: Bool = false) -> NotificationItem {
    NotificationItem(id: UUID(), kind: kind, actorName: "marta_r", fontID: UUID(), fontName: fontName,
                     excerpt: excerpt, read: read, createdAt: .now)
}

struct NotificationTextTests {
    let es = spanish()

    @Test func codesBecomeWordsInTheReadersLanguage() {
        #expect(NotificationText.title(notice("reviewConfirmed"), bundle: es) == "marta_r confirma tu reseña")
        #expect(NotificationText.body(notice("fontUpdate", excerpt: "review:dry"), bundle: es)
            == L10n.t("notif.fontUpdate.reviewWithStatus", ["user": "marta_r", "status": "🚱 " + L10n.t("status.dry", bundle: es)], bundle: es))
        #expect(NotificationText.body(notice("fontUpdate", excerpt: "hidden:retired"), bundle: es)
            == "Se ha retirado: ya no está.")
        #expect(NotificationText.body(notice("fontUpdate", excerpt: "resolved"), bundle: es)
            == "La incidencia se ha resuelto: vuelve a manar.")
    }

    @Test func unknownCodesNeverShowRaw() {
        // A code from a newer server, and a status this build does not know.
        #expect(NotificationText.body(notice("fontUpdate", excerpt: "moved:north"), bundle: es) == "Ha habido un cambio.")
        #expect(NotificationText.body(notice("fontUpdate", excerpt: "review:sparkling"), bundle: es) == "marta_r ha pasado por allí.")
        #expect(!NotificationText.title(notice("brandNewKind"), bundle: es).contains("notif."))
    }

    @Test func figuresAndUnnamedFountains() {
        let stale = notice("staleGuarded", excerpt: "7|6|142", fontName: nil)
        #expect(NotificationText.title(stale, bundle: es) == "7 fuentes que cuidas se han quedado viejas")
        #expect(NotificationText.body(stale, bundle: es).contains("Fuente sin nombre"))
        #expect(NotificationText.body(stale, bundle: es).contains("142"))
        #expect(NotificationText.figures("garbage") == (0, 0, 0))
    }
}

extension StubbedNetwork {
@MainActor struct BellTests {
    private let inbox = """
    {"unread":1,"items":[{"id":"00000000-0000-0000-0000-00000000000A","kind":"commentLike","actorName":"jordi88",
    "fontID":null,"fontName":null,"excerpt":"","read":false,"createdAt":"2026-09-28T09:00:00Z"}]}
    """

    @Test func loadingDoesNotMarkReadButOpeningDoes() async {
        StubProtocol.sent = []
        StubProtocol.responses = ["GET /notifications": (200, inbox), "POST /notifications/read": (204, "")]
        let bell = Bell(api: StubProtocol.client())
        await bell.reload()
        #expect(bell.unread == 1 && bell.items.first?.fontID == nil)
        #expect(!StubProtocol.sent.contains { $0.path == "/notifications/read" })
        await bell.opened()
        #expect(bell.unread == 0)
        #expect(StubProtocol.sent.contains { $0.method == "POST" && $0.path == "/notifications/read" })
        // Still shown as new until the next load, so you can tell which ones they were.
        #expect(bell.items.first?.read == false)
    }

    @Test func aFailedMarkKeepsTheCountAndNoSignalKeepsTheInbox() async {
        StubProtocol.responses = ["GET /notifications": (200, inbox), "POST /notifications/read": (-1, "")]
        let bell = Bell(api: StubProtocol.client())
        await bell.reload()
        await bell.opened()
        #expect(bell.unread == 1)
        StubProtocol.responses["GET /notifications"] = (-1, "")
        await bell.reload()
        #expect(bell.items.count == 1)
        bell.clear()
        #expect(bell.items.isEmpty && bell.unread == 0)
    }
}
}
