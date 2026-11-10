import XCTest
import CoreGraphics
import ImageIO
@testable import StreamDockKit

final class KeyImageEncoderTests: XCTestCase {
    /// Image carrée dont seul le quart en haut à gauche est rouge, le reste noir.
    private func redTopLeft(side: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: side / 2, width: side / 2, height: side / 2))  // origine en bas à gauche
        return ctx.makeImage()!
    }

    private func decode(_ jpeg: [UInt8]) -> CGImage {
        let source = CGImageSourceCreateWithData(Data(jpeg) as CFData, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    /// Composante rouge au point donné, repère image (origine en haut à gauche).
    private func red(_ image: CGImage, x: Int, y: Int) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return Int(pixel[0])
    }

    func testOutputIsAJPEGOfTheRequestedSize() {
        let jpeg = KeyImageEncoder.jpeg(from: redTopLeft(side: 200), side: 96, quarterTurnsCounterClockwise: 0)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        let image = decode(jpeg)
        XCTAssertEqual(image.width, 96)
        XCTAssertEqual(image.height, 96)
    }

    func testWithoutRotationTheRedQuarterStaysTopLeft() {
        let image = decode(KeyImageEncoder.jpeg(from: redTopLeft(side: 200), side: 96, quarterTurnsCounterClockwise: 0))
        XCTAssertGreaterThan(red(image, x: 20, y: 20), 200)
        XCTAssertLessThan(red(image, x: 76, y: 20), 60)
        XCTAssertLessThan(red(image, x: 20, y: 76), 60)
    }

    func testOneCounterClockwiseQuarterTurnMovesTopLeftToBottomLeft() {
        let image = decode(KeyImageEncoder.jpeg(from: redTopLeft(side: 200), side: 96, quarterTurnsCounterClockwise: 1))
        XCTAssertGreaterThan(red(image, x: 20, y: 76), 200)
        XCTAssertLessThan(red(image, x: 20, y: 20), 60)
        XCTAssertLessThan(red(image, x: 76, y: 76), 60)
    }
}
