import OpenAI from "openai";
import { z } from "zod";
import { useAISettingsStore } from "../store/useAISettingsStore";

// Routed through a third-party OpenAI-compatible gateway
// (factchat-cloud.mindlogic.ai) rather than Anthropic's own API — per
// explicit instruction. This means captions/screenshots sent for AI
// extraction pass through that gateway, not just Anthropic directly, and
// the API key entered in Settings is a key issued by that gateway, not an
// Anthropic key. Per the gateway's own docs, JSON mode / structured
// output isn't among its listed endpoints, so this prompts for JSON in
// plain chat-completion form and validates the response against the
// schema below rather than relying on a provider-specific extension.
const GATEWAY_BASE_URL = "https://factchat-cloud.mindlogic.ai/v1/gateway";

// The documented endpoint is "/v1/gateway/chat/completions/" — WITH a
// trailing slash. The openai SDK's own client.chat.completions.create()
// always requests the path without one (confirmed by testing against a
// local mock server), which risks a 404 or a broken POST-to-GET redirect
// on a Django-style backend that enforces trailing slashes. Calling the
// SDK's lower-level client.post() with the exact path sidesteps that.
const CHAT_COMPLETIONS_PATH = "/chat/completions/";

interface GatewayChatCompletionResponse {
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
    }),
  ),
});

export interface AIExtractedPlace {
  name: string;
  address: string | null;
}

export class AIExtractionError extends Error {}

type ImageMediaType = "image/jpeg" | "image/png" | "image/gif" | "image/webp";

const SYSTEM_PROMPT =
  "You extract place recommendations (restaurants, cafes, shops, attractions) from " +
  "an Instagram post's caption text or a screenshot of one. Return every distinct " +
  "place mentioned, each with its name and, if given, its full address exactly as " +
  "written. If no address is given for a place, use null — never guess or invent " +
  "one. If nothing in the text describes an actual place, return an empty list.\n\n" +
  "Respond with ONLY a single JSON object, no other text, no markdown code fence, " +
  'matching exactly this shape: {"places": [{"name": string, "address": string | null}]}';

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

function getClient(apiKey: string): OpenAI {
  return new OpenAI({ apiKey, baseURL: GATEWAY_BASE_URL, dangerouslyAllowBrowser: true });
}

function toAIExtractionError(error: unknown): AIExtractionError {
  if (error instanceof OpenAI.AuthenticationError) {
    return new AIExtractionError("That API key was rejected — check it in Settings.");
  }
  if (error instanceof OpenAI.RateLimitError) {
    return new AIExtractionError("Rate limited by the gateway — try again in a moment.");
  }
  if (error instanceof OpenAI.APIError) {
    return new AIExtractionError(`Gateway error: ${error.message}`);
  }
  return new AIExtractionError("Couldn't reach the AI extraction service.");
}

/**
 * Parses the model's reply as the {places: [...]} shape, tolerating a
 * markdown code fence around the JSON despite the prompt asking for none —
 * models routed through arbitrary gateways don't reliably follow that.
 */
function parsePlacesResponse(content: string | null | undefined): AIExtractedPlace[] {
  if (!content) {
    throw new AIExtractionError("The AI extraction service returned an empty response.");
  }
  const fenced = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  const jsonText = fenced ? fenced[1] : content;

  let parsedJSON: unknown;
  try {
    parsedJSON = JSON.parse(jsonText);
  } catch {
    throw new AIExtractionError("The AI extraction service didn't return valid JSON.");
  }

  const result = PlacesSchema.safeParse(parsedJSON);
  if (!result.success) {
    throw new AIExtractionError("The AI extraction service returned an unexpected response shape.");
  }
  return result.data.places;
}

/** Extracts places from pasted/OCR'd caption text using the user's own gateway API key. */
export async function extractPlacesFromText(
  apiKey: string,
  captionText: string,
): Promise<AIExtractedPlace[]> {
  const client = getClient(apiKey);
  try {
    const response = await client.post<GatewayChatCompletionResponse>(CHAT_COMPLETIONS_PATH, {
      body: {
        model: useAISettingsStore.getState().model,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: captionText },
        ],
      },
    });
    return parsePlacesResponse(response.choices?.[0]?.message?.content);
  } catch (error) {
    if (error instanceof AIExtractionError) throw error;
    throw toAIExtractionError(error);
  }
}

/**
 * Extracts places directly from a caption screenshot via vision — combines
 * OCR and extraction in a single step, generally more accurate than running
 * local OCR first and parsing the result with regex.
 */
export async function extractPlacesFromImage(
  apiKey: string,
  imageBase64: string,
  mediaType: ImageMediaType,
): Promise<AIExtractedPlace[]> {
  const client = getClient(apiKey);
  try {
    const response = await client.post<GatewayChatCompletionResponse>(CHAT_COMPLETIONS_PATH, {
      body: {
        model: useAISettingsStore.getState().model,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          {
            role: "user",
            content: [
              { type: "text", text: "Extract every place recommended in this screenshot's caption." },
              { type: "image_url", image_url: { url: `data:${mediaType};base64,${imageBase64}` } },
            ],
          },
        ],
      },
    });
    return parsePlacesResponse(response.choices?.[0]?.message?.content);
  } catch (error) {
    if (error instanceof AIExtractionError) throw error;
    throw toAIExtractionError(error);
  }
}

/**
 * Best-effort guess at a full address for each of the given place names,
 * using the model's general knowledge rather than anything extracted from
 * a caption — for places a caption named without ever giving an address.
 * Returns one entry per input name, in order; an entry is null where the
 * model wasn't confident enough to guess.
 */
export async function guessMissingAddresses(
  apiKey: string,
  destination: string,
  placeNames: string[],
): Promise<(string | null)[]> {
  if (placeNames.length === 0) return [];
  const client = getClient(apiKey);
  try {
    const response = await client.post<GatewayChatCompletionResponse>(CHAT_COMPLETIONS_PATH, {
      body: {
        model: useAISettingsStore.getState().model,
        messages: [
          { role: "system", content: ADDRESS_GUESS_SYSTEM_PROMPT },
          {
            role: "user",
            content: `Destination: ${destination}\n\nPlaces:\n${placeNames
              .map((name, i) => `${i + 1}. ${name}`)
              .join("\n")}`,
          },
        ],
      },
    });
    const content = response.choices?.[0]?.message?.content;
    if (!content) {
      throw new AIExtractionError("The AI extraction service returned an empty response.");
    }
    const fenced = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
    const jsonText = fenced ? fenced[1] : content;

    let parsedJSON: unknown;
    try {
      parsedJSON = JSON.parse(jsonText);
    } catch {
      throw new AIExtractionError("The AI extraction service didn't return valid JSON.");
    }

    const result = AddressGuessSchema.safeParse(parsedJSON);
    if (!result.success) {
      throw new AIExtractionError("The AI extraction service returned an unexpected response shape.");
    }
    // Pad/truncate defensively in case the model didn't return exactly one
    // entry per input — a mismatched count shouldn't crash the merge back
    // into the candidate rows.
    return placeNames.map((_, i) => result.data.addresses[i] ?? null);
  } catch (error) {
    if (error instanceof AIExtractionError) throw error;
    throw toAIExtractionError(error);
  }
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
