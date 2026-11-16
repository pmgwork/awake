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

        let idleBitmap = try renderBitmap(for: idle)
        let idleCenter = try XCTUnwrap(idleBitmap.colorAt(x: 9, y: 5))
        XCTAssertLessThan(idleCenter.alphaComponent, 0.1)

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

        let automaticTemplate = try XCTUnwrap(AwakeAppDelegate.statusIcon(
            keepAwakeState: .automatic, isCoolingActive: false, appearance: aqua
        ))
        XCTAssertTrue(automaticTemplate.isTemplate)
        XCTAssertEqual(automaticTemplate.size, idle.size)

        let automaticBitmap = try renderBitmap(for: automaticTemplate)
        let automaticCoffee = try XCTUnwrap(automaticBitmap.colorAt(x: 9, y: 5)?.usingColorSpace(.sRGB))
        let automaticTopCorner = try XCTUnwrap(automaticBitmap.colorAt(x: 19, y: 3)?.usingColorSpace(.sRGB))
        let automaticBottomDot = try XCTUnwrap(automaticBitmap.colorAt(x: 19, y: 14)?.usingColorSpace(.sRGB))
        let cupBody = try XCTUnwrap(automaticBitmap.colorAt(x: 9, y: 12)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(automaticCoffee.alphaComponent, 0.7)
        XCTAssertLessThan(automaticCoffee.redComponent, 0.3)
        XCTAssertLessThan(automaticCoffee.greenComponent, 0.3)
        XCTAssertLessThan(automaticCoffee.blueComponent, 0.3)
        XCTAssertLessThan(automaticTopCorner.alphaComponent, 0.1)
        XCTAssertLessThan(automaticBottomDot.alphaComponent, 0.1)
        XCTAssertLessThan(cupBody.redComponent, 0.3)

        let automaticAndCoolingLight = try XCTUnwrap(AwakeAppDelegate.statusIcon(
            keepAwakeState: .automatic, isCoolingActive: true, appearance: aqua
        ))
        XCTAssertFalse(automaticAndCoolingLight.isTemplate)
        let autoCoolBitmap = try renderBitmap(for: automaticAndCoolingLight)
        let autoCoolCoffee = try XCTUnwrap(autoCoolBitmap.colorAt(x: 9, y: 5)?.usingColorSpace(.sRGB))
        let autoCoolDot = try XCTUnwrap(autoCoolBitmap.colorAt(x: 19, y: 3)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(autoCoolCoffee.alphaComponent, 0.7)
        XCTAssertLessThan(autoCoolCoffee.redComponent, 0.3)
        XCTAssertLessThan(autoCoolCoffee.greenComponent, 0.3)
        XCTAssertGreaterThan(autoCoolDot.blueComponent, 0.7)
        XCTAssertLessThan(autoCoolDot.redComponent, 0.4)
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
