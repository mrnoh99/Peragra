import OpenAI from "openai";
import { z } from "zod";

// Routed through a third-party OpenAI-compatible gateway
// (factchat-cloud.mindlogic.ai) rather than Anthropic's own API — per
// explicit instruction. This means captions/screenshots sent for AI
// extraction pass through that gateway, not just Anthropic directly, and
// the API key entered in Settings is a key issued by that gateway, not an
// Anthropic key. The gateway's actual feature support (vision passthrough,
// JSON mode) is undocumented from here, so this prompts for JSON in plain
// chat-completion form and validates the response against the schema below
// rather than relying on any provider-specific structured-output extension.
const GATEWAY_BASE_URL = "https://factchat-cloud.mindlogic.ai/v1/gateway";
const GATEWAY_MODEL = "claude-sonnet-5";

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
    const response = await client.chat.completions.create({
      model: GATEWAY_MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: captionText },
      ],
    });
    return parsePlacesResponse(response.choices[0]?.message.content);
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
    const response = await client.chat.completions.create({
      model: GATEWAY_MODEL,
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
    });
    return parsePlacesResponse(response.choices[0]?.message.content);
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
