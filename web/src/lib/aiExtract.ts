import Anthropic from "@anthropic-ai/sdk";
import OpenAI from "openai";
import { z } from "zod";
import { useAISettingsStore } from "../store/useAISettingsStore";

// The default provider: a third-party OpenAI-compatible gateway
// (factchat-cloud.mindlogic.ai) rather than calling Anthropic's own API —
// per explicit instruction, kept as the default. This means
// captions/screenshots sent through it pass through that gateway, and the
// key entered in Settings for it is a key issued by that gateway, not an
// Anthropic key. Per the gateway's own docs, JSON mode / structured
// output isn't among its listed endpoints, so this prompts for JSON in
// plain chat-completion form and validates the response against the
// schema below rather than relying on a provider-specific extension — the
// same technique is reused for every direct provider below so there's
// only one response-parsing path to trust.
//
// Alongside the gateway, Settings also offers calling Anthropic, OpenAI,
// Google (Gemini), or Perplexity directly with the user's own key for
// that provider — bypassing the gateway entirely. Perplexity's API has no
// vision support, so screenshot extraction is unavailable when it's the
// active provider (checked in callModel below).
const GATEWAY_BASE_URL = "https://factchat-cloud.mindlogic.ai/v1/gateway";
const PERPLEXITY_BASE_URL = "https://api.perplexity.ai";

// The documented gateway endpoint is "/v1/gateway/chat/completions/" —
// WITH a trailing slash. The openai SDK's own
// client.chat.completions.create() always requests the path without one
// (confirmed by testing against a local mock server), which risks a 404
// or a broken POST-to-GET redirect on a Django-style backend that
// enforces trailing slashes. Calling the SDK's lower-level client.post()
// with the exact path sidesteps that — real OpenAI-compatible APIs
// (OpenAI itself, Perplexity) don't have this quirk, but the same
// low-level call works fine against them too.
const GATEWAY_CHAT_COMPLETIONS_PATH = "/chat/completions/";
const CHAT_COMPLETIONS_PATH = "/chat/completions";

interface OpenAICompatibleChatResponse {
  choices?: { message?: { content?: string | null } }[];
}

const PlacesSchema = z.object({
  places: z.array(
    z.object({
      name: z.string().describe("The place's name (restaurant, cafe, shop, attraction, etc.)"),
      address: z
        .string()
        .nullable()
        .describe("The place's full address as written, or null if none was given"),
      telephone: z
        .string()
        .nullable()
        .describe("The place's phone number as written, or null if none was given"),
      notes: z
        .string()
        .nullable()
        .describe(
          "Any other detail about this specific place worth keeping (hours, price, a recommended " +
            "menu item, why it was recommended, a rating, etc.), as free text, or null if nothing else was said",
        ),
    }),
  ),
});

export interface AIExtractedPlace {
  name: string;
  address: string | null;
  telephone: string | null;
  notes: string | null;
}

export class AIExtractionError extends Error {}

type ImageMediaType = "image/jpeg" | "image/png" | "image/gif" | "image/webp";

const SYSTEM_PROMPT =
  "You extract place recommendations (restaurants, cafes, shops, attractions) from " +
  "an Instagram post's caption text or a screenshot of one. Return every distinct " +
  "place mentioned, each with these fields:\n" +
  "- name: the place's name\n" +
  "- address: its full address exactly as written, or null if none was given\n" +
  "- telephone: its phone number exactly as written, or null if none was given\n" +
  "- notes: anything else relevant to that specific place — hours, price, a recommended " +
  "menu item, why it was recommended, a rating, and so on — as short free text, or null if " +
  "nothing else was said about it. Don't repeat the name/address/telephone here, and don't " +
  "include generic caption text that isn't about this specific place (like unrelated hashtags).\n\n" +
  "Never guess or invent any of these — use null when something wasn't actually given. If " +
  "nothing in the text describes an actual place, return an empty list.\n\n" +
  "Respond with ONLY a single JSON object, no other text, no markdown code fence, matching " +
  'exactly this shape: {"places": [{"name": string, "address": string | null, ' +
  '"telephone": string | null, "notes": string | null}]}';

