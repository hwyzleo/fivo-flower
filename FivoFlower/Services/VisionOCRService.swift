import Foundation
import Vision
import ImageIO
import CoreGraphics

/// 设备端 Vision OCR，识别中文与英文，按阅读顺序拼接。
final class VisionOCRService: OCRServicing {
    func recognizeText(in imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw OCRError.invalidImage
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw OCRError.failed(error.localizedDescription)
            }
            guard let observations = request.results, !observations.isEmpty else {
                throw OCRError.noTextFound
            }
            let sorted = observations.sorted { lhs, rhs in
                let lhsBox = lhs.boundingBox
                let rhsBox = rhs.boundingBox
                if abs(lhsBox.midY - rhsBox.midY) > 0.02 {
                    return lhsBox.midY > rhsBox.midY
                }
                return lhsBox.minX < rhsBox.minX
            }
            let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OCRError.noTextFound
            }
            return text
        }.value
    }
}

/// OCR 不可用时的确定性替身（仅在测试/预览注入）。
struct StubOCRService: OCRServicing {
    var text: String
    var error: Error?

    init(text: String = "淘宝订单\n实付 ¥128.00\n2024-05-01\n店铺：花艺工作室\n订单号：123456789012", error: Error? = nil) {
        self.text = text
        self.error = error
    }

    func recognizeText(in imageData: Data) async throws -> String {
        if let error { throw error }
        return text
    }
}
