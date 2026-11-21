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

    /// Everything needed to store a newly imported photo.
    struct Prepared: Sendable {
        let full: Data
        let thumbnail: Data
        let cropCenterX: Double
        let cropCenterY: Double
        let cropSide: Double
        let takenOn: Date?
    }

    /// Downsizes an imported photo, finds the cat for the avatar crop, and reads
    /// the capture date. Call off the main thread.
    static func prepare(_ data: Data) -> Prepared? {
        guard let full = downsample(data, maxPixels: fullMaxPixels),
              let fullData = jpegData(full)
        else { return nil }
        let crop = CatDetector.avatarCrop(for: full)
            ?? CatDetector.Crop(centerX: 0.5, centerY: 0.5, side: 1)
        guard let thumbnail = makeAvatar(from: full, centerX: crop.centerX, centerY: crop.centerY, side: crop.side)
        else { return nil }
        return Prepared(full: fullData, thumbnail: thumbnail,
                        cropCenterX: crop.centerX, cropCenterY: crop.centerY, cropSide: crop.side,
                        takenOn: captureDate(data))
    }

    /// The EXIF "date taken", if the photo has one.
    static func captureDate(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
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

    func cached(_ key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
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

    /// A new photo from prepared import data. Insert it into a context before relating it to a cat.
    static func make(from prepared: ImageTools.Prepared) -> CatPhoto {
        let photo = CatPhoto(imageData: prepared.full, thumbnailData: prepared.thumbnail)
        photo.cropCenterX = prepared.cropCenterX
        photo.cropCenterY = prepared.cropCenterY
        photo.cropSide = prepared.cropSide
        photo.takenOn = prepared.takenOn
        return photo
    }
}

extension Cat {
    /// Photos, most recently taken (or added) first.
    var photosNewestFirst: [CatPhoto] {
        (photos ?? []).sorted { ($0.takenOn ?? $0.addedAt) > ($1.takenOn ?? $1.addedAt) }
    }
}
