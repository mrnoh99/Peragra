import Foundation

struct AIExtractedPlace: Decodable {
    let name: String
    let address: String?
}

enum AIExtractionError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case authenticationFailed
    case rateLimited
    case apiError(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured — add one in Settings."
        case .invalidResponse:
            return "Couldn't reach the AI extraction service."
        case .authenticationFailed:
            return "That API key was rejected — check it in Settings."
        case .rateLimited:
            return "Rate limited by the gateway — try again in a moment."
        case .apiError(let message):
            return "Gateway error: \(message)"
        case .decodingFailed:
            return "Couldn't understand the AI's response."
        }
    }
}

/// Extracts place recommendations from caption text or a caption
/// screenshot using the user's own API key, called directly from the
/// device (this app has no server). Routed through a third-party
/// OpenAI-compatible gateway (factchat-cloud.mindlogic.ai) rather than
/// Anthropic's own API — per explicit instruction. This means
/// captions/screenshots sent for extraction pass through that gateway, not
/// just Anthropic directly, and the key entered in Settings is one issued
/// by that gateway, not an Anthropic key. Its actual feature support
/// (vision passthrough, JSON mode) is undocumented from here, so this
/// prompts for JSON in plain chat-completion form and decodes the response
/// manually rather than relying on any provider-specific structured-output
/// extension (mirrors web/src/lib/aiExtract.ts).
enum AIExtractionService {
    // Trailing slash matters — the gateway's documented endpoint is
    // "/v1/gateway/chat/completions/" and a request without one risks a
    // 404 or a broken POST-to-GET redirect on a Django-style backend that
    // enforces trailing slashes (confirmed as a real discrepancy while
    // testing the equivalent web request against a local mock server —
    // the openai npm SDK's own path-building drops the trailing slash by
    // default, which is what led to catching this here too).
    private static let endpoint = URL(string: "https://factchat-cloud.mindlogic.ai/v1/gateway/chat/completions/")!

    private static let systemPrompt = """
    You extract place recommendations (restaurants, cafes, shops, attractions) from \
    an Instagram post's caption text or a screenshot of one. Return every distinct \
    place mentioned, each with its name and, if given, its full address exactly as \
    written. If no address is given for a place, use null — never guess or invent \
    one. If nothing in the text describes an actual place, return an empty list.

    Respond with ONLY a single JSON object, no other text, no markdown code fence, \
    matching exactly this shape: {"places": [{"name": string, "address": string | null}]}
    """

    static func extractPlaces(apiKey: String, captionText: String) async throws -> [AIExtractedPlace] {
        try await request(apiKey: apiKey, userContent: captionText)
    }

    static func extractPlaces(apiKey: String, imageData: Data, mediaType: String) async throws -> [AIExtractedPlace] {
        let base64 = imageData.base64EncodedString()
        let content: [[String: Any]] = [
            [
                "type": "text",
                "text": "Extract every place recommended in this screenshot's caption.",
            ],
            [
                "type": "image_url",
                "image_url": ["url": "data:\(mediaType);base64,\(base64)"],
            ],
        ]
        return try await request(apiKey: apiKey, userContent: content)
    }

    private static func request(apiKey: String, userContent: Any) async throws -> [AIExtractedPlace] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw AIExtractionError.missingAPIKey }

        let body: [String: Any] = [
            "model": AISettings.shared.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExtractionError.invalidResponse
        }

        let rawJSON = try? JSONSerialization.jsonObject(with: data)
        let json = rawJSON as? [String: Any]

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw AIExtractionError.authenticationFailed }
            if httpResponse.statusCode == 429 { throw AIExtractionError.rateLimited }
            let errorObject = json?["error"] as? [String: Any]
            let message = (errorObject?["message"] as? String) ?? (json?["error"] as? String)
            throw AIExtractionError.apiError(message ?? "HTTP \(httpResponse.statusCode)")
        }

        guard
            let choices = json?["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw AIExtractionError.decodingFailed
        }

        return try parsePlaces(from: text)
    }

    /// Tolerates a markdown code fence around the JSON despite the prompt
    /// asking for none — models routed through arbitrary gateways don't
    /// reliably follow that.
    private static func parsePlaces(from text: String) throws -> [AIExtractedPlace] {
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = jsonText.range(of: "```(?:json)?\\s*([\\s\\S]*?)\\s*```", options: .regularExpression) {
            let fenced = String(jsonText[range])
            jsonText = fenced
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let textData = jsonText.data(using: .utf8) else {
            throw AIExtractionError.decodingFailed
        }

        struct PlacesResponse: Decodable {
            let places: [AIExtractedPlace]
        }

        guard let decoded = try? JSONDecoder().decode(PlacesResponse.self, from: textData) else {
            throw AIExtractionError.decodingFailed
        }
        return decoded.places
    }
}
