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
    case missingAPIKey(String)
    case invalidResponse(String)
    case authenticationFailed(String)
    case rateLimited(String)
    case apiError(String, String)
    case decodingFailed
    case visionUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let label):
            return "No \(label) API key set — add one in Settings."
        case .invalidResponse(let label):
            return "Couldn't reach \(label)."
        case .authenticationFailed(let label):
            return "That \(label) API key was rejected — check it in Settings."
        case .rateLimited(let label):
            return "Rate limited by \(label) — try again in a moment."
        case .apiError(let label, let message):
            return "\(label) error: \(message)"
        case .decodingFailed:
            return "Couldn't understand the AI's response."
        case .visionUnsupported(let label):
            return "\(label) doesn't support reading screenshots — switch providers in Settings, or paste the caption text instead."
        }
    }
}

/// Extracts place recommendations from caption text or a caption
/// screenshot using the active provider's API key (see AISettings),
/// called directly from the device (this app has no server).
///
/// The default provider ("gateway") routes through a third-party
/// OpenAI-compatible gateway (factchat-cloud.mindlogic.ai) rather than any
/// provider's own API — per explicit instruction, kept as the default.
/// Its actual feature support (vision passthrough, JSON mode) is
/// undocumented from here, so this prompts for JSON in plain
/// chat-completion form and decodes the response manually rather than
/// relying on any provider-specific structured-output extension — the
/// same technique is reused for every direct provider below so there's
/// only one response-parsing path to trust.
///
/// Alongside the gateway, Settings also offers calling Anthropic, OpenAI,
/// Google (Gemini), or Perplexity directly with the user's own key for
/// that provider — bypassing the gateway entirely. Unlike a browser, a
/// native URLSession request isn't subject to CORS, so no special
/// browser-access opt-in header is needed for the direct providers here
/// (mirrors web/src/lib/aiExtract.ts, which does need one on the web).
/// Perplexity's API has no vision support, so screenshot extraction is
/// unavailable when it's the active provider (checked in
/// performChatRequest below).
enum AIExtractionService {
    static let defaultAnthropicModel = "claude-sonnet-5"
    static let defaultOpenAIModel = "gpt-4o"
    static let defaultGeminiModel = "gemini-2.0-flash"
    static let defaultPerplexityModel = "sonar"

    // Trailing slash matters — the gateway's documented endpoint is
    // "/v1/gateway/chat/completions/" and a request without one risks a
    // 404 or a broken POST-to-GET redirect on a Django-style backend that
    // enforces trailing slashes (confirmed as a real discrepancy while
    // testing the equivalent web request against a local mock server).
    // Real OpenAI-compatible APIs (OpenAI itself, Perplexity) don't have
    // this quirk.
    private static let gatewayEndpoint = URL(string: "https://factchat-cloud.mindlogic.ai/v1/gateway/chat/completions/")!
    private static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let perplexityEndpoint = URL(string: "https://api.perplexity.ai/chat/completions")!
    private static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

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

    static func extractPlaces(imageData: Data, mediaType: String) async throws -> [AIExtractedPlace] {
        try await extractPlaces(images: [(data: imageData, mediaType: mediaType)])
    }

    /// Same as the single-image overload, but for several photos of the
    /// *same* place (e.g. a storefront sign, a menu, the interior) sent
    /// together in one request — letting the model cross-reference them
    /// into one accurate, consolidated result rather than reconciling
    /// separate per-photo guesses itself.
    ///
    /// `isOnSitePhoto` picks the right prompt for what these photos
    /// actually show — it can't be inferred from the photo count alone,
    /// since the on-site flow can just as easily hand this a single photo
    /// (one storefront shot) as the screenshot flow always does. Getting
    /// this wrong sends a real on-site photo through wording written for
    /// an Instagram caption screenshot ("extract every place recommended
    /// in this caption"), which reads a sign or menu as if it were social
    /// copy and can come back empty.
    static func extractPlaces(images: [(data: Data, mediaType: String)], isOnSitePhoto: Bool = false) async throws -> [AIExtractedPlace] {
        let encoded = images.map { (mediaType: $0.mediaType, base64: $0.data.base64EncodedString()) }
        let textPrompt: String
        if isOnSitePhoto {
            textPrompt = images.count > 1
                ? "These photos were taken in person at a single real place — extract one consolidated, accurate result for it, cross-referencing all the photos (for example, a storefront sign for the name and a menu photo for prices/items)."
                : "This photo was taken in person at a single real place (its storefront, sign, menu, or interior) — extract one accurate result for it from whatever is written or shown, such as its name and any menu items, prices, or hours visible."
        } else {
            textPrompt = "Extract every place recommended in this screenshot's caption."
        }
        let text = try await performChatRequest(
            systemPrompt: systemPrompt,
            textPrompt: textPrompt,
            images: encoded
        )
        return try parsePlaces(from: text)
    }

