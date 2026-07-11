import XCTest
@testable import WudaX

final class BudgetCardViewTests: XCTestCase {
    func testOneTapChecklistConfirmationMarksEveryItemDone() {
        var items = [
            BudgetCardView.GateItem(title: "饮水", reason: "含电解质", required: true),
            BudgetCardView.GateItem(title: "头灯", reason: "日落冗余", required: true),
            BudgetCardView.GateItem(title: "相机", reason: "可选", required: false)
        ]

        items.markAllDone()

        XCTAssertTrue(items.allSatisfy(\.done))
    }
}
