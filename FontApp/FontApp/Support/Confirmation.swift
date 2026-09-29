import SwiftUI

extension View {
    /// Asks before something that cannot be undone, hung on the control or row that
    /// asked. Since iOS 26 a confirmation dialog springs from the view it is attached to
    /// (Apple's action sheet guidance): hung on a whole page it floated at the top, and
    /// hung on a page underneath a pushed screen it opened on the wrong screen.
    func confirmsDestructive(_ title: String, isPresented: Binding<Bool>, action label: String,
                             message: String? = nil, perform: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(label, role: .destructive, action: perform)
            Button(L10n.t("form.cancel"), role: .cancel) {}
        } message: {
            if let message { Text(message) }
        }
    }
}