    /// Best-effort guess at a full address for each of the given place
    /// names, using the model's general knowledge rather than anything
    /// extracted from a caption — for places a caption named without ever
    /// giving an address. Returns one entry per input name, in order; an
    /// entry is nil where the model wasn't confident enough to guess.
    static func guessAddresses(destination: String, placeNames: [String]) async throws -> [String?] {
        guard !placeNames.isEmpty else { return [] }
        let placesList = placeNames.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let textPrompt = "Destination: \(destination)\n\nPlaces:\n\(placesList)"
        let text = try await performChatRequest(systemPrompt: addressGuessSystemPrompt, textPrompt: textPrompt, images: [])
        return try parseAddressGuesses(from: text, count: placeNames.count)
    }

    /// Best-effort fallback for when ordinary geocoding fails on a place's
    /// own address/name: asks AI for its single best guess at the nearest
    /// plausible real address, using everything known about the place
    /// (its name, the address that failed to geocode, and any other
    /// notes) rather than just the name alone. Returns nil when the model
    /// has no reasonable basis for a guess.
    static func guessNearestAddress(
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
        let textPrompt = "Destination: \(destination)\n\n\(details)"
        let text = try await performChatRequest(systemPrompt: nearestLocationSystemPrompt, textPrompt: textPrompt, images: [])
        return try parseNearestLocation(from: text)
    }

    /// Routes to whichever provider is currently active in Settings.
    private static func performChatRequest(
        systemPrompt: String,
        textPrompt: String,
        images: [(mediaType: String, base64: String)]
    ) async throws -> String {
        let settings = AISettings.shared
        switch settings.provider {
        case .gateway:
            let apiKey = try requireKey(settings.apiKey, label: "AI extraction gateway")
            return try await performOpenAICompatibleRequest(
                endpoint: gatewayEndpoint,
                apiKey: apiKey,
                model: settings.model,
                systemPrompt: systemPrompt,
                userContent: openAICompatibleUserContent(text: textPrompt, images: images),
                serviceLabel: "the gateway"
            )
        case .openai:
            let apiKey = try requireKey(settings.openaiAPIKey, label: "OpenAI")
            return try await performOpenAICompatibleRequest(
                endpoint: openAIEndpoint,
                apiKey: apiKey,
                model: settings.openaiModel,
                systemPrompt: systemPrompt,
                userContent: openAICompatibleUserContent(text: textPrompt, images: images),
                serviceLabel: "OpenAI"
            )
        case .perplexity:
            if !images.isEmpty { throw AIExtractionError.visionUnsupported("Perplexity") }
            let apiKey = try requireKey(settings.perplexityAPIKey, label: "Perplexity")
            return try await performOpenAICompatibleRequest(
                endpoint: perplexityEndpoint,
                apiKey: apiKey,
                model: settings.perplexityModel,
                systemPrompt: systemPrompt,
                userContent: textPrompt,
                serviceLabel: "Perplexity"
            )
        case .anthropic:
            let apiKey = try requireKey(settings.anthropicAPIKey, label: "Anthropic")
            return try await performAnthropicRequest(
                apiKey: apiKey,
                model: settings.anthropicModel,
                systemPrompt: systemPrompt,
                userContent: anthropicUserContent(text: textPrompt, images: images)
            )
        case .gemini:
            let apiKey = try requireKey(settings.geminiAPIKey, label: "Gemini")
            return try await performGeminiRequest(
                apiKey: apiKey,
                model: settings.geminiModel,
                systemPrompt: systemPrompt,
                textPrompt: textPrompt,
                images: images
            )
        }
    }