const ADDRESS_GUESS_SYSTEM_PROMPT =
  "You are given a travel destination and a numbered list of place names " +
  "(restaurants, cafes, shops, attractions, hotels, etc.) that were saved without " +
  "an address. For each place, if you have reasonably confident knowledge of a " +
  "real, specific location matching that name at or near the given destination, " +
  "respond with your single best-guess full address for it. If you aren't " +
  "reasonably confident — the name is too generic, ambiguous, or unfamiliar — " +
  "respond with null for that entry rather than inventing one.\n\n" +
  "Respond with ONLY a single JSON object, no other text, no markdown code fence, " +
  'matching exactly this shape: {"addresses": (string | null)[]}, with exactly one ' +
  "entry per input place, in the same order.";

const AddressGuessSchema = z.object({
  addresses: z.array(z.string().nullable()),
});

const NEAREST_LOCATION_SYSTEM_PROMPT =
  "You are given a travel destination and everything known about a single saved place — " +
  "its name and, if available, an address (which may be incomplete, garbled, or simply wrong, " +
  "since it couldn't be located on a map) and other notes about it. Using all of that, if you " +
  "have a reasonably confident guess at a real, specific location for this place at or near the " +
  "given destination, respond with your single best-guess full address for it — ideally the " +
  "correct one, but the closest plausible real location is still useful when you're not sure of " +
  "the exact spot. If you have no reasonable basis for a guess at all, respond with null rather " +
  "than inventing one.\n\n" +
  "Respond with ONLY a single JSON object, no other text, no markdown code fence, matching " +
  'exactly this shape: {"address": string | null}';

const NearestLocationSchema = z.object({
  address: z.string().nullable(),
});

/**
 * Strips a markdown code fence around JSON despite the prompt asking for
 * none — models routed through arbitrary gateways/providers don't
 * reliably follow that — then JSON.parses the result.
 */
function parseJsonContent(content: string | null | undefined): unknown {
  if (!content) {
    throw new AIExtractionError("The AI extraction service returned an empty response.");
  }
  const fenced = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  const jsonText = fenced ? fenced[1] : content;
  try {
    return JSON.parse(jsonText);
  } catch {
    throw new AIExtractionError("The AI extraction service didn't return valid JSON.");
  }
}

/** One request to send to whichever provider is currently active. */
interface ChatContent {
  systemPrompt: string;
  text: string;
  images?: { mediaType: ImageMediaType; base64: string }[];
}

function requireKey(key: string | null, providerLabel: string): string {
  if (!key) {
    throw new AIExtractionError(`No ${providerLabel} API key set — add one in Settings.`);
  }
  return key;
}

function toOpenAICompatibleError(error: unknown, serviceLabel: string): AIExtractionError {
  if (error instanceof OpenAI.AuthenticationError) {
    return new AIExtractionError(`That ${serviceLabel} API key was rejected — check it in Settings.`);
  }
  if (error instanceof OpenAI.RateLimitError) {
    return new AIExtractionError(`Rate limited by ${serviceLabel} — try again in a moment.`);
  }
  if (error instanceof OpenAI.APIError) {
    return new AIExtractionError(`${serviceLabel} error: ${error.message}`);
  }
  return new AIExtractionError(`Couldn't reach ${serviceLabel}.`);
}

/** Shared by the gateway, OpenAI-direct, and Perplexity — all speak the same OpenAI-compatible chat API. */
async function callOpenAICompatible(options: {
  baseURL: string;
  path: string;
  apiKey: string;
  model: string;
  content: ChatContent;
  serviceLabel: string;
}): Promise<string | null | undefined> {
  const client = new OpenAI({ apiKey: options.apiKey, baseURL: options.baseURL, dangerouslyAllowBrowser: true });
  const userContent = options.content.images?.length
    ? [
        { type: "text" as const, text: options.content.text },
        ...options.content.images.map((image) => ({
          type: "image_url" as const,
          image_url: { url: `data:${image.mediaType};base64,${image.base64}` },
        })),
      ]
    : options.content.text;
  try {
    const response = await client.post<OpenAICompatibleChatResponse>(options.path, {
      body: {
        model: options.model,
        messages: [
          { role: "system", content: options.content.systemPrompt },
          { role: "user", content: userContent },
        ],
      },
    });
    return response.choices?.[0]?.message?.content;
  } catch (error) {
    throw toOpenAICompatibleError(error, options.serviceLabel);
  }
}

