import Cocoa
import Translation
import NaturalLanguage

// MARK: - Translation Error
/// 翻译流程自定义错误（注意：系统 Translation 框架自带 TranslationError，故加 WS 前缀避免冲突）
enum WSTranslationError: LocalizedError {
    /// 原图为空 / 没有可翻译内容
    case emptyText
    /// 原文已是简体中文，无需翻译
    case alreadySimplifiedChinese
    /// 无法识别原文语言
    case undetectableLanguage
    /// 在线翻译失败（携带原因）
    case network(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "没有可翻译的文字内容"
        case .alreadySimplifiedChinese:
            return "检测到原文已是简体中文，无需翻译 ✨"
        case .undetectableLanguage:
            return "未能识别原文语言，无法翻译"
        case .network(let reason):
            return "在线翻译失败：\(reason)"
        }
    }
}

// MARK: - Online Free Translator (双接口兜底)
/// 在线兜底翻译（无需任何 API Key / 账号）：
/// 1) MyMemory 公开接口（需显式语言对，稳定性好）
/// 2) Google 免费接口 client=gtx（隐式自动测源语言，作为第二道兜底，偶有反滥用拦截）
enum OnlineTranslator {
    /// MyMemory 单次请求最大字符数（接口限制单请求 500 字节，中文占 3 字节，取小值稳妥）
    private static let myMemoryChunkMax = 150
    /// Google 接口单次请求最大字符数
    private static let googleChunkMax = 600

    static func translate(_ text: String, sourceCode: String, completion: @escaping (Result<String, Error>) -> Void) {
        fetchMyMemoryBatch(text, sourceCode: sourceCode) { result in
            switch result {
            case .success(let translated):
                completion(.success(translated))
            case .failure(let mmError):
                fetchGoogleBatch(text) { gResult in
                    switch gResult {
                    case .success(let translated):
                        completion(.success(translated))
                    case .failure(let gError):
                        let mmDetail = (mmError as? WSTranslationError)?.errorDescription ?? mmError.localizedDescription
                        let gDetail = (gError as? WSTranslationError)?.errorDescription ?? gError.localizedDescription
                        completion(.failure(WSTranslationError.network(
                            "MyMemory：\(mmDetail)；Google 兜底：\(gDetail)"
                        )))
                    }
                }
            }
        }
    }

    /// 由检测到的语言生成本地源语言代码（供 MyMemory 语言对使用）
    static func sourceCode(for language: Locale.Language) -> String? {
        guard let code = language.languageCode?.identifier(.alpha2) else { return nil }
        if code == "zh" {
            if language.isEquivalent(to: Locale.Language(identifier: "zh-Hant")) { return "zh-TW" }
            return "zh-CN"
        }
        return code
    }

    // MARK: - MyMemory (source lang must be explicit)

    private static func fetchMyMemoryBatch(_ text: String, sourceCode: String, completion: @escaping (Result<String, Error>) -> Void) {
        let chunks = split(text, maxLength: myMemoryChunkMax)
        fetchSequential(chunks, index: 0, results: [], fetcher: { chunk, inner in
            fetchMyMemoryChunk(chunk: chunk, sourceCode: sourceCode, completion: inner)
        }, completion: completion)
    }

