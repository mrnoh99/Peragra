import { create } from "zustand";
import { persist } from "zustand/middleware";

interface AISettingsState {
  apiKey: string | null;
  setApiKey: (key: string | null) => void;
}

/**
 * The user's own API key for the AI extraction gateway (see
 * lib/aiExtract.ts — a third-party OpenAI-compatible gateway at
 * factchat-cloud.mindlogic.ai, not Anthropic's own API), stored only in
 * this browser's localStorage. This app has no backend — AI extraction
 * calls that gateway directly from the client. Leaving this unset just
 * disables the AI extraction option; the free pattern-matching extraction
 * always works.
 */
export const useAISettingsStore = create<AISettingsState>()(
  persist(
    (set) => ({
      apiKey: null,
      setApiKey: (key) => set({ apiKey: key && key.trim() ? key.trim() : null }),
    }),
    { name: "peragra-ai-settings" },
  ),
);