/** Anthropic's own Messages API, called directly from the browser with the user's own key. */
async function callAnthropic(apiKey: string, model: string, content: ChatContent): Promise<string | null> {
  const client = new Anthropic({ apiKey, dangerouslyAllowBrowser: true });
  const userContent: Anthropic.MessageParam["content"] = content.images?.length
    ? [
        ...content.images.map((image) => ({
          type: "image" as const,
          source: { type: "base64" as const, media_type: image.mediaType, data: image.base64 },
        })),
        { type: "text", text: content.text },
      ]
    : content.text;
  try {
    const response = await client.messages.create({
      model,
      max_tokens: 4096,
      system: content.systemPrompt,
      messages: [{ role: "user", content: userContent }],
    });
    const textBlock = response.content.find((block): block is Anthropic.TextBlock => block.type === "text");
    return textBlock?.text ?? null;
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) {
      throw new AIExtractionError("That Anthropic API key was rejected — check it in Settings.");
    }
    if (error instanceof Anthropic.RateLimitError) {
      throw new AIExtractionError("Rate limited by Anthropic — try again in a moment.");
    }
    if (error instanceof Anthropic.APIError) {
      throw new AIExtractionError(`Anthropic error: ${error.message}`);
    }
    throw new AIExtractionError(
      "Couldn't reach the Anthropic API — some networks or browser setups block direct API calls.",
    );
  }
}

/** Google's Gemini API, called directly from the browser via its REST endpoint (no bundled SDK here). */
async function callGemini(apiKey: string, model: string, content: ChatContent): Promise<string | null | undefined> {
  const parts: Record<string, unknown>[] = [{ text: content.text }];
  for (const image of content.images ?? []) {
    parts.push({ inline_data: { mime_type: image.mediaType, data: image.base64 } });
  }

  let response: Response;
  try {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: content.systemPrompt }] },
          contents: [{ role: "user", parts }],
        }),
      },
    );
  } catch {
    throw new AIExtractionError("Couldn't reach the Gemini API.");
  }

  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new AIExtractionError("That Gemini API key was rejected — check it in Settings.");
    }
    if (response.status === 429) {
      throw new AIExtractionError("Rate limited by Gemini — try again in a moment.");
    }
    throw new AIExtractionError(`Gemini error: HTTP ${response.status}`);
  }

  const data = (await response.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  return data.candidates?.[0]?.content?.parts?.[0]?.text;
}

/** Sends one chat request to whichever provider is currently active in Settings. */
async function callModel(content: ChatContent): Promise<string | null | undefined> {
  const settings = useAISettingsStore.getState();
  switch (settings.provider) {
    case "gateway":
      return callOpenAICompatible({
        baseURL: GATEWAY_BASE_URL,
        path: GATEWAY_CHAT_COMPLETIONS_PATH,
        apiKey: requireKey(settings.apiKey, "AI extraction gateway"),
        model: settings.model,
        content,
        serviceLabel: "the gateway",
      });
    case "openai":
      return callOpenAICompatible({
        baseURL: "https://api.openai.com/v1",
        path: CHAT_COMPLETIONS_PATH,
        apiKey: requireKey(settings.openaiApiKey, "OpenAI"),
        model: settings.openaiModel,
        content,
        serviceLabel: "OpenAI",
      });
    case "anthropic":
      return callAnthropic(requireKey(settings.anthropicApiKey, "Anthropic"), settings.anthropicModel, content);
    case "gemini":
      return callGemini(requireKey(settings.geminiApiKey, "Gemini"), settings.geminiModel, content);
    case "perplexity":
      if (content.images?.length) {
        throw new AIExtractionError(
          "Perplexity doesn't support reading screenshots — switch to a different provider in Settings, or paste the caption text instead.",
        );
      }
      return callOpenAICompatible({
        baseURL: PERPLEXITY_BASE_URL,
        path: CHAT_COMPLETIONS_PATH,
        apiKey: requireKey(settings.perplexityApiKey, "Perplexity"),
        model: settings.perplexityModel,
        content,
        serviceLabel: "Perplexity",
      });
  }
}

/** Parses the model's reply as the {places: [...]} shape. */
function parsePlacesResponse(content: string | null | undefined): AIExtractedPlace[] {
  const parsedJSON = parseJsonContent(content);
  const result = PlacesSchema.safeParse(parsedJSON);
  if (!result.success) {
    throw new AIExtractionError("The AI extraction service returned an unexpected response shape.");
  }
  return result.data.places;
}

/**
 * Extracts places directly from a caption screenshot via vision — combines
 * OCR and extraction in a single step, generally more accurate than running
 * local OCR first and parsing the result with regex.
 */
export async function extractPlacesFromImage(
  imageBase64: string,
  mediaType: ImageMediaType,
): Promise<AIExtractedPlace[]> {
  return extractPlacesFromImages([{ mediaType, base64: imageBase64 }]);
}

