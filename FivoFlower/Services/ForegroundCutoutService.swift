import Foundation
import UIKit
import Vision
import ImageIO
import CoreImage

enum CutoutError: LocalizedError {
    case invalidImage
    case noSubject
    case requiresDevice
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取图片。"
        case .noSubject:
            return "没有识别到明显主体，请换一张主体清晰、背景简单的照片。"
        case .requiresDevice:
            return "自动抠图依赖设备端主体分割，模拟器不支持，请在真机 iPhone 上使用。"
        case .failed(let detail):
            return "抠图失败：\(detail)"
        }
    }
}

protocol ForegroundCutoutProviding {
    func cutout(from image: UIImage) async throws -> UIImage
}

/// 使用设备端 Vision 前景主体分割生成透明背景图。
/// 不联网，图片不会离开设备。
/// 模拟器缺少推理上下文，无法运行该请求，会返回明确提示。
struct ForegroundCutoutService: ForegroundCutoutProviding {
    static var isSupported: Bool {
#if targetEnvironment(simulator)
        return false
#else
        return true
#endif
    }

    func cutout(from image: UIImage) async throws -> UIImage {
        guard Self.isSupported else {
            throw CutoutError.requiresDevice
        }
        return try await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else {
                throw CutoutError.invalidImage
            }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.fivoCGImageOrientation,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                throw CutoutError.failed(error.localizedDescription)
            }
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else {
                throw CutoutError.noSubject
            }
            let pixelBuffer: CVPixelBuffer
            do {
                pixelBuffer = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances,
                    from: handler,
                    croppedToInstancesExtent: true
                )
            } catch {
                throw CutoutError.failed(error.localizedDescription)
            }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let output = context.createCGImage(ciImage, from: ciImage.extent) else {
                throw CutoutError.failed("无法生成输出图片")
            }
            return UIImage(cgImage: output, scale: image.scale, orientation: .up)
        }.value
    }
}

private extension UIImage {
    var fivoCGImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
