import Foundation

/// Wraps the wordstory.vercel.app HTTP API.
///
/// Two endpoints:
/// - `POST /api/define`   — single-word definition + example
/// - `POST /api/generate` — full story using a list of words
///
/// Both use `application/json` request/response bodies. Errors map to ``APIError``
/// so views can show friendly messages.
struct APIService {

    static let baseURL = URL(string: "https://wordstory.vercel.app")!

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidResponse
        case server(status: Int, message: String?)
        case decoding
        case transport(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return String(localized: "error.invalid_response")
            case .server(_, let message):
                return message ?? String(localized: "error.server_generic")
            case .decoding:
                return String(localized: "error.decoding")
            case .transport(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    // MARK: - Define

    struct DefineResponse: Decodable {
        let word: String
        let definition: String
        let example: String

        init(word: String, definition: String, example: String) {
            self.word = word
            self.definition = definition
            self.example = example
        }
    }

    /// Defines a word with offline-first behavior:
    /// 1. Try the bundled ECDICT dictionary (covers ~770k English headwords).
    /// 2. On a local miss, fall through to the online `/api/define`.
    /// Both paths return the same `DefineResponse` shape so callers don't care
    /// which one succeeded.
    static func defineWord(_ word: String, direction: LanguageDirection) async throws -> DefineResponse {
        if let hit = await DictionaryService.shared.lookup(word, direction: direction) {
            print("[APIService] local hit: \(word)")
            return DefineResponse(
                word: hit.word,
                definition: hit.translation,
                example: ""
            )
        }
        print("[APIService] local miss, online lookup: \(word)")
        struct Payload: Encodable { let word: String; let direction: String }
        let body = Payload(word: word, direction: direction.rawValue)
        return try await post(path: "/api/define", body: body)
    }

    // MARK: - Generate

    struct GeneratePayload: Encodable {
        struct WordEntry: Encodable { let word: String }
        let words: [WordEntry]
        let style: String
        let customPrompt: String
        let direction: String
    }

    struct GenerateResponse: Decodable {
        /// English + Chinese sentence pairs. Empty when the server couldn't
        /// extract them (truncated response, very old server, etc.) — clients
        /// fall back to the flat story_en / story_zh fields in that case.
        let sentences: [SentencePair]?
        /// Full English version of the generated piece (concatenated for
        /// convenience and as the fallback when `sentences` is missing).
        let story_en: String
        /// Full Traditional Chinese version of the same piece.
        let story_zh: String

        struct SentencePair: Decodable, Hashable {
            let en: String
            let zh: String
        }
    }

    /// Calls `/api/generate` with a list of words and a style.
    static func generateStory(
        words: [String],
        style: StoryStyle,
        customPrompt: String,
        direction: LanguageDirection
    ) async throws -> GenerateResponse {
        let payload = GeneratePayload(
            words: words.map { GeneratePayload.WordEntry(word: $0) },
            style: style.rawValue,
            customPrompt: customPrompt,
            direction: direction.rawValue
        )
        return try await post(path: "/api/generate", body: payload)
    }

    // MARK: - Transport

    private struct ServerError: Decodable { let error: String? }

    private static func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // The API expects `customPrompt` (camelCase) but `direction` and `words` as-is.
        // We custom-encode to match the API contract exactly without the snake-case mangle.
        encoder.keyEncodingStrategy = .useDefaultKeys

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.decoding
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[APIService] POST \(path) transport error: \(error.localizedDescription)")
            throw APIError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            print("[APIService] POST \(path) — non-HTTP response: \(type(of: response))")
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
            let bodySnippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            print("[APIService] POST \(path) HTTP \(http.statusCode): \(message ?? String(bodySnippet))")
            throw APIError.server(status: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // Longer body snippet for /api/generate failures so dual-language
            // truncation issues are visible in the Xcode console.
            let snippetLimit = path.contains("/api/generate") ? 500 : 200
            let bodySnippet = String(data: data, encoding: .utf8)?.prefix(snippetLimit) ?? ""
            print("[APIService] POST \(path) decode failed: \(error). Body: \(bodySnippet)")
            throw APIError.decoding
        }
    }
}
