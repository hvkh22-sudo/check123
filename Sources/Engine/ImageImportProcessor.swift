import CoreImage
import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageImportLimits: Sendable {
    let maxEncodedBytes: Int
    let maxDimension: Int
    let maxPixelCount: Int
    let targetDimension: Int

    static let passportPhoto = ImageImportLimits(
        maxEncodedBytes: 25 * 1_024 * 1_024,
        maxDimension: 12_000,
        maxPixelCount: 80_000_000,
        targetDimension: 2_400
    )
}

enum ImageImportError: LocalizedError, Equatable, Sendable {
    case unsupportedType
    case encodedDataTooLarge
    case invalidImage
    case dimensionsTooLarge
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "Choose a JPEG, HEIC, or PNG photo."
        case .encodedDataTooLarge:
            return "That file is too large. Choose a photo smaller than 25 MB."
        case .invalidImage:
            return "That photo file is invalid or damaged. Try a different one."
        case .dimensionsTooLarge:
            return "That photo's dimensions are too large. Choose a smaller image."
        case .decodingFailed:
            return "That photo couldn't be decoded safely. Try a different one."
        }
    }
}

/// PhotosPicker transfers the selected asset as a system-managed file. The import closure
/// validates and downsamples it before the temporary URL expires, so the app never needs to
/// materialize an unbounded encoded asset as Data.
struct BoundedImportedImage: Transferable {
    let image: CIImage

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            BoundedImportedImage(
                image: try ImageImportProcessor.prepare(
                    fileURL: received.file,
                    supportedContentTypes: [.image]
                )
            )
        }
    }
}

/// Validates encoded input before pixel decoding, then asks Image I/O for a bounded
/// thumbnail instead of materializing the full-resolution image in memory.
enum ImageImportProcessor {
    private static let allowedTypes: [UTType] = [.jpeg, .heic, .png]

    static func prepare(
        fileURL: URL,
        supportedContentTypes: [UTType],
        limits: ImageImportLimits = .passportPhoto
    ) throws -> CIImage {
        try validate(contentTypes: supportedContentTypes)
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else { throw ImageImportError.invalidImage }
        guard let fileSize = values.fileSize, fileSize > 0 else {
            throw ImageImportError.invalidImage
        }
        guard fileSize <= limits.maxEncodedBytes else {
            throw ImageImportError.encodedDataTooLarge
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            throw ImageImportError.invalidImage
        }
        return try prepare(source: source, limits: limits)
    }

    static func prepare(
        data: Data,
        supportedContentTypes: [UTType],
        limits: ImageImportLimits = .passportPhoto
    ) throws -> CIImage {
        try validate(contentTypes: supportedContentTypes)
        guard !data.isEmpty else { throw ImageImportError.invalidImage }
        guard data.count <= limits.maxEncodedBytes else {
            throw ImageImportError.encodedDataTooLarge
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ImageImportError.invalidImage
        }
        return try prepare(source: source, limits: limits)
    }

    private static func validate(contentTypes: [UTType]) throws {
        guard contentTypes.isEmpty ||
                contentTypes.contains(where: { declared in
                    declared == .image || allowedTypes.contains(where: { declared.conforms(to: $0) })
                }) else {
            throw ImageImportError.unsupportedType
        }
    }

    private static func prepare(
        source: CGImageSource,
        limits: ImageImportLimits
    ) throws -> CIImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard CGImageSourceGetCount(source) > 0,
              let sourceType = CGImageSourceGetType(source),
              let uniformType = UTType(sourceType as String) else {
            throw ImageImportError.invalidImage
        }
        guard allowedTypes.contains(where: { uniformType.conforms(to: $0) }) else {
            throw ImageImportError.unsupportedType
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            CGImageSourceGetPrimaryImageIndex(source),
            sourceOptions
        ) as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ImageImportError.invalidImage
        }

        let width = widthNumber.intValue
        let height = heightNumber.intValue
        guard width > 0, height > 0,
              width <= limits.maxDimension, height <= limits.maxDimension,
              height <= limits.maxPixelCount / width else {
            throw ImageImportError.dimensionsTooLarge
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limits.targetDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            CGImageSourceGetPrimaryImageIndex(source),
            thumbnailOptions as CFDictionary
        ) else {
            throw ImageImportError.decodingFailed
        }

        return CIImage(cgImage: thumbnail)
    }
}
