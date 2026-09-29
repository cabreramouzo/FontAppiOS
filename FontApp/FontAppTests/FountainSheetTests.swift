import Foundation
import Testing
import UIKit
@testable import FontApp

/// The fountain's sheet over the map opens as the short card and stays there until the
/// person lifts it: choosing another pin, or "view on map", brings it back down.
@MainActor
struct FountainSheetTests {
    @Test func anotherFountainLowersTheSheetButTheSameOneOrClosingDoesNot() {
        let a = UUID(), b = UUID()
        #expect(FountainSheetPolicy.lowersOnSelection(from: nil, to: a))
        #expect(FountainSheetPolicy.lowersOnSelection(from: a, to: b))
        #expect(!FountainSheetPolicy.lowersOnSelection(from: a, to: a))
        #expect(!FountainSheetPolicy.lowersOnSelection(from: a, to: nil))
    }

    /// A sheet like SwiftUI's: the short card and the whole page, lifted to the page.
    private func liftedSheet() -> (UISheetPresentationController, UIViewController) {
        let content = UIViewController()
        let sheet = UISheetPresentationController(presentedViewController: content, presenting: UIViewController())
        let short = UISheetPresentationController.Detent.custom(identifier: .init("short")) { _ in 420 }
        sheet.detents = [short, .large()]
        sheet.selectedDetentIdentifier = .large
        return (sheet, content)
    }

    @Test func lowerToSmallestGoesBackToTheShortCard() {
        let (sheet, _) = liftedSheet()
        let handle = SheetHandle()
        handle.controller = sheet
        handle.lowerToSmallest()
        #expect(sheet.selectedDetentIdentifier == .init("short"))
    }

    @Test func lowerToSmallestDoesNothingWithoutASheet() {
        let handle = SheetHandle()
        handle.lowerToSmallest()   // no crash, nothing to lower
        #expect(handle.controller == nil)
    }
}
