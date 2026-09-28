import Foundation

/// A half-written form kept on the phone, per account and per fountain: it survives the
/// app being killed and closing the form, and goes when it is sent or discarded.
nonisolated enum FormDraft {
    static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults = .standard) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func save<T: Encodable>(_ value: T?, key: String, defaults: UserDefaults = .standard) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func key(_ kind: String, user: UUID?, font: UUID) -> String {
        "draft.\(kind).\(user?.uuidString ?? "anon").\(font.uuidString)"
    }
}
