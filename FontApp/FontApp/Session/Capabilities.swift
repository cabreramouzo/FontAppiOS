import Foundation

/// What your level opens, asked once per account and shared, as the web does: a page per
/// fountain opened would otherwise be a request per page for an answer that does not
/// change while you browse. Only for the interface; the server decides.
@MainActor
enum Capabilities {
    private static var cache: (account: UUID, task: Task<Set<String>, Never>)?

    static func of(_ account: UUID?, api: APIClient = .shared) async -> Set<String> {
        guard let account else { return [] }
        if let cache, cache.account == account { return await cache.task.value }
        let task = Task { Set((try? await api.gamification())??.grant?.capabilities ?? []) }
        cache = (account, task)
        return await task.value
    }
}
