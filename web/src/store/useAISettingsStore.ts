import { create } from "zustand";
import { persist } from "zustand/middleware";

interface AISettingsState {
  apiKey: string | null;
  setApiKey: (key: string | null) => void;
}

/**
 * The user's own Anthropic API key, stored only in this browser's
 * localStorage. This app has no backend — AI extraction calls Anthropic's
 * API directly from the client, so no key is ever sent anywhere but
 * Anthropic. Leaving this unset just disables the AI extraction option;
 * the free pattern-matching extraction always works.
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