    private static func requireKey(_ key: String?, label: String) throws -> String {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { throw AIExtractionError.missingAPIKey(label) }
        return trimmed
    }

    private static func openAICompatibleUserContent(text: String, images: [(mediaType: String, base64: String)]) -> Any {
        guard !images.isEmpty else { return text }
        var content: [[String: Any]] = [["type": "text", "text": text]]
        for image in images {
            content.append(["type": "image_url", "image_url": ["url": "data:\(image.mediaType);base64,\(image.base64)"]])
        }
        return content
    }

    private static func anthropicUserContent(text: String, images: [(mediaType: String, base64: String)]) -> [[String: Any]] {
        let imageBlocks = images.map { image in
            ["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.base64]] as [String: Any]
        }
        return imageBlocks + [["type": "text", "text": text]]
    }

    /// Shared by the gateway, OpenAI-direct, and Perplexity — all speak
    /// the same OpenAI-compatible chat API.
    private static func performOpenAICompatibleRequest(
        endpoint: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userContent: Any,
        serviceLabel: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExtractionError.invalidResponse(serviceLabel)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw AIExtractionError.authenticationFailed(serviceLabel) }
            if httpResponse.statusCode == 429 { throw AIExtractionError.rateLimited(serviceLabel) }
            let errorObject = json?["error"] as? [String: Any]
            let message = (errorObject?["message"] as? String) ?? (json?["error"] as? String)
            throw AIExtractionError.apiError(serviceLabel, message ?? "HTTP \(httpResponse.statusCode)")
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

    /// Anthropic's own Messages API — a different request/response shape
    /// than the OpenAI-compatible one above.
    private static func performAnthropicRequest(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userContent: [[String: Any]]
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userContent]],
        ]

        var urlRequest = URLRequest(url: anthropicEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExtractionError.invalidResponse("Anthropic")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw AIExtractionError.authenticationFailed("Anthropic") }
            if httpResponse.statusCode == 429 { throw AIExtractionError.rateLimited("Anthropic") }
            let errorObject = json?["error"] as? [String: Any]
            let message = errorObject?["message"] as? String
            throw AIExtractionError.apiError("Anthropic", message ?? "HTTP \(httpResponse.statusCode)")
        }

        guard
            let content = json?["content"] as? [[String: Any]],
            let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
            let text = textBlock["text"] as? String
        else {
            throw AIExtractionError.decodingFailed
        }

        return text
    }

    /// Google's Gemini API — its own REST shape (no bundled SDK here).
    private static func performGeminiRequest(
        apiKey: String,
        model: String,
        systemPrompt: String,
        textPrompt: String,
        images: [(mediaType: String, base64: String)]
    ) async throws -> String {
        var parts: [[String: Any]] = [["text": textPrompt]]
        for image in images {
            parts.append(["inline_data": ["mime_type": image.mediaType, "data": image.base64]])
        }

        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw AIExtractionError.invalidResponse("Gemini")
        }

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExtractionError.invalidResponse("Gemini")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AIExtractionError.authenticationFailed("Gemini")
            }
            if httpResponse.statusCode == 429 { throw AIExtractionError.rateLimited("Gemini") }
            throw AIExtractionError.apiError("Gemini", "HTTP \(httpResponse.statusCode)")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard
            let candidates = json?["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let responseParts = content["parts"] as? [[String: Any]],
            let text = responseParts.first?["text"] as? String
        else {
            throw AIExtractionError.decodingFailed
        }

        return text
    }

    /// Strips a markdown code fence around JSON despite the prompt asking
    /// for none — models routed through arbitrary gateways/providers
    /// don't reliably follow that.
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
