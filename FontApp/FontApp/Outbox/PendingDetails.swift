import SwiftUI
import UIKit

/// A queued contribution as a person can read it, and as it is exported.
///
/// The web's `listPending` / `fieldsOf` (rule R5.7): a contribution can be stuck retrying on
/// flaky signal — correct, it is never dropped — and the person was left blind: trust it
/// is saved, or discard it and lose it. Being able to read it, copy it or keep its photo
/// means a new fountain's data is never trapped where nobody can see it.
nonisolated enum PendingExport {
    /// The legible fields, keyed as the web's export (`type`, `name`, `latitude`…). Never
    /// the photo bytes.
    static func fields(of item: OutboxItem) -> [String: Any] {
        var out: [String: Any] = ["hasPhoto": item.photoFile != nil]
        func put(_ key: String, _ value: Any?) { out[key] = value ?? NSNull() }
        switch item.kind {
        case .font:
            let font = item.newFont
            out["type"] = "new-fountain"
            put("name", font?.name)
            put("latitude", font?.latitude)
            put("longitude", font?.longitude)
            put("description", font?.description)
            put("source", font?.source?.rawValue)
            put("drinkable", font?.drinkable?.rawValue)
            put("waterStatus", item.firstStatus)
        case .comment:
            out["type"] = "review"
            put("name", item.fontName)
            out["fontID"] = item.fontID.uuidString
            put("waterStatus", item.comment?.waterStatus)
            put("rating", item.comment?.rating)
            put("text", item.comment?.body)
        case .review:
            out["type"] = "review"
            put("name", item.fontName)
            out["fontID"] = item.fontID.uuidString
            put("waterStatus", item.review?.waterStatus)
            put("remoteDistanceM", item.review?.remoteDistanceM)
        case .photo:
            out["type"] = "photo"
            put("name", item.fontName)
            out["fontID"] = item.fontID.uuidString
        }
        return out
    }

    /// What "copy all" puts on the clipboard: for a person, not a program — each contribution
    /// with its kind, its fields in the reader's language, when it was queued and how many
    /// attempts it has had, in queue order. Nothing internal (ids, keys, file names).
    static func text(_ items: [OutboxItem]) -> String {
        items.map(block).joined(separator: "\n\n")
    }

    static func block(_ item: OutboxItem) -> String {
        var lines = [L10n.t(kindKey(of: item))]
        lines += rows(of: item, includeID: false).map { "\($0.label): \($0.value)" }
        if let lat = item.newFont?.latitude, let long = item.newFont?.longitude {
            lines.append(String(format: "https://maps.apple.com/?ll=%.5f,%.5f", lat, long))
        }
        if item.photoFile != nil { lines.append("📷 " + L10n.t("offline.itemPhoto")) }
        lines.append([item.queuedAt.formatted(date: .abbreviated, time: .shortened),
                      item.attempts > 0 ? L10n.t("offline.attempts", ["n": item.attempts]) : nil]
            .compactMap { $0 }.joined(separator: " · "))
        return lines.joined(separator: "\n")
    }

    static func kindKey(of item: OutboxItem) -> String {
        switch item.kind {
        case .review, .comment: "offline.itemReview"
        case .photo: "offline.itemPhoto"
        case .font: "offline.itemFont"
        }
    }

    /// The fields that carry something, in a stable order, with their label.
    static func rows(of item: OutboxItem, includeID: Bool = true) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            // The web's labels for type and drinkability end in a colon; here the label is its own line.
            rows.append((L10n.t(key).trimmingCharacters(in: CharacterSet(charactersIn: ": ")), value))
        }
        let fields = fields(of: item)
        add("offline.fName", fields["name"] as? String)
        if let lat = fields["latitude"] as? Double, let long = fields["longitude"] as? Double {
            add("offline.fCoords", String(format: "%.5f, %.5f", lat, long))
        }
        if let status = fields["waterStatus"] as? String {
            add("offline.fStatus", WaterStatus(status).map { L10n.t($0.labelKey) } ?? status)
        }
        add("detail.type", (fields["source"] as? String).flatMap { L10n.lookup("source.\($0)") })
        add("detail.drinkability", (fields["drinkable"] as? String).flatMap { L10n.lookup("drink.\($0)") })
        if let rating = fields["rating"] as? Int { add("offline.fRating", String(rating)) }
        add("offline.fText", (fields["text"] as? String) ?? (fields["description"] as? String))
        if includeID { add("offline.fFont", fields["fontID"] as? String) }
        return rows
    }

    /// Oldest first, as they will be sent.
    static func inQueueOrder(_ items: [OutboxItem]) -> [OutboxItem] {
        items.sorted { $0.queuedAt < $1.queuedAt }
    }
}

/// See — and copy — what is waiting on this phone.
struct PendingDetailsSheet: View {
    @Environment(Outbox.self) private var outbox
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var copyCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.t("offline.detailsIntro")).font(.subheadline).foregroundStyle(.secondary)
                }
                let items = PendingExport.inQueueOrder(outbox.items)
                if items.isEmpty {
                    Section { Text(L10n.t("offline.detailsEmpty")).foregroundStyle(.secondary) }
                }
                ForEach(items) { item in
                    Section { PendingDetailRow(item: item, mine: !outbox.isOthers(item)) }
                }
            }
            .navigationTitle(L10n.t("offline.detailsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(role: .close) { dismiss() } }
                if !outbox.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = PendingExport.text(PendingExport.inQueueOrder(outbox.items))
                            copyCount += 1
                            withAnimation { copied = true }
                        } label: {
                            Label(L10n.t("offline.copyJson"), systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if copied {
                    Text(L10n.t("offline.copied"))
                        .font(.subheadline)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .sensoryFeedback(.success, trigger: copyCount)
            .task(id: copyCount) {
                guard copyCount > 0 else { return }
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { withAnimation { copied = false } }
            }
        }
    }
}

private struct PendingDetailRow: View {
    @Environment(Outbox.self) private var outbox
    let item: OutboxItem
    let mine: Bool

    @State private var saved: PhotoLibrarySaver.Outcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.t(PendingExport.kindKey(of: item))).font(.headline)
                if !mine { tag(L10n.t("offline.itemOther")) }
                if item.needsAuth { tag(L10n.t("offline.itemNeedsAuth")) }
            }
            ForEach(Array(PendingExport.rows(of: item).enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.label).font(.caption).foregroundStyle(.secondary)
                    Text(row.value).textSelection(.enabled)
                }
            }
            if let data = outbox.photoData(of: item), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                // Into the Photos library itself: the share sheet does not offer "Save" reliably.
                Button {
                    Task { saved = await PhotoLibrarySaver.save(data, meta: item.photoMeta) }
                } label: {
                    Label(L10n.t("offline.savePhoto"), systemImage: "square.and.arrow.down")
                }
                .frame(minHeight: 44)
                if let saved {
                    Text(L10n.t(saved.messageKey))
                        .font(.footnote)
                        .foregroundStyle(saved == .saved ? Color.green : Color.red)
                }
            }
            Text([RelativeTime.string(since: item.queuedAt),
                  item.attempts > 0 ? L10n.t("offline.attempts", ["n": item.attempts]) : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.warning)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color.warning.opacity(0.7)))
    }
}
