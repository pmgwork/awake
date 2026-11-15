import AppKit
import XCTest
@testable import awake

final class MenuBarStatusIconTests: XCTestCase {
    @MainActor
    func testStatusIconUsesFixedSizeAndSemanticIndicators() throws {
        let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAqua = try XCTUnwrap(NSAppearance(named: .darkAqua))

        let idle = try XCTUnwrap(AwakeAppDelegate.statusIcon(
            keepAwakeState: .inactive, isCoolingActive: false, appearance: darkAqua
        ))
        XCTAssertTrue(idle.isTemplate)
        XCTAssertEqual(idle.size, NSSize(width: 21, height: 16.8))

        let manualAndCoolingDark = try XCTUnwrap(AwakeAppDelegate.statusIcon(
            keepAwakeState: .manual, isCoolingActive: true, appearance: darkAqua
        ))
        XCTAssertFalse(manualAndCoolingDark.isTemplate)
        XCTAssertEqual(manualAndCoolingDark.size, idle.size)

        let manualBitmap = try renderBitmap(for: manualAndCoolingDark)
        let manualCoffee = try XCTUnwrap(manualBitmap.colorAt(x: 9, y: 5)?.usingColorSpace(.sRGB))
        let manualTopDot = try XCTUnwrap(manualBitmap.colorAt(x: 19, y: 3)?.usingColorSpace(.sRGB))
        let manualBottomCorner = try XCTUnwrap(manualBitmap.colorAt(x: 19, y: 14)?.usingColorSpace(.sRGB))
        let cupBodyDark = try XCTUnwrap(manualBitmap.colorAt(x: 9, y: 12)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(manualCoffee.redComponent, 0.7)
        XCTAssertLessThan(manualCoffee.blueComponent, 0.4)
        XCTAssertGreaterThan(manualTopDot.blueComponent, 0.7)
        XCTAssertLessThan(manualTopDot.redComponent, 0.4)
        XCTAssertLessThan(manualBottomCorner.alphaComponent, 0.1)
        XCTAssertGreaterThan(cupBodyDark.redComponent, 0.7)

        let automaticLight = try XCTUnwrap(AwakeAppDelegate.statusIcon(
            keepAwakeState: .automatic, isCoolingActive: false, appearance: aqua
        ))
        XCTAssertFalse(automaticLight.isTemplate)
        XCTAssertEqual(automaticLight.size, idle.size)

        let automaticBitmap = try renderBitmap(for: automaticLight)
        let automaticCoffee = try XCTUnwrap(automaticBitmap.colorAt(x: 9, y: 5)?.usingColorSpace(.sRGB))
        let automaticTopCorner = try XCTUnwrap(automaticBitmap.colorAt(x: 19, y: 3)?.usingColorSpace(.sRGB))
        let automaticBottomDot = try XCTUnwrap(automaticBitmap.colorAt(x: 19, y: 14)?.usingColorSpace(.sRGB))
        let cupBodyLight = try XCTUnwrap(automaticBitmap.colorAt(x: 9, y: 12)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(automaticCoffee.greenComponent, 0.6)
        XCTAssertLessThan(automaticCoffee.redComponent, 0.4)
        XCTAssertLessThan(automaticCoffee.blueComponent, 0.5)
        XCTAssertLessThan(automaticTopCorner.alphaComponent, 0.1)
        XCTAssertLessThan(automaticBottomDot.alphaComponent, 0.1)
        XCTAssertLessThan(cupBodyLight.redComponent, 0.3)
    }

    private func renderBitmap(for image: NSImage) throws -> NSBitmapImageRep {
        let width = max(1, Int(ceil(image.size.width)))
        let height = max(1, Int(ceil(image.size.height)))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
