import AppKit
import XCTest
@testable import VXLib

final class TranscriptionPasteboardTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var transcriptionPasteboard: TranscriptionPasteboard!

    override func setUp() {
        super.setUp()
        // Exercise the real macOS pasteboard service without touching the user's clipboard.
        pasteboard = NSPasteboard.withUniqueName()
        transcriptionPasteboard = TranscriptionPasteboard(pasteboard: pasteboard)
    }

    override func tearDown() {
        transcriptionPasteboard = nil
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    func testRestoresAllRepresentationsAndItemOrder() throws {
        let richText = NSPasteboardItem()
        richText.setString("formatted text", forType: .string)
        richText.setData(Data(#"{\rtf1\ansi formatted \b text}"#.utf8), forType: .rtf)
        richText.setData(Data(), forType: NSPasteboard.PasteboardType("vx.test.empty-data"))

        let image = NSPasteboardItem()
        image.setData(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!, forType: .png)

        let firstFile = NSPasteboardItem()
        firstFile.setString("file:///tmp/first.txt", forType: .fileURL)
        let secondFile = NSPasteboardItem()
        secondFile.setString("file:///tmp/second.txt", forType: .fileURL)

        XCTAssertTrue(pasteboard.writeObjects([richText, image, firstFile, secondFile]))
        let original = contents()
        let restore = try transcriptionPasteboard.prepare("dictated text")
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")

        restore()

        XCTAssertEqual(contents(), original)
    }

    func testRestoresAnEmptyClipboard() throws {
        let restore = try transcriptionPasteboard.prepare("dictated text")

        restore()

        XCTAssertTrue((pasteboard.pasteboardItems ?? []).isEmpty)
    }

    func testDoesNotOverwriteANewCopy() throws {
        pasteboard.setString("original", forType: .string)
        let restore = try transcriptionPasteboard.prepare("dictated text")
        copy("new copy")
        let copiedChangeCount = pasteboard.changeCount

        restore()

        XCTAssertEqual(pasteboard.string(forType: .string), "new copy")
        XCTAssertEqual(pasteboard.changeCount, copiedChangeCount)
    }

    func testDoesNotOverwriteANewCopyOfTheSameText() throws {
        pasteboard.setString("original", forType: .string)
        let restore = try transcriptionPasteboard.prepare("dictated text")
        copy("dictated text")
        let copiedChangeCount = pasteboard.changeCount

        restore()

        XCTAssertEqual(pasteboard.string(forType: .string), "dictated text")
        XCTAssertEqual(pasteboard.changeCount, copiedChangeCount)
    }

    func testDoesNotUndoAnExternalClear() throws {
        pasteboard.setString("original", forType: .string)
        let restore = try transcriptionPasteboard.prepare("dictated text")
        let clearedChangeCount = pasteboard.clearContents()

        restore()

        XCTAssertTrue((pasteboard.pasteboardItems ?? []).isEmpty)
        XCTAssertEqual(pasteboard.changeCount, clearedChangeCount)
    }

    func testUnreadableRepresentationLeavesTheClipboardUnchanged() {
        let unavailableType = NSPasteboard.PasteboardType("vx.test.unavailable")
        pasteboard.declareTypes([.string, unavailableType], owner: nil)
        XCTAssertTrue(pasteboard.setString("original", forType: .string))
        let originalChangeCount = pasteboard.changeCount

        XCTAssertThrowsError(try transcriptionPasteboard.prepare("dictated text")) { error in
            guard case TextInsertionError.clipboardUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertTrue(pasteboard.types?.contains(unavailableType) == true)
        XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
    }

    func testOverlappingInsertionsKeepTheLatestTextUntilRestoringTheOriginal() throws {
        pasteboard.setString("original", forType: .string)
        let restoreFirst = try transcriptionPasteboard.prepare("first dictation")
        let restoreSecond = try transcriptionPasteboard.prepare("second dictation")

        restoreFirst()
        XCTAssertEqual(pasteboard.string(forType: .string), "second dictation")

        restoreSecond()
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testOlderCallbackCannotUndoANewerRestore() throws {
        pasteboard.setString("original", forType: .string)
        let restoreFirst = try transcriptionPasteboard.prepare("first dictation")
        let restoreSecond = try transcriptionPasteboard.prepare("second dictation")

        restoreSecond()
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        let restoredChangeCount = pasteboard.changeCount
        restoreFirst()
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.changeCount, restoredChangeCount)
    }

    func testCopyBetweenInsertionsBecomesTheNewOriginal() throws {
        pasteboard.setString("original", forType: .string)
        let restoreFirst = try transcriptionPasteboard.prepare("first dictation")
        copy("new copy")
        let restoreSecond = try transcriptionPasteboard.prepare("second dictation")

        restoreFirst()
        XCTAssertEqual(pasteboard.string(forType: .string), "second dictation")
        restoreSecond()
        XCTAssertEqual(pasteboard.string(forType: .string), "new copy")
    }

    func testCompletedRestoreCannotAffectALaterInsertion() throws {
        pasteboard.setString("original", forType: .string)
        let restoreFirst = try transcriptionPasteboard.prepare("first dictation")
        restoreFirst()
        copy("new original")
        let restoreSecond = try transcriptionPasteboard.prepare("second dictation")

        restoreFirst()
        XCTAssertEqual(pasteboard.string(forType: .string), "second dictation")
        restoreSecond()
        XCTAssertEqual(pasteboard.string(forType: .string), "new original")
    }

    private func copy(_ text: String) {
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
    }

    private func contents() -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                representations[type] = item.data(forType: type)
            }
            return representations
        }
    }
}
