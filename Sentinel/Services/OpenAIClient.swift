import Foundation
import os

struct OpenAIClient {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "OpenAIClient")

    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case http(status: Int, body: String)
        case decoding(String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "OpenAI API key 未配置。请到 设置 → AI 中粘贴 API Key。"
            case .invalidResponse: return "OpenAI 接口返回了非预期格式。"
            case .http(let status, let body):
                let trimmed = body.count > 400 ? String(body.prefix(400)) + "…" : body
                return "OpenAI 接口错误 (HTTP \(status))：\(trimmed)"
            case .decoding(let message): return "解析 OpenAI 响应失败：\(message)"
            case .noContent: return "OpenAI 响应为空。"
            }
        }
    }

    let apiKey: String
    let model: String
    let baseURL: URL
    let timeoutSeconds: TimeInterval

    init(apiKey: String,
         model: String = "gpt-4o-mini",
         baseURL: URL = URL(string: "https://api.openai.com/v1")!,
         timeoutSeconds: TimeInterval = 60) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.timeoutSeconds = timeoutSeconds
    }

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    /// Sends a chat completion request asking the model to return strict JSON.
    /// The caller is responsible for prompting the model to produce valid JSON.
    func completeJSON(messages: [ChatMessage], temperature: Double = 0.4) async throws -> String {
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        struct ResponseFormat: Codable { let type: String }
        struct Body: Codable {
            let model: String
            let messages: [ChatMessage]
            let temperature: Double
            let response_format: ResponseFormat
        }
        let body = Body(
            model: model,
            messages: messages,
            temperature: temperature,
            response_format: ResponseFormat(type: "json_object")
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            Self.log.error("OpenAI HTTP \(http.statusCode): \(text)")
            throw ClientError.http(status: http.statusCode, body: text)
        }

        struct ChatChoice: Codable {
            struct Msg: Codable { let role: String; let content: String? }
            let message: Msg
        }
        struct ChatResponse: Codable { let choices: [ChatChoice] }

        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
                throw ClientError.noContent
            }
            return content
        } catch let e as ClientError {
            throw e
        } catch {
            throw ClientError.decoding(error.localizedDescription)
        }
    }

    /// Probe call: lists models accessible by the key. Returns model IDs sorted alphabetically.
    func listModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(status: http.statusCode, body: text)
        }

        struct ModelInfo: Codable { let id: String }
        struct ModelList: Codable { let data: [ModelInfo] }

        do {
            let decoded = try JSONDecoder().decode(ModelList.self, from: data)
            return decoded.data.map(\.id).sorted()
        } catch {
            throw ClientError.decoding(error.localizedDescription)
        }
    }
}
