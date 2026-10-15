import XCTest
@testable import InkhashCore

final class PageScaleTests: XCTestCase {
    func testPageFitsNarrowSurfacesAndStopsAtTheLargestZoom() {
        let width = PageGeometry.width
        XCTAssertEqual(PageGeometry.scale(surfaceWidth: 393, pageWidth: width), 393 / width, accuracy: 0.0001, "an iPhone fits the width")
        XCTAssertEqual(PageGeometry.scale(surfaceWidth: 834, pageWidth: width), 834 / width, accuracy: 0.0001, "an 11 inch iPad upright fits the width")
        XCTAssertEqual(PageGeometry.scale(surfaceWidth: 1032, pageWidth: width), 1032 / width, accuracy: 0.0001, "a 13 inch iPad upright still fills the width")
        XCTAssertEqual(PageGeometry.scale(surfaceWidth: 1376, pageWidth: width), PageGeometry.maxScale, "an iPad on its side stops at the largest zoom")
        XCTAssertEqual(PageGeometry.scale(surfaceWidth: 2400, pageWidth: width), PageGeometry.maxScale)
        XCTAssertEqual(PageGeometry.scale(surfaceWidth: 0, pageWidth: width), 0.01, "no surface yet is never zero")
    }
}
