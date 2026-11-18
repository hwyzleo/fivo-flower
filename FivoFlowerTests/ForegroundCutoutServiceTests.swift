import XCTest
import UIKit
@testable import FivoFlower

final class ForegroundCutoutServiceTests: XCTestCase {
    func testCutoutReportsEnvironmentCapability() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            UIColor.systemPink.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 60, y: 40, width: 180, height: 220))
        }

        if ForegroundCutoutService.isSupported {
            do {
                let output = try await ForegroundCutoutService().cutout(from: image)
                XCTAssertGreaterThan(output.size.width, 0)
            } catch {
                guard case CutoutError.noSubject = error else {
                    return XCTFail("真机抠图出现非预期错误：\(error)")
                }
            }
        } else {
            do {
                _ = try await ForegroundCutoutService().cutout(from: image)
                XCTFail("模拟器应返回 requiresDevice")
            } catch {
                guard case CutoutError.requiresDevice = error else {
                    return XCTFail("非预期错误：\(error)")
                }
            }
        }
    }
}
