import Cocoa
import Vision

// MARK: - Shared Offline OCR Engine (Vision)
/// 从截图中识别文字的共享引擎，OCR 结果窗口与截图翻译共用。
enum OCREngine {
    /// 识别语言列表：简繁中文、英、日、韩（与翻译功能支持的语言一致）
    static let recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

    /// NSImage -> CGImage 便捷转换（Vision OCR 只能基于 CGImage 工作）
    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// 后台线程执行离线文字识别，完成后回调（回调仍在后台线程，UI 更新请自行切主线程）。
    /// 成功返回按行拼接的全文，未识别到任何文字时返回空字符串。
    static func recognizeText(in cgImage: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { req, err in
                if let err = err {
                    completion(.failure(err))
                    return
                }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [String] = observations.compactMap { $0.topCandidates(1).first?.string }
                completion(.success(lines.joined(separator: "\n")))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = recognitionLanguages

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
}
