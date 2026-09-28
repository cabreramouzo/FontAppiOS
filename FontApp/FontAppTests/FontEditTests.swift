import Foundation
import Testing
@testable import FontApp

private let fountainID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let creatorID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
private let visitorID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
private let fontJSON = """
{"id":"11111111-1111-1111-1111-111111111111","name":"Original","latitude":41.8,"longitude":2.1,
"creator":{"id":"22222222-2222-2222-2222-222222222222"},"image":"/uploads/cover.jpg",
"description":"Old description","source":"spring","drinkable":"untreated"}
"""
private func font() throws -> FontDetail { try APIClient.decoder.decode(FontDetail.self, from: Data(fontJSON.utf8)) }
private func user(_ role: UserRole = .user, id: UUID = visitorID) -> UserResponse {
    UserResponse(id: id, name: "Test", username: "test", role: role)
}

struct FontEditPermissionTests {
    @Test func roleAndOwnershipMatrix() throws {
        let fountain = try font()
        for role in [UserRole.user, .moderator, .admin, .owner] {
            for id in [creatorID, visitorID] {
                let permissions = FontEditPermissions(user: user(role, id: id), font: fountain, grant: nil)
                #expect(permissions.canEdit)
                #expect(permissions.canRelocate == (id == creatorID || role >= .admin))
                #expect(permissions.canSetPhoto == (id == creatorID || role >= .admin))
            }
        }
        let anonymous = FontEditPermissions(user: nil, font: fountain, grant: nil)
        #expect(!anonymous.canEdit && !anonymous.canRelocate && !anonymous.canSetPhoto)
    }

    @Test func earnedRelocationDoesNotGrantPhotoReplacement() throws {
        let grant = FontEditGrant(capabilities: ["relocateAnyFont", "addSecondaryPhoto"], blockedBy: [])
        let permissions = FontEditPermissions(user: user(), font: try font(), grant: grant)
        #expect(permissions.canRelocate)
        #expect(!permissions.canSetPhoto)
        for reason in ["disabled", "provisional", "optedOut", "activeDays", "recentlyVoided"] {
            let p = FontEditPermissions(user: user(), font: try font(),
                                        grant: FontEditGrant(capabilities: [], blockedBy: [reason]))
            #expect(p.canEdit)
            #expect(!p.canRelocate)
        }
    }

    @Test func importedFountainAndPostingRestriction() throws {
        let imported = try APIClient.decoder.decode(FontDetail.self, from: Data("""
        {"id":"\(fountainID)","latitude":41.8,"longitude":2.1,"creator":{"id":null}}
        """.utf8))
        let permissions = FontEditPermissions(user: user(), font: imported, grant: nil)
        #expect(permissions.canEdit && permissions.canSetPhoto && !permissions.canRelocate)
        for role in [UserRole.user, .moderator, .admin, .owner] {
            let restricted = FontEditPermissions(user: user(role, id: creatorID), font: imported,
                                                 grant: FontEditGrant(capabilities: [], blockedBy: ["restricted"]))
            #expect(!restricted.canEdit && !restricted.canSetPhoto && !restricted.canRelocate)
        }
    }

    @Test func untouchedFieldsUseLatestDataAndClearingFieldsWorks() throws {
        let original = try font()
        var fields = FontEditFields(original)
        fields.name = "  "
        fields.description = ""
        fields.source = nil
        fields.drinkable = nil
        let current = try APIClient.decoder.decode(FontDetail.self, from: Data(fontJSON
            .replacingOccurrences(of: "41.8", with: "41.9")
            .replacingOccurrences(of: "cover.jpg", with: "new-cover.jpg").utf8))
        let permissions = FontEditPermissions(user: user(.admin), font: current, grant: nil)
        let payload = fields.payload(baseline: FontEditFields(original), current: current,
                                     permissions: permissions, image: nil)
        #expect(payload.name == nil && payload.description == nil)
        #expect(payload.source == nil && payload.drinkable == nil)
        #expect(payload.latitude == 41.9)
        #expect(payload.image == "/uploads/new-cover.jpg")
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(json["latitude"] as? Double == 41.9)
        #expect(json["allowNearbyDuplicate"] == nil)
    }

