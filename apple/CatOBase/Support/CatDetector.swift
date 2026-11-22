import CoreGraphics
import Foundation
import Vision

/// Finds a cat or dog in a photo with Apple's on-device Vision framework.
enum CatDetector {
    struct Crop: Sendable {
        let centerX: Double
        let centerY: Double
        let side: Double
    }

    /// Normalized box (0…1, origin top-left) around the most likely cat, or any
    /// recognised animal if there's no cat. Nil when nothing is found.
    static func findCat(in image: CGImage) -> CGRect? {
        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let results = request.results, !results.isEmpty else { return nil }

        // Vision's animal recogniser knows cats and dogs; pick the most confident one.
        func score(_ observation: VNRecognizedObjectObservation) -> Float {
            let petConfidence = observation.labels
                .filter { ["cat", "dog"].contains($0.identifier.lowercased()) }
                .map(\.confidence)
                .max() ?? 0
            return petConfidence > 0 ? 1 + petConfidence : observation.confidence
        }

        guard let best = results.max(by: { score($0) < score($1) }) else { return nil }
        let box = best.boundingBox // Vision: normalized, origin bottom-left
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// An avatar crop centred on the detected cat, with some breathing room.
    static func avatarCrop(for image: CGImage) -> Crop? {
        guard let box = findCat(in: image) else { return nil }
        let width = Double(image.width)
        let height = Double(image.height)
        let shorter = min(width, height)
        let boxSide = max(Double(box.width) * width, Double(box.height) * height) * 1.3
        let side = min(max(boxSide / shorter, AvatarCrop.minimumSide), 1)
        return Crop(centerX: Double(box.midX), centerY: Double(box.midY), side: side)
    }
}

/// Shared limits and clamping for avatar crops.
enum AvatarCrop {
    /// Smallest crop: about 6.7× zoom.
    static let minimumSide = 0.15

    static func clampSide(_ side: Double) -> Double {
        min(max(side, minimumSide), 1)
    }

    /// Keeps the crop square inside the image.
    static func clampCenter(x: Double, y: Double, side: Double, width: Double, height: Double) -> (Double, Double) {
        let half = side * min(width, height) / 2
        let minX = half / width
        let minY = half / height
        return (min(max(x, minX), 1 - minX), min(max(y, minY), 1 - minY))
    }
}
