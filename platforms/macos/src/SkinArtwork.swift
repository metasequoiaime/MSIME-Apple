import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// Desktop artwork is a bounded, metadata-free 3:1 header, leaving candidates readable below it.
enum MacSkinArtwork {
  static let maximumBytes = 10 * 1024 * 1024
  static func communityPhoto(_ data: Data) throws -> Data {
    let normalized = try normalize(data)
    guard let source = CGImageSourceCreateWithData(normalized as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw ServiceFailure(message: "无法处理插画。")
    }
    for quality in [0.85, 0.65, 0.4] {
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { break }
      CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
      if CGImageDestinationFinalize(destination), output.length <= 512_000 { return output as Data }
    }
    throw ServiceFailure(message: "插画超过皮肤分享的大小限制。")
  }
  static func normalize(_ data: Data) throws -> Data {
    guard data.count <= maximumBytes,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let type = CGImageSourceGetType(source) as String?,
          [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 32_000_000,
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
          ] as CFDictionary),
          let context = CGContext(data: nil, width: 720, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw ServiceFailure(message: "请选择不超过 10 MB、3200 万像素的 PNG 或 JPEG 图片。")
    }
    let scale = max(720 / CGFloat(image.width), 240 / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: (720 - size.width) / 2, y: (240 - size.height) / 2, width: size.width, height: size.height))
    let output = NSMutableData()
    guard let rendered = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
      throw ServiceFailure(message: "无法处理这张图片。")
    }
    CGImageDestinationAddImage(destination, rendered, nil)
    guard CGImageDestinationFinalize(destination) else { throw ServiceFailure(message: "无法保存图片。") }
    return output as Data
  }
}