    @Test func draftsExpireAndAreScopedToAccountFountainAndServer() throws {
        let defaults = UserDefaults(suiteName: "FontEditTests.\(UUID())")!
        let origin = URL(string: "https://test.invalid")!
        let key = FontEditDraft.key(origin: origin, userID: creatorID, fontID: fountainID)
        let fields = FontEditFields(try font())
        let now = Date()
        let draft = FontEditDraft(baseline: fields, fields: fields, hadPhoto: true, savedAt: now)
        defaults.set(try JSONEncoder().encode(draft), forKey: key)
        defer { defaults.removeObject(forKey: key) }
        #expect(FontEditDraft.load(key: key, defaults: defaults, now: now)?.hadPhoto == true)
        #expect(FontEditDraft.load(key: key, defaults: defaults, now: now.addingTimeInterval(7 * 86_400)) == nil)
        #expect(key != FontEditDraft.key(origin: origin, userID: visitorID, fontID: fountainID))
        #expect(key != FontEditDraft.key(origin: origin, userID: creatorID, fontID: visitorID))
        #expect(key != FontEditDraft.key(origin: URL(string: "https://other.invalid")!, userID: creatorID, fontID: fountainID))
    }
}

extension StubbedNetwork {
    @MainActor struct FontEditing {
        private func setup(role: UserRole = .user, grantStatus: Int = 200,
                           grant: String = #"{"grant":{"capabilities":[],"blockedBy":[]}}"#) throws -> (APIClient, FontEditModel, UserDefaults) {
            let api = StubProtocol.client()
            api.credentials.set("editor-token")
            StubProtocol.sent = []
            StubProtocol.responses = [
                "GET /auth/me": (200, """
                {"id":"\(visitorID)","name":"Test","username":"test","role":"\(role.rawValue)"}
                """),
                "GET /fonts/\(fountainID)": (200, fontJSON),
                "GET /gamification/me": (grantStatus, grant),
                "PUT /fonts/\(fountainID)": (200, fontJSON.replacingOccurrences(of: "Original", with: "Edited")),
            ]
            let defaults = UserDefaults(suiteName: "FontEditing.\(UUID())")!
            return (api, FontEditModel(font: try font(), userID: visitorID, api: api, defaults: defaults), defaults)
        }

        @Test func regularEditorSavesAndClearsDraftWithOptOut204() async throws {
            let (_, model, defaults) = try setup(grantStatus: 204, grant: "")
            await model.prepare()
            #expect(model.ready && model.permissions.canEdit && !model.permissions.canRelocate)
            model.fields.name = "Edited"
            let result = await model.save()
            #expect(result?.name == "Edited")
            let sent = try #require(StubProtocol.sent.first { $0.method == "PUT" })
            let body = try #require(sent.body)
            let payload = try JSONDecoder().decode(NewFont.self, from: body)
            #expect(payload.name == "Edited" && payload.image == "/uploads/cover.jpg")
            #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("draft.edit.") }.isEmpty)
        }

        @Test func revokedRelocationKeepsDraftAndDoesNotWrite() async throws {
            let (_, model, _) = try setup(grant: #"{"grant":{"capabilities":["relocateAnyFont"],"blockedBy":[]}}"#)
            await model.prepare()
            model.fields.latitude = 41.85
            StubProtocol.responses["GET /gamification/me"] = (200, #"{"grant":{"capabilities":[],"blockedBy":["recentlyVoided"]}}"#)
            #expect(await model.save() == nil)
            #expect(!StubProtocol.sent.contains { $0.method == "PUT" })
            #expect(model.dirty && model.error != nil)
            model.discard()
        }

        @Test func permissionFailureDoesNotInventAGrant() async throws {
            let (_, model, _) = try setup(grantStatus: 503, grant: "{}")
            await model.prepare()
            #expect(model.ready && model.permissions.canEdit && !model.permissions.canRelocate)
        }

        @Test func switchingAccountsPreventsSubmission() async throws {
            let (api, model, _) = try setup()
            await model.prepare()
            model.fields.name = "Edited"
            api.credentials.set("another-account")
            #expect(await model.save() == nil)
            #expect(!StubProtocol.sent.contains { $0.method == "PUT" })
            model.discard()
        }

        @Test func serverRejectionAndNetworkFailurePreserveDraft() async throws {
            for status in [403, -1] {
                let (_, model, _) = try setup(role: .admin)
                await model.prepare()
                model.fields.name = "Edited"
                StubProtocol.responses["PUT /fonts/\(fountainID)"] = (status, #"{"code":"user.postingRestricted"}"#)
                #expect(await model.save() == nil)
                #expect(model.dirty && model.error != nil)
                model.discard()
            }
        }
    }
}
