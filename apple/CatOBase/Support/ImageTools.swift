import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Image handling with ImageIO/CoreGraphics only, so the same code runs on
/// iOS and macOS without UIImage/NSImage. Handles HEIC and EXIF orientation.
enum ImageTools {
    static let fullMaxPixels = 2400
    static let avatarPixels = 512

    /// Decodes and downsizes image data, applying EXIF orientation.
    static func downsample(_ data: Data, maxPixels: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Square crop. `centerX`/`centerY` are 0…1 of width/height, `side` is 0…1 of
    /// the shorter edge. The square is kept inside the image.
    static func squareCrop(_ image: CGImage, centerX: Double, centerY: Double, side: Double) -> CGImage? {
        let width = Double(image.width)
        let height = Double(image.height)
        let length = min(width, height) * min(max(side, 0.05), 1)
        let x = min(max(centerX * width - length / 2, 0), width - length)
        let y = min(max(centerY * height - length / 2, 0), height - length)
        return image.cropping(to: CGRect(x: x, y: y, width: length, height: length).integral)
    }

    /// Prepared data for a newly imported photo: the stored full image and the avatar.
    struct Prepared: Sendable {
        let full: Data
        let thumbnail: Data
    }

    /// Downsizes an imported photo and makes a centre-cropped avatar.
    /// Call off the main thread.
    static func prepare(_ data: Data) -> Prepared? {
        guard let full = downsample(data, maxPixels: fullMaxPixels),
              let fullData = jpegData(full),
              let thumbnail = makeAvatar(from: full, centerX: 0.5, centerY: 0.5, side: 1)
        else { return nil }
        return Prepared(full: fullData, thumbnail: thumbnail)
    }

    static func makeAvatar(from image: CGImage, centerX: Double, centerY: Double, side: Double) -> Data? {
        guard let square = squareCrop(image, centerX: centerX, centerY: centerY, side: side) else { return nil }
        let size = avatarPixels
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let scaled = context.makeImage() else { return nil }
        return jpegData(scaled, quality: 0.85)
    }
}

/// Small in-memory cache of decoded images, keyed by photo ID and variant.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, CGImageBox>()

    private init() {
        cache.countLimit = 300
    }

    func image(for key: String, data: Data?, maxPixels: Int) -> CGImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit.image }
        guard let data, let image = ImageTools.downsample(data, maxPixels: maxPixels) else { return nil }
        cache.setObject(CGImageBox(image), forKey: key as NSString)
        return image
    }
}

final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

extension CatPhoto {
    /// Changes whenever the crop changes, so a re-cropped avatar isn't served from cache.
    func cacheKey(_ variant: String) -> String {
        "\(uuid.uuidString)-\(variant)-\(cropCenterX)-\(cropCenterY)-\(cropSide)"
    }

    var thumbnailImage: CGImage? {
        ImageCache.shared.image(for: cacheKey("thumb"), data: thumbnailData, maxPixels: ImageTools.avatarPixels)
    }
}
