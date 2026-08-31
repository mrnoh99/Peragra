import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";

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
  "one. If nothing in the text describes an actual place, return an empty list.";

function getClient(apiKey: string): Anthropic {
  return new Anthropic({ apiKey, dangerouslyAllowBrowser: true });
}

function toAIExtractionError(error: unknown): AIExtractionError {
  if (error instanceof Anthropic.AuthenticationError) {
    return new AIExtractionError("That API key was rejected — check it in Settings.");
  }
  if (error instanceof Anthropic.RateLimitError) {
    return new AIExtractionError("Rate limited by Anthropic — try again in a moment.");
  }
  if (error instanceof Anthropic.APIError) {
    return new AIExtractionError(`Anthropic API error: ${error.message}`);
  }
  return new AIExtractionError("Couldn't reach the AI extraction service.");
}

/** Extracts places from pasted/OCR'd caption text using the user's own Anthropic API key. */
export async function extractPlacesFromText(
  apiKey: string,
  captionText: string,
): Promise<AIExtractedPlace[]> {
  const client = getClient(apiKey);
  try {
    const response = await client.messages.parse({
      model: "claude-opus-5",
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: captionText }],
      output_config: { format: zodOutputFormat(PlacesSchema) },
    });
    return response.parsed_output?.places ?? [];
  } catch (error) {
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
    const response = await client.messages.parse({
      model: "claude-opus-5",
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mediaType, data: imageBase64 } },
            { type: "text", text: "Extract every place recommended in this screenshot's caption." },
          ],
        },
      ],
      output_config: { format: zodOutputFormat(PlacesSchema) },
    });
    return response.parsed_output?.places ?? [];
  } catch (error) {
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
