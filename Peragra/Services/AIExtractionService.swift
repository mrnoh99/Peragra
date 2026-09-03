import Foundation

struct AIExtractedPlace: Decodable {
    let name: String
    let address: String?
    let telephone: String?
    // Anything else recognized about this specific place (hours, price, a
    // recommended item, why it was recommended, ...) — combined with the
    // form's own manual notes field at save time, not a replacement for it.
    let notes: String?
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
    place mentioned, each with these fields:
    - name: the place's name
    - address: its full address exactly as written, or null if none was given
    - telephone: its phone number exactly as written, or null if none was given
    - notes: anything else relevant to that specific place — hours, price, a \
    recommended menu item, why it was recommended, a rating, and so on — as short \
    free text, or null if nothing else was said about it. Don't repeat the \
    name/address/telephone here, and don't include generic caption text that isn't \
    about this specific place (like unrelated hashtags).

    Never guess or invent any of these — use null when something wasn't actually \
    given. If nothing in the text describes an actual place, return an empty list.

    Respond with ONLY a single JSON object, no other text, no markdown code fence, \
    matching exactly this shape: {"places": [{"name": string, "address": string | null, \
    "telephone": string | null, "notes": string | null}]}
    """

    private static let addressGuessSystemPrompt = """
    You are given a travel destination and a numbered list of place names \
    (restaurants, cafes, shops, attractions, hotels, etc.) that were saved without \
    an address. For each place, if you have reasonably confident knowledge of a \
    real, specific location matching that name at or near the given destination, \
    respond with your single best-guess full address for it. If you aren't \
    reasonably confident — the name is too generic, ambiguous, or unfamiliar — \
    respond with null for that entry rather than inventing one.

    Respond with ONLY a single JSON object, no other text, no markdown code fence, \
    matching exactly this shape: {"addresses": (string | null)[]}, with exactly one \
    entry per input place, in the same order.
    """

    private static let nearestLocationSystemPrompt = """
    You are given a travel destination and everything known about a single saved \
    place — its name and, if available, an address (which may be incomplete, \
    garbled, or simply wrong, since it couldn't be located on a map) and other \
    notes about it. Using all of that, if you have a reasonably confident guess at \
    a real, specific location for this place at or near the given destination, \
    respond with your single best-guess full address for it — ideally the correct \
    one, but the closest plausible real location is still useful when you're not \
    sure of the exact spot. If you have no reasonable basis for a guess at all, \
    respond with null rather than inventing one.

    Respond with ONLY a single JSON object, no other text, no markdown code fence, \
    matching exactly this shape: {"address": string | null}
    """

    static func extractPlaces(apiKey: String, captionText: String) async throws -> [AIExtractedPlace] {
        let text = try await performChatRequest(apiKey: apiKey, systemPrompt: systemPrompt, userContent: captionText)
        return try parsePlaces(from: text)
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
        let text = try await performChatRequest(apiKey: apiKey, systemPrompt: systemPrompt, userContent: content)
        return try parsePlaces(from: text)
    }

    /// Best-effort guess at a full address for each of the given place
    /// names, using the model's general knowledge rather than anything
    /// extracted from a caption — for places a caption named without ever
    /// giving an address. Returns one entry per input name, in order; an
    /// entry is nil where the model wasn't confident enough to guess.
    static func guessAddresses(apiKey: String, destination: String, placeNames: [String]) async throws -> [String?] {
        guard !placeNames.isEmpty else { return [] }
        let placesList = placeNames.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let userContent = "Destination: \(destination)\n\nPlaces:\n\(placesList)"
        let text = try await performChatRequest(apiKey: apiKey, systemPrompt: addressGuessSystemPrompt, userContent: userContent)
        return try parseAddressGuesses(from: text, count: placeNames.count)
    }

    /// Best-effort fallback for when ordinary geocoding fails on a place's
    /// own address/name: asks AI for its single best guess at the nearest
    /// plausible real address, using everything known about the place
    /// (its name, the address that failed to geocode, and any other
    /// notes) rather than just the name alone. Returns nil when the model
    /// has no reasonable basis for a guess.
    static func guessNearestAddress(
        apiKey: String,
        destination: String,
        name: String,
        address: String?,
        telephone: String?,
        notes: String?
    ) async throws -> String? {
        let details = [
            "Name: \(name)",
            address.map { "Address given (could not be located on a map): \($0)" },
            telephone.map { "Phone: \($0)" },
            notes.map { "Other notes: \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let userContent = "Destination: \(destination)\n\n\(details)"
        let text = try await performChatRequest(apiKey: apiKey, systemPrompt: nearestLocationSystemPrompt, userContent: userContent)
        return try parseNearestLocation(from: text)
    }

    private static func performChatRequest(apiKey: String, systemPrompt: String, userContent: Any) async throws -> String {
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

        return text
    }

    /// Strips a markdown code fence around JSON despite the prompt asking
    /// for none — models routed through arbitrary gateways don't reliably
    /// follow that.
    private static func stripMarkdownFence(from text: String) -> String {
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = jsonText.range(of: "```(?:json)?\\s*([\\s\\S]*?)\\s*```", options: .regularExpression) {
            let fenced = String(jsonText[range])
            jsonText = fenced
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return jsonText
    }

    private static func parsePlaces(from text: String) throws -> [AIExtractedPlace] {
        let jsonText = stripMarkdownFence(from: text)
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

    private static func parseAddressGuesses(from text: String, count: Int) throws -> [String?] {
        let jsonText = stripMarkdownFence(from: text)
        guard let textData = jsonText.data(using: .utf8) else {
            throw AIExtractionError.decodingFailed
        }

        struct AddressGuessResponse: Decodable {
            let addresses: [String?]
        }

        guard let decoded = try? JSONDecoder().decode(AddressGuessResponse.self, from: textData) else {
            throw AIExtractionError.decodingFailed
        }
        // Pad/truncate defensively in case the model didn't return exactly
        // one entry per input place.
        return (0..<count).map { $0 < decoded.addresses.count ? decoded.addresses[$0] : nil }
    }

    private static func parseNearestLocation(from text: String) throws -> String? {
        let jsonText = stripMarkdownFence(from: text)
        guard let textData = jsonText.data(using: .utf8) else {
            throw AIExtractionError.decodingFailed
        }

        struct NearestLocationResponse: Decodable {
            let address: String?
        }

        guard let decoded = try? JSONDecoder().decode(NearestLocationResponse.self, from: textData) else {
            throw AIExtractionError.decodingFailed
        }
        return decoded.address
    }
}