/**
 * Extracts places from one or more photos in a single AI request, so the
 * model can cross-reference them (e.g. a storefront sign for the name, a
 * menu photo for prices/items) into one consolidated result, rather than
 * merging independent per-photo extractions client-side.
 *
 * `isOnSitePhoto` picks the right prompt for what these photos actually
 * show — it can't be inferred from the photo count alone, since the
 * on-site flow can just as easily hand this a single photo (one storefront
 * shot) as the screenshot flow always does. Getting this wrong sends a
 * real on-site photo through wording written for an Instagram caption
 * screenshot ("extract every place recommended in this caption"), which
 * reads a sign or menu as if it were social copy and can come back empty.
 */
export async function extractPlacesFromImages(
  images: { mediaType: ImageMediaType; base64: string }[],
  isOnSitePhoto = false,
): Promise<AIExtractedPlace[]> {
  const text = isOnSitePhoto
    ? images.length > 1
      ? "These photos were taken in person at a single real place — extract one consolidated, " +
        "accurate result for it, cross-referencing all the photos (for example, a storefront sign " +
        "for the name and a menu photo for prices/items)."
      : "This photo was taken in person at a single real place (its storefront, sign, menu, or " +
        "interior) — extract one accurate result for it from whatever is written or shown, such as " +
        "its name and any menu items, prices, or hours visible."
    : "Extract every place recommended in this screenshot's caption.";
  const content = await callModel({ systemPrompt: SYSTEM_PROMPT, text, images });
  return parsePlacesResponse(content);
}

/**
 * Best-effort guess at a full address for each of the given place names,
 * using the model's general knowledge rather than anything extracted from
 * a caption — for places a caption named without ever giving an address.
 * Returns one entry per input name, in order; an entry is null where the
 * model wasn't confident enough to guess.
 */
export async function guessMissingAddresses(
  destination: string,
  placeNames: string[],
): Promise<(string | null)[]> {
  if (placeNames.length === 0) return [];
  const content = await callModel({
    systemPrompt: ADDRESS_GUESS_SYSTEM_PROMPT,
    text: `Destination: ${destination}\n\nPlaces:\n${placeNames.map((name, i) => `${i + 1}. ${name}`).join("\n")}`,
  });
  const parsedJSON = parseJsonContent(content);
  const result = AddressGuessSchema.safeParse(parsedJSON);
  if (!result.success) {
    throw new AIExtractionError("The AI extraction service returned an unexpected response shape.");
  }
  // Pad/truncate defensively in case the model didn't return exactly one
  // entry per input — a mismatched count shouldn't crash the merge back
  // into the candidate rows.
  return placeNames.map((_, i) => result.data.addresses[i] ?? null);
}

/**
 * Best-effort fallback for when ordinary geocoding fails on a place's own
 * address/name: asks AI for its single best guess at the nearest plausible
 * real address, using everything known about the place (its name, the
 * address that failed to geocode, and any other notes) rather than just
 * the name alone. Returns null when the model has no reasonable basis for
 * a guess, or when the guess call itself fails.
 */
export async function guessNearestAddress(
  destination: string,
  place: { name: string; address?: string | null; telephone?: string | null; notes?: string | null },
): Promise<string | null> {
  const details = [
    `Name: ${place.name}`,
    place.address ? `Address given (could not be located on a map): ${place.address}` : null,
    place.telephone ? `Phone: ${place.telephone}` : null,
    place.notes ? `Other notes: ${place.notes}` : null,
  ]
    .filter(Boolean)
    .join("\n");
  const content = await callModel({
    systemPrompt: NEAREST_LOCATION_SYSTEM_PROMPT,
    text: `Destination: ${destination}\n\n${details}`,
  });
  const parsedJSON = parseJsonContent(content);
  const result = NearestLocationSchema.safeParse(parsedJSON);
  if (!result.success) {
    throw new AIExtractionError("The AI extraction service returned an unexpected response shape.");
  }
  return result.data.address;
}

export function isSupportedImageMediaType(type: string): type is ImageMediaType {
  return type === "image/jpeg" || type === "image/png" || type === "image/gif" || type === "image/webp";
}

/** Reads a File as a base64 string (without the data: URL prefix). */
export function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      const base64 = result.slice(result.indexOf(",") + 1);
      resolve(base64);
    };
    reader.onerror = () => reject(reader.error ?? new Error("Failed to read file"));
    reader.readAsDataURL(file);
  });
}
