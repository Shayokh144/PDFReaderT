import UIKit
import XCTest
@testable import PDFReaderT

final class PDFWordSelectionTests: XCTestCase {

    func testDefineTerm_stripsLeadingAndTrailingPunctuation() {
        XCTAssertEqual(PDFWordSelection.defineTerm(from: "  hello.  "), "hello")
        XCTAssertEqual(PDFWordSelection.defineTerm(from: "\"hello.\""), "hello")
    }

    func testDefineTerm_keepsInternalApostropheAndHyphen() {
        XCTAssertEqual(PDFWordSelection.defineTerm(from: "don't"), "don't")
        XCTAssertEqual(PDFWordSelection.defineTerm(from: "well-known"), "well-known")
    }

    func testDefineTerm_rejectsRangeSelection() {
        XCTAssertNil(PDFWordSelection.defineTerm(from: "hello world"))
    }

    func testDefineTerm_rejectsHyphenNewlineWrap() {
        XCTAssertNil(PDFWordSelection.defineTerm(from: "inter-\nnet"))
    }

    func testDefineTerm_rejectsPunctuationOnly() {
        XCTAssertNil(PDFWordSelection.defineTerm(from: "..."))
    }

    func testDefineTerm_rejectsEmpty() {
        XCTAssertNil(PDFWordSelection.defineTerm(from: "   \n"))
    }

    func testRemovingSystemLookup_dropsLookupMenu() {
        let lookup = UIMenu(
            title: "Look Up",
            identifier: .lookup,
            children: [
                UIAction(title: "Look Up", handler: { _ in })
            ]
        )
        let copy = UIAction(title: "Copy", handler: { _ in })
        let result = PDFSelectionMenu.removingSystemLookup(from: [copy, lookup])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual((result.first as? UIAction)?.title, "Copy")
    }
}
