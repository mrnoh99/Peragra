import Foundation

struct AIExtractedPlace: Decodable {
    let name: String
    let address: String?
}

enum AIExtractionError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key configured — add one in Settings."
        case .invalidResponse:
            return "Couldn't reach the AI extraction service."
        case .apiError(let message):
            return "Anthropic API error: \(message)"
        case .decodingFailed:
            return "Couldn't understand the AI's response."
        }
    }
}

/// Extracts place recommendations from caption text or a caption
/// screenshot using the user's own Anthropic API key, called directly from
/// the device (this app has no server). Swift has no official Anthropic
/// SDK, so this talks to the Messages API directly over HTTPS.
enum AIExtractionService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-5"
    private static let anthropicVersion = "2023-06-01"

    private static let systemPrompt = """
    You extract place recommendations (restaurants, cafes, shops, attractions) from \
    an Instagram post's caption text or a screenshot of one. Return every distinct \
    place mentioned, each with its name and, if given, its full address exactly as \
    written. If no address is given for a place, use null — never guess or invent \
    one. If nothing in the text describes an actual place, return an empty list.
    """

    // Matches the JSON schema `zodOutputFormat()` produces for the
    // equivalent Zod schema on the web client, so both platforms constrain
    // the model's output identically.
    private static let outputFormat: [String: Any] = [
        "type": "json_schema",
        "schema": [
            "type": "object",
            "properties": [
                "places": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "address": ["type": ["string", "null"]],
                        ],
                        "additionalProperties": false,
                        "required": ["name", "address"],
                    ],
                ],
            ],
            "additionalProperties": false,
            "required": ["places"],
        ],
    ]

    static func extractPlaces(apiKey: String, captionText: String) async throws -> [AIExtractedPlace] {
        try await request(apiKey: apiKey, messageContent: captionText)
    }

    static func extractPlaces(apiKey: String, imageData: Data, mediaType: String) async throws -> [AIExtractedPlace] {
        let base64 = imageData.base64EncodedString()
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": ["type": "base64", "media_type": mediaType, "data": base64],
            ],
            [
                "type": "text",
                "text": "Extract every place recommended in this screenshot's caption.",
            ],
        ]
        return try await request(apiKey: apiKey, messageContent: content)
    }

    private static func request(apiKey: String, messageContent: Any) async throws -> [AIExtractedPlace] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw AIExtractionError.missingAPIKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": messageContent],
            ],
            "output_config": ["format": outputFormat],
        ]

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExtractionError.invalidResponse
        }

        let rawJSON = try? JSONSerialization.jsonObject(with: data)
        let json = rawJSON as? [String: Any]

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorObject = json?["error"] as? [String: Any]
            let message = errorObject?["message"] as? String
            throw AIExtractionError.apiError(message ?? "HTTP \(httpResponse.statusCode)")
        }

        guard
            let contentBlocks = json?["content"] as? [[String: Any]],
            let textBlock = contentBlocks.first(where: { $0["type"] as? String == "text" }),
            let text = textBlock["text"] as? String,
            let textData = text.data(using: .utf8)
        else {
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
