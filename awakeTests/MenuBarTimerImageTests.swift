import AppKit
import XCTest
@testable import awake

final class MenuBarTimerImageTests: XCTestCase {
    @MainActor
    func testNonTemplateTimerStatusImageAdaptsTextToAppearance() throws {
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        icon.isTemplate = false

        let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAqua = try XCTUnwrap(NSAppearance(named: .darkAqua))

        let lightBarImage = AwakeAppDelegate.timerStatusImage(icon: icon, text: "88:88", appearance: aqua)
        let darkBarImage = AwakeAppDelegate.timerStatusImage(icon: icon, text: "88:88", appearance: darkAqua)

        XCTAssertFalse(lightBarImage.isTemplate)
        XCTAssertFalse(darkBarImage.isTemplate)

        let lightTextLuminance = try averageTextLuminance(in: lightBarImage, iconWidth: icon.size.width)
        let darkTextLuminance = try averageTextLuminance(in: darkBarImage, iconWidth: icon.size.width)

        XCTAssertLessThan(lightTextLuminance, 0.3)
        XCTAssertGreaterThan(darkTextLuminance, 0.7)
    }

    private func averageTextLuminance(in image: NSImage, iconWidth: CGFloat) throws -> CGFloat {
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

        let textMaxX = max(1, width - Int(ceil(iconWidth)) - 4)
        var totalLuminance: CGFloat = 0
        var pixelCount = 0

        for y in 0..<height {
            for x in 0..<textMaxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.5 else { continue }
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                totalLuminance += luminance
                pixelCount += 1
            }
        }

        XCTAssertGreaterThan(pixelCount, 0)
        return totalLuminance / CGFloat(pixelCount)
    }
}
