import SwiftUI
import UIKit

/// "My routes": every imported GPX, managed in place. The eye shows or hides its line, the
/// dot picks its colour, and tapping the row opens it (fountains along it) and frames it.
/// Rename and delete are in the swipe and the context menu; deleting removes it from every
/// device with the same iCloud.
struct RoutesSheet: View {
    let library: RouteLibrary
    let onImport: () -> Void
    let onShow: (RouteModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedRoute?
    @State private var newName = ""
    @State private var deleting: SavedRoute?

    var body: some View {
        NavigationStack {
            Group {
                if library.routes.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.t("ios.routes.title"), systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    } description: {
                        Text(L10n.t("ios.routes.empty"))
                    } actions: {
                        Button(L10n.t("ios.routes.import")) { dismiss(); onImport() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(library.routes) { saved in row(saved) }
                        } footer: {
                            Text(L10n.t(library.syncsWithICloud ? "ios.routes.icloud" : "ios.routes.local"))
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("ios.routes.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("ios.routes.import"), systemImage: "plus") { dismiss(); onImport() }
                }
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .alert(L10n.t("ios.routes.rename"), isPresented: Binding(get: { renaming != nil },
                                                                     set: { if !$0 { renaming = nil } })) {
                TextField("", text: $newName)
                Button(L10n.t("form.save")) {
                    if let renaming { library.rename(renaming, to: newName) }
                }
                Button(L10n.t("form.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L10n.t("ios.routes.deleteTitle", ["name": deleting?.name ?? ""]),
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { saved in
                Button(L10n.t("ios.routes.delete"), role: .destructive) { library.delete(saved) }
                Button(L10n.t("form.cancel"), role: .cancel) {}
            } message: { _ in
                Text(L10n.t("ios.routes.deleteBody"))
            }
        }
    }

    private func row(_ saved: SavedRoute) -> some View {
        let active = library.isActive(saved)
        let hidden = library.isHidden(saved)
        return HStack(spacing: 4) {
            colorMenu(saved) {
                Circle()
                    .fill(Color(hex: UInt32(saved.colorHex)))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                    .opacity(hidden ? 0.35 : 1)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("ios.routes.color"))
            .accessibilityValue(L10n.t("ios.routes.color.\(saved.color.key)"))
            Button {
                let model = library.activate(saved)
                dismiss()
                onShow(model)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.name).foregroundStyle(hidden ? .secondary : .primary)
                    Text(subtitle(saved, active: active))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityHint(L10n.t("ios.routes.open"))
            Button {
                withAnimation { library.setHidden(!hidden, saved) }
            } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .foregroundStyle(hidden ? Color.secondary : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t(hidden ? "ios.routes.show" : "ios.routes.hide"))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .swipeActions(edge: .trailing) {
            Button(L10n.t("ios.routes.delete"), systemImage: "trash", role: .destructive) { deleting = saved }
            Button(L10n.t("ios.routes.rename"), systemImage: "pencil") { startRenaming(saved) }
        }
        .contextMenu {
            Button(L10n.t(hidden ? "ios.routes.show" : "ios.routes.hide"), systemImage: hidden ? "eye" : "eye.slash") {
                library.setHidden(!hidden, saved)
            }
            colorMenu(saved) { Label(L10n.t("ios.routes.color"), systemImage: "paintpalette") }
            Button(L10n.t("ios.routes.rename"), systemImage: "pencil") { startRenaming(saved) }
            Button(L10n.t("ios.routes.delete"), systemImage: "trash", role: .destructive) { deleting = saved }
        }
    }

    /// Six named colours, never a free picker: see `RouteColor`.
    private func colorMenu(_ saved: SavedRoute, @ViewBuilder label: () -> some View) -> some View {
        Menu {
            Picker(L10n.t("ios.routes.color"), selection: Binding(get: { saved.color },
                                                                  set: { library.setColor($0, saved) })) {
                ForEach(RouteColor.allCases) { color in
                    Label {
                        Text(L10n.t("ios.routes.color.\(color.key)"))
                    } icon: {
                        // A menu draws its icons as monochrome templates and ignores
                        // foregroundStyle (all came out grey): a pre-tinted original image.
                        Image(uiImage: UIImage(systemName: "circle.fill")!
                            .withTintColor(UIColor(Color(hex: UInt32(color.rawValue))), renderingMode: .alwaysOriginal))
                    }
                    .tag(color)
                }
            }
        } label: { label() }
    }

    private func subtitle(_ saved: SavedRoute, active: Bool) -> String {
        var parts = ["\(RouteModel.km(saved.lengthKm)) km", saved.importedAt.formatted(date: .abbreviated, time: .omitted)]
        if library.isHidden(saved) { parts.append(L10n.t("ios.routes.hiddenTag")) }
        else if active { parts.append(L10n.t("ios.routes.openTag")) }
        return parts.joined(separator: " · ")
    }

    private func startRenaming(_ saved: SavedRoute) {
        newName = saved.name
        renaming = saved
    }
}

/// The open route, said on the map: a line nobody explains is a surprise (field test,
/// 03/10/2026). With several lines drawn, the chip names the one whose fountains are
/// loaded. Its name opens them; the eye hides that line (and closes it); the cross only
/// closes it — the line stays, as every other visible route does.
struct RouteChip: View {
    let route: RouteModel
    let color: RouteColor
    let onOpen: () -> Void
    let onHide: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
                        .foregroundStyle(Color(hex: UInt32(color.rawValue)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(route.name).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text("\(RouteModel.km(route.lengthKm)) km").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 14)
                .frame(minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("ios.routes.open"))
            .accessibilityValue(route.name)
            Button(action: onHide) {
                Image(systemName: "eye.slash")
                    .frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("ios.routes.hide"))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("ios.routes.close"))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }
}
