import InkhashCore
import UIKit
import XCTest
@testable import Inkhash

/// Serif headings, sans text, airy lines. See ADR 0053.
@MainActor
final class EditorTypographyTests: EditorTestCase {
    private var serifFamily: String {
        let body = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        return UIFont(descriptor: body.withDesign(.serif)!, size: 17).familyName
    }

    private func font(at location: Int) -> UIFont {
        view.storage.attribute(.font, at: location, effectiveRange: nil) as! UIFont
    }

    private func paragraphStyle(at location: Int) -> NSParagraphStyle {
        view.storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as! NSParagraphStyle
    }

    func testHeadingsAreSerifAndTextIsNot() {
        open("# Titel\n\nText mit **fett** und *kursiv*\n\n- Punkt")
        let text = view.storage.string as NSString
        XCTAssertEqual(font(at: 0).familyName, serifFamily)
        for word in ["Text", "fett", "kursiv", "Punkt"] {
            XCTAssertNotEqual(font(at: text.range(of: word).location).familyName, serifFamily, word)
        }
    }

    func testTypingInAHeadingKeepsTheSerif() {
        open()
        type("# Titel *schräg*")
        XCTAssertEqual(markdown, "# Titel *schräg*\n")
        XCTAssertEqual(font(at: view.storage.length - 1).familyName, serifFamily)
    }

    func testTextLinesAreAboutOneAndAHalfHigh() {
        open("Text\n\n# Titel")
        for location in [0, view.storage.length - 1] {
            let font = font(at: location)
            let height = font.lineHeight + paragraphStyle(at: location).lineSpacing
            let factor: CGFloat = location == 0 ? 1.5 : 1.2
            XCTAssertEqual(height, font.pointSize * factor, accuracy: 1, "at \(location)")
            XCTAssertEqual(paragraphStyle(at: location).lineHeightMultiple, 0, "at \(location)")
        }
    }

    func testANewTextSizeKeepsTheNote() {
        open("# Titel\n\nText\n\n- [x] Erledigt")
        let before = markdown
        engine.textSizeChanged()
        XCTAssertEqual(markdown, before)
        XCTAssertEqual(font(at: 0).familyName, serifFamily)
    }
}
