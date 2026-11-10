import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Met une image au format attendu par le boîtier : carrée, tournée, en JPEG.
public enum KeyImageEncoder {
    public static func jpeg(from image: CGImage, side: Int, quarterTurnsCounterClockwise: Int,
                            quality: Double = 0.9) -> [UInt8] {
        let s = CGFloat(side)
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return [] }
        ctx.interpolationQuality = .high
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        // Dans le repère CoreGraphics (axe y vers le haut), un angle positif tourne dans le sens inverse des aiguilles.
        ctx.translateBy(x: s / 2, y: s / 2)
        ctx.rotate(by: CGFloat(quarterTurnsCounterClockwise) * .pi / 2)
        ctx.translateBy(x: -s / 2, y: -s / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: s, height: s))
        guard let rotated = ctx.makeImage() else { return [] }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return [] }
        CGImageDestinationAddImage(dest, rotated, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return [] }
        return [UInt8](out as Data)
    }
}
