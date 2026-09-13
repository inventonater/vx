import XCTest
@testable import VXLib

final class TextInserterTests: XCTestCase {
    func testEmptyTextIsRejectedBeforePreparingAPaste() {
        XCTAssertThrowsError(try TextInserter.insert(" \n\t", submitBehavior: .returnKey)) { error in
            guard case TextInsertionError.emptyText = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testReturnKeySubmitDoesNotAlterPasteboardPayload() {
        XCTAssertEqual(
            TextInserter.pasteboardPayload(for: "Just testing something out", submitBehavior: .returnKey),
            "Just testing something out"
        )
    }

    func testTerminalSubmitDoesNotPasteTrailingLineBreak() {
        XCTAssertEqual(
            TextInserter.pasteboardPayload(for: "Just testing something out", submitBehavior: .terminalReturnKey),
            "Just testing something out"
        )
    }
}
