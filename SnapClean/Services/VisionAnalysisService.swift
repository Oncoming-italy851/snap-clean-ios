import Vision
import UIKit
import CoreImage

struct BlurAnalysisResult: Sendable {
    let assetId: String
    let blurScore: Float      // Higher = more blurry. 0-1 scale
    let isBlurry: Bool
}

struct ExposureAnalysisResult: Sendable {
    let assetId: String
    let meanLuminance: Float  // 0-1 scale
    let isTooDark: Bool
    let isOverexposed: Bool
}

enum BlurSensitivity: String, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var threshold: Float {
        switch self {
        case .low: 0.7
        case .medium: 0.5
        case .high: 0.3
        }
    }
}

actor VisionAnalysisService {

    // MARK: - Blur Detection

    func analyzeBlurriness(image: CGImage, assetId: String, sensitivity: BlurSensitivity = .medium) -> BlurAnalysisResult {
        let ciImage = CIImage(cgImage: image)
        let blurScore = computeLaplacianVariance(ciImage: ciImage)
        // Invert: low variance = blurry = high blur score
        let normalizedScore = max(0, min(1, 1.0 - blurScore))

        return BlurAnalysisResult(
            assetId: assetId,
            blurScore: normalizedScore,
            isBlurry: normalizedScore > sensitivity.threshold
        )
    }

    private func computeLaplacianVariance(ciImage: CIImage) -> Float {
        let context = CIContext()

        // Apply edge detection to measure sharpness
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return 0.5 }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(10.0, forKey: kCIInputIntensityKey)

        guard let outputImage = edgeFilter.outputImage else { return 0.5 }

        // Compute average intensity of edges
        let extent = outputImage.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return 0.5 }

        // Use CIAreaAverage to get mean color
        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        avgFilter.setValue(outputImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let avgOutput = avgFilter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(avgOutput,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        // Average of RGB channels normalized to 0-1
        let avg = (Float(pixel[0]) + Float(pixel[1]) + Float(pixel[2])) / (3.0 * 255.0)
        return avg
    }

    // MARK: - Exposure Analysis

    func analyzeExposure(image: CGImage, assetId: String) -> ExposureAnalysisResult {
        let ciImage = CIImage(cgImage: image)
        let luminance = computeMeanLuminance(ciImage: ciImage)

        return ExposureAnalysisResult(
            assetId: assetId,
            meanLuminance: luminance,
            isTooDark: luminance < 0.12,
            isOverexposed: luminance > 0.88
        )
    }

    private func computeMeanLuminance(ciImage: CIImage) -> Float {
        let context = CIContext()
        let extent = ciImage.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return 0.5 }

        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        avgFilter.setValue(ciImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let avgOutput = avgFilter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(avgOutput,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        // Luminance: 0.299R + 0.587G + 0.114B
        let luminance = (0.299 * Float(pixel[0]) + 0.587 * Float(pixel[1]) + 0.114 * Float(pixel[2])) / 255.0
        return luminance
    }

    // MARK: - Feature Print (for duplicate/similar detection)

    func generateFeaturePrint(image: CGImage) -> VNFeaturePrintObservation? {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()

        do {
            try requestHandler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    func computeDistance(between fp1: VNFeaturePrintObservation, and fp2: VNFeaturePrintObservation) -> Float {
        var distance: Float = 0
        do {
            try fp1.computeDistance(&distance, to: fp2)
        } catch {
            return Float.greatestFiniteMagnitude
        }
        return distance
    }

    // MARK: - Sharpness Scoring

    func computeSharpness(image: CGImage) -> Float {
        let ciImage = CIImage(cgImage: image)
        return computeLaplacianVariance(ciImage: ciImage)
    }
}
