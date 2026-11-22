// Makes the faint, rounded icon shown on the launch screen and in the start-up zoom.
// Run by make-icons.sh:  swift tools/make-launch-icon.swift icon.png output-folder
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: swift make-launch-icon.swift icon.png output-folder")
    exit(1)
}
let input = URL(fileURLWithPath: arguments[1])
let folder = URL(fileURLWithPath: arguments[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("Can't read \(arguments[1])")
    exit(1)
}

let points = 120        // same size as the icon on the Home Screen
let opacity = 0.2       // how faint it is
let corner = 0.224      // iOS rounds icons to about 22.4% of their width

for scale in [1, 2, 3] {
    let pixels = points * scale
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("Couldn't create an image")
        exit(1)
    }
    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let radius = CGFloat(pixels) * corner
    context.interpolationQuality = .high
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.setAlpha(opacity)
    context.draw(image, in: rect)

    let url = folder.appendingPathComponent("launch-icon@\(scale)x.png")
    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("Couldn't write \(url.path)")
        exit(1)
    }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else {
        print("Couldn't write \(url.path)")
        exit(1)
    }
}