    private static func fetchMyMemoryChunk(chunk: String, sourceCode: String, completion: @escaping (Result<String, Error>) -> Void) {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: chunk),
            URLQueryItem(name: "langpair", value: "\(sourceCode)|zh-CN")
        ]
        guard let url = components?.url else {
            DispatchQueue.main.async { completion(.failure(WSTranslationError.network("构造翻译请求失败"))) }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(WSTranslationError.network(error.localizedDescription))) }
                return
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data, options: []),
                  let dict = root as? [String: Any] else {
                DispatchQueue.main.async { completion(.failure(WSTranslationError.network("翻译结果解析失败"))) }
                return
            }

            if let responseStatus = dict["responseStatus"] as? Int, responseStatus == 200,
               let responseData = dict["responseData"] as? [String: Any],
               let translated = responseData["translatedText"] as? String,
               !translated.isEmpty {
                DispatchQueue.main.async { completion(.success(translated)) }
                return
            }

            let detail = (dict["responseDetails"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "接口拒绝或配额用尽"
            DispatchQueue.main.async { completion(.failure(WSTranslationError.network(detail))) }
        }.resume()
    }

    // MARK: - Google (auto source detect, secondary fallback)

    private static func fetchGoogleBatch(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        let chunks = split(text, maxLength: googleChunkMax)
        fetchSequential(chunks, index: 0, results: [], fetcher: { chunk, inner in
            fetchGoogleChunk(chunk: chunk, completion: inner)
        }, completion: completion)
    }

    private static func fetchGoogleChunk(chunk: String, completion: @escaping (Result<String, Error>) -> Void) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "zh-CN"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: chunk)
        ]
        guard let url = components?.url else {
            DispatchQueue.main.async { completion(.failure(WSTranslationError.network("构造翻译请求失败"))) }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(WSTranslationError.network(error.localizedDescription))) }
                return
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data, options: []),
                  let array = root as? [Any],
                  let segments = array.first as? [[Any]] else {
                DispatchQueue.main.async {
                    completion(.failure(WSTranslationError.network("被接口拒绝（反滥用拦截）或返回异常")))
                }
                return
            }

            let parts: [String] = segments.compactMap { $0.first as? String }
            let joined = parts.joined()
            if joined.isEmpty {
                DispatchQueue.main.async { completion(.failure(WSTranslationError.network("翻译结果为空"))) }
                return
            }
            DispatchQueue.main.async { completion(.success(joined)) }
        }.resume()
    }

    // MARK: - Shared Split / Sequential

    /// 将长文本按段落拆分为若干不超长的请求分段
    static func split(_ text: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.count > maxLength {
                var rest = Substring(line)
                while rest.count > maxLength {
                    let head = rest.prefix(maxLength)
                    chunks.append(String(head))
                    rest = rest.dropFirst(maxLength)
                }
                chunks.append(String(rest))
            } else if line.isEmpty {
                continue
            } else if let last = chunks.last, last.count + line.count + 1 <= maxLength {
                chunks[chunks.count - 1] += "\n" + line
            } else {
                chunks.append(line)
            }
        }
        return chunks
    }

    private static func fetchSequential(
        _ chunks: [String],
        index: Int,
        results: [String],
        fetcher: @escaping (String, @escaping (Result<String, Error>) -> Void) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard chunks.indices.contains(index) else {
            DispatchQueue.main.async { completion(.success(results.joined(separator: "\n"))) }
            return
        }
        fetcher(chunks[index]) { result in
            switch result {
            case .success(let value):
                fetchSequential(chunks, index: index + 1, results: results + [value], fetcher: fetcher, completion: completion)
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

// MARK: - Translation Service (Hybrid Engine)
/// 截图翻译服务：固定译为简体中文。
/// - 任何版本：先用本机 NLLanguageRecognizer 检测源语言；原文已是简体中文则直接提示无需翻译
/// - macOS 26.4+：优先使用系统离线翻译引擎（TranslationSession，需系统已安装对应语言包）
/// - 其余情况 / 离线不可用：自动回退在线免费接口（MyMemory → Google）
final class TranslationService {
    static let shared = TranslationService()

    /// 翻译目标语言：简体中文
    static let targetLanguage = Locale.Language(identifier: "zh-Hans")

    /// 最近一次翻译实际使用的引擎（"离线" / "在线"），供结果窗口展示
    private(set) var lastEngineName: String = "在线"

    typealias Completion = (Result<String, Error>) -> Void

    /// 翻译文本为简体中文。completion 保证在主线程回调。
    func translate(_ text: String, completion: @escaping Completion) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(WSTranslationError.emptyText))
            return
        }

        // 1. 本机离线检测原文语言
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else {
            completion(.failure(WSTranslationError.undetectableLanguage))
            return
        }
        let source = Locale.Language(identifier: dominant.rawValue)

        // 2. 原文已是简体中文，无需翻译（繁体除外，繁→简有意义）
        if source.isEquivalent(to: Self.targetLanguage) {
            completion(.failure(WSTranslationError.alreadySimplifiedChinese))
            return
        }

        // 3. 按系统版本选择引擎
        if #available(macOS 26.4, *) {
            translateOffline(trimmed, source: source) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let translated):
                    completion(.success(translated))
                case .failure(let error):
                    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.translateOnline(trimmed, source: source, offlineSkipReason: reason, completion: completion)
                }
            }
        } else {
            translateOnline(trimmed, source: source, offlineSkipReason: nil, completion: completion)
        }
    }

    // MARK: - Offline (macOS 26.4+, system Translation engine)

    @available(macOS 26.4, *)
    private func translateOffline(_ text: String, source: Locale.Language, completion: @escaping Completion) {
        let availability = LanguageAvailability()
        Task {
            // 检查「源语言 -> 简体中文」离线翻译包是否已安装；未安装直接回退在线，避免弹窗打断
            let status = await availability.status(from: source, to: Self.targetLanguage)
            guard status == .installed else {
                let reason = status == .unsupported ? "系统不支持该语言的离线翻译" : "系统尚未下载该语言的离线翻译包"
                self.translateOnline(text, source: source, offlineSkipReason: reason, completion: completion)
                return
            }

            do {
                let session = TranslationSession(installedSource: source, target: Self.targetLanguage)
                let response = try await session.translate(text)
                self.lastEngineName = "离线"
                DispatchQueue.main.async { completion(.success(response.targetText)) }
            } catch {
                self.translateOnline(text, source: source, offlineSkipReason: "离线翻译出错（\(error.localizedDescription)）", completion: completion)
            }
        }
    }

    // MARK: - Online Fallback

    /// 使用在线接口翻译；completion 保证主线程。若带 offlineSkipReason，失败时会把两个原因合并上报。
    private func translateOnline(_ text: String, source: Locale.Language, offlineSkipReason: String?, completion: @escaping Completion) {
        guard let sourceCode = OnlineTranslator.sourceCode(for: source) else {
            let detail = offlineSkipReason ?? "该语言暂不支持"
            completion(.failure(WSTranslationError.network("\(detail)，且其语言代码无法用于在线翻译")))
            return
        }

        OnlineTranslator.translate(text, sourceCode: sourceCode) { [weak self] result in
            switch result {
            case .success(let translated):
                self?.lastEngineName = "在线"
                completion(.success(translated))
            case .failure(let error):
                let detail = (error as? WSTranslationError)?.errorDescription ?? error.localizedDescription
                if let reason = offlineSkipReason {
                    completion(.failure(WSTranslationError.network("\(reason)，\n且\(detail)")))
                } else {
                    completion(.failure(WSTranslationError.network(detail)))
                }
            }
        }
    }
}
