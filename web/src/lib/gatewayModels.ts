/**
 * Model IDs available on the factchat-cloud.mindlogic.ai gateway, as listed
 * on its own "API Gateway" docs page. Not necessarily exhaustive — the
 * Settings model picker also accepts a custom ID for anything not listed
 * here (the gateway may add models this list doesn't know about).
 */
export const GATEWAY_MODELS = [
  { id: "claude-sonnet-5", label: "Claude Sonnet 5" },
  { id: "claude-opus-5", label: "Claude Opus 5" },
  { id: "claude-fable-5-1", label: "Claude Fable 5.1" },
  { id: "claude-fable-5", label: "Claude Fable 5" },
  { id: "gpt-5.6-luna", label: "GPT-5.6 Luna" },
  { id: "gpt-5.6-terra", label: "GPT-5.6 Terra" },
  { id: "gpt-5.6-sol", label: "GPT-5.6 Sol" },
  { id: "gpt-5.5", label: "GPT-5.5" },
] as const;

export const DEFAULT_GATEWAY_MODEL = "claude-sonnet-5";
