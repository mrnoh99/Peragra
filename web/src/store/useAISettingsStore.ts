import { create } from "zustand";
import { persist } from "zustand/middleware";
import { DEFAULT_GATEWAY_MODEL } from "../lib/gatewayModels";

export type AIProvider = "gateway" | "anthropic" | "openai" | "gemini" | "perplexity";

export const DEFAULT_ANTHROPIC_MODEL = "claude-sonnet-5";
export const DEFAULT_OPENAI_MODEL = "gpt-4o";
export const DEFAULT_GEMINI_MODEL = "gemini-2.0-flash";
export const DEFAULT_PERPLEXITY_MODEL = "sonar";

interface AISettingsState {
  provider: AIProvider;
  setProvider: (provider: AIProvider) => void;

  // The default: routed through the factchat-cloud.mindlogic.ai gateway.
  apiKey: string | null;
  model: string;
  setApiKey: (key: string | null) => void;
  setModel: (model: string) => void;

  // Direct providers — each call Anthropic/OpenAI/Google/Perplexity's own
  // API straight from the browser with the user's own key for that
  // provider, bypassing the gateway entirely.
  anthropicApiKey: string | null;
  anthropicModel: string;
  setAnthropicApiKey: (key: string | null) => void;
  setAnthropicModel: (model: string) => void;

  openaiApiKey: string | null;
  openaiModel: string;
  setOpenaiApiKey: (key: string | null) => void;
  setOpenaiModel: (model: string) => void;

  geminiApiKey: string | null;
  geminiModel: string;
  setGeminiApiKey: (key: string | null) => void;
  setGeminiModel: (model: string) => void;

  perplexityApiKey: string | null;
  perplexityModel: string;
  setPerplexityApiKey: (key: string | null) => void;
  setPerplexityModel: (model: string) => void;
}

function trimmedOrNull(value: string | null): string | null {
  return value && value.trim() ? value.trim() : null;
}

/**
 * The user's own API key (and chosen model/provider) for AI place
 * extraction, stored only in this browser's localStorage. This app has no
 * backend — AI extraction calls the chosen provider directly from the
 * client. The default provider ("gateway") routes through a third-party
 * OpenAI-compatible gateway at factchat-cloud.mindlogic.ai (see
 * lib/aiExtract.ts); the others call Anthropic/OpenAI/Google/Perplexity's
 * own API directly with the user's own key for that provider. Leaving the
 * active provider's key unset just disables the AI extraction option; the
 * free pattern-matching extraction always works.
 */
export const useAISettingsStore = create<AISettingsState>()(
  persist(
    (set) => ({
      provider: "gateway",
      setProvider: (provider) => set({ provider }),

      apiKey: null,
      model: DEFAULT_GATEWAY_MODEL,
      setApiKey: (key) => set({ apiKey: trimmedOrNull(key) }),
      setModel: (model) => set({ model: model.trim() || DEFAULT_GATEWAY_MODEL }),

      anthropicApiKey: null,
      anthropicModel: DEFAULT_ANTHROPIC_MODEL,
      setAnthropicApiKey: (key) => set({ anthropicApiKey: trimmedOrNull(key) }),
      setAnthropicModel: (model) => set({ anthropicModel: model.trim() || DEFAULT_ANTHROPIC_MODEL }),

      openaiApiKey: null,
      openaiModel: DEFAULT_OPENAI_MODEL,
      setOpenaiApiKey: (key) => set({ openaiApiKey: trimmedOrNull(key) }),
      setOpenaiModel: (model) => set({ openaiModel: model.trim() || DEFAULT_OPENAI_MODEL }),

      geminiApiKey: null,
      geminiModel: DEFAULT_GEMINI_MODEL,
      setGeminiApiKey: (key) => set({ geminiApiKey: trimmedOrNull(key) }),
      setGeminiModel: (model) => set({ geminiModel: model.trim() || DEFAULT_GEMINI_MODEL }),

      perplexityApiKey: null,
      perplexityModel: DEFAULT_PERPLEXITY_MODEL,
      setPerplexityApiKey: (key) => set({ perplexityApiKey: trimmedOrNull(key) }),
      setPerplexityModel: (model) => set({ perplexityModel: model.trim() || DEFAULT_PERPLEXITY_MODEL }),
    }),
    { name: "peragra-ai-settings" },
  ),
);

/** The API key for whichever provider is currently active, or null if unset. */
export function selectActiveApiKey(s: AISettingsState): string | null {
  switch (s.provider) {
    case "gateway":
      return s.apiKey;
    case "anthropic":
      return s.anthropicApiKey;
    case "openai":
      return s.openaiApiKey;
    case "gemini":
      return s.geminiApiKey;
    case "perplexity":
      return s.perplexityApiKey;
  }
}
