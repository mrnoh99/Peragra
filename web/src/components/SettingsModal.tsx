import { useMemo, useState } from "react";
import { Modal } from "./Modal";
import { GATEWAY_MODELS } from "../lib/gatewayModels";
import {
  DEFAULT_ANTHROPIC_MODEL,
  DEFAULT_GEMINI_MODEL,
  DEFAULT_OPENAI_MODEL,
  DEFAULT_PERPLEXITY_MODEL,
  useAISettingsStore,
  type AIProvider,
} from "../store/useAISettingsStore";
import { useMapSettingsStore, type MapProvider } from "../store/useMapSettingsStore";

const CUSTOM_MODEL_VALUE = "__custom__";

const PROVIDER_LABELS: Record<AIProvider, string> = {
  gateway: "Gateway (default)",
  anthropic: "Anthropic",
  openai: "OpenAI",
  gemini: "Gemini",
  perplexity: "Perplexity",
};

// Display order for the provider tab strip — gateway last, since it's the
// fallback rather than the first thing to reach for.
const PROVIDER_ORDER: AIProvider[] = ["anthropic", "openai", "gemini", "perplexity", "gateway"];

const ANTHROPIC_MODELS = [
  { id: "claude-sonnet-5", label: "Claude Sonnet 5" },
  { id: "claude-opus-5", label: "Claude Opus 5" },
];

/**
 * One provider's key + model fields. Keyed by provider from the caller so
 * switching providers remounts this with fresh local input state seeded
 * from that provider's own stored key/model, rather than carrying over
 * whatever was typed for the previous one.
 */
function ProviderFields({
  apiKey,
  setApiKey,
  model,
  setModel,
  defaultModel,
  knownModels,
  placeholder,
  helpText,
}: {
  apiKey: string | null;
  setApiKey: (key: string | null) => void;
  model: string;
  setModel: (model: string) => void;
  defaultModel: string;
  /** Empty means "free text only" — no dropdown, no Custom… option. */
  knownModels: readonly { id: string; label: string }[];
  placeholder: string;
  helpText: string;
}) {
  const [input, setInput] = useState(apiKey ?? "");
  const isKnownModel = useMemo(() => knownModels.some((m) => m.id === model), [knownModels, model]);
  const [modelSelectValue, setModelSelectValue] = useState(isKnownModel ? model : CUSTOM_MODEL_VALUE);
  const [customModelInput, setCustomModelInput] = useState(isKnownModel ? "" : model);

  return (
    <div>
      <input
        type="password"
        autoFocus
        value={input}
        onChange={(e) => setInput(e.target.value)}
        placeholder={placeholder}
        spellCheck={false}
        className="w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
      />
      <p className="mt-2 text-xs text-neutral-400">{helpText}</p>
      <div className="mt-2 flex gap-2">
        <button
          onClick={() => setApiKey(input)}
          className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600"
        >
          Save
        </button>
        {apiKey && (
          <button
            onClick={() => {
              setApiKey(null);
              setInput("");
            }}
            className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
          >
            Remove key
          </button>
        )}
      </div>

      <label className="mb-1 mt-4 block text-sm font-medium text-neutral-700">Model</label>
      {knownModels.length > 0 ? (
        <>
          <select
            value={modelSelectValue}
            onChange={(e) => {
              const value = e.target.value;
              setModelSelectValue(value);
              if (value !== CUSTOM_MODEL_VALUE) setModel(value);
            }}
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          >
            {knownModels.map((m) => (
              <option key={m.id} value={m.id}>
                {m.label}
              </option>
            ))}
            <option value={CUSTOM_MODEL_VALUE}>Custom…</option>
          </select>
          {modelSelectValue === CUSTOM_MODEL_VALUE && (
            <input
              value={customModelInput}
              onChange={(e) => {
                setCustomModelInput(e.target.value);
                setModel(e.target.value);
              }}
              placeholder="model-id"
              spellCheck={false}
              className="mt-2 w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          )}
        </>
      ) : (
        <input
          defaultValue={model}
          onChange={(e) => setModel(e.target.value || defaultModel)}
          placeholder="model-id"
          spellCheck={false}
          className="w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
        />
      )}
    </div>
  );
}

export function SettingsModal({ onClose }: { onClose: () => void }) {
  const provider = useAISettingsStore((s) => s.provider);
  const setProvider = useAISettingsStore((s) => s.setProvider);

  const gatewayApiKey = useAISettingsStore((s) => s.apiKey);
  const setGatewayApiKey = useAISettingsStore((s) => s.setApiKey);
  const gatewayModel = useAISettingsStore((s) => s.model);
  const setGatewayModel = useAISettingsStore((s) => s.setModel);

  const anthropicApiKey = useAISettingsStore((s) => s.anthropicApiKey);
  const setAnthropicApiKey = useAISettingsStore((s) => s.setAnthropicApiKey);
  const anthropicModel = useAISettingsStore((s) => s.anthropicModel);
  const setAnthropicModel = useAISettingsStore((s) => s.setAnthropicModel);

  const openaiApiKey = useAISettingsStore((s) => s.openaiApiKey);
  const setOpenaiApiKey = useAISettingsStore((s) => s.setOpenaiApiKey);
  const openaiModel = useAISettingsStore((s) => s.openaiModel);
  const setOpenaiModel = useAISettingsStore((s) => s.setOpenaiModel);

  const geminiApiKey = useAISettingsStore((s) => s.geminiApiKey);
  const setGeminiApiKey = useAISettingsStore((s) => s.setGeminiApiKey);
  const geminiModel = useAISettingsStore((s) => s.geminiModel);
  const setGeminiModel = useAISettingsStore((s) => s.setGeminiModel);

  const perplexityApiKey = useAISettingsStore((s) => s.perplexityApiKey);
  const setPerplexityApiKey = useAISettingsStore((s) => s.setPerplexityApiKey);
  const perplexityModel = useAISettingsStore((s) => s.perplexityModel);
  const setPerplexityModel = useAISettingsStore((s) => s.setPerplexityModel);

  const mapProvider = useMapSettingsStore((s) => s.mapProvider);
  const setMapProvider = useMapSettingsStore((s) => s.setMapProvider);
  const googleMapsApiKey = useMapSettingsStore((s) => s.googleMapsApiKey);
  const setGoogleMapsApiKey = useMapSettingsStore((s) => s.setGoogleMapsApiKey);
  const [googleKeyInput, setGoogleKeyInput] = useState(googleMapsApiKey ?? "");

  return (
    <Modal title="Settings" onClose={onClose} closeLabel="Close">
      <div className="space-y-6">
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            AI place extraction
          </label>
          <p className="mb-2 text-xs text-neutral-400">
            This app has no server — AI extraction calls the chosen provider directly from your
            browser, and any key you enter is stored only in this browser's local storage. Leave
            every key blank to skip AI — the free pattern-matching extraction still works without
            one.
          </p>

          <div className="mb-3 flex flex-wrap gap-1 rounded-lg border border-neutral-300 p-1 text-sm">
            {PROVIDER_ORDER.map((p) => (
              <button
                key={p}
                onClick={() => setProvider(p)}
                className={`flex-1 rounded-md px-2 py-1.5 text-xs font-medium ${
                  provider === p ? "bg-brand-500 text-white" : "text-neutral-600 hover:bg-neutral-50"
                }`}
              >
                {PROVIDER_LABELS[p]}
              </button>
            ))}
          </div>

          {provider === "gateway" && (
            <ProviderFields
              key="gateway"
              apiKey={gatewayApiKey}
              setApiKey={setGatewayApiKey}
              model={gatewayModel}
              setModel={setGatewayModel}
              defaultModel="claude-sonnet-5"
              knownModels={GATEWAY_MODELS}
              placeholder="API key"
              helpText="AI place extraction calls the gateway at factchat-cloud.mindlogic.ai directly from your browser using this key. This is a third-party gateway, not any provider's own API — your caption/screenshot data passes through it. The model list is from the gateway's own catalog — pick 'Custom…' for any other ID it supports."
            />
          )}
          {provider === "anthropic" && (
            <ProviderFields
              key="anthropic"
              apiKey={anthropicApiKey}
              setApiKey={setAnthropicApiKey}
              model={anthropicModel}
              setModel={setAnthropicModel}
              defaultModel={DEFAULT_ANTHROPIC_MODEL}
              knownModels={ANTHROPIC_MODELS}
              placeholder="sk-ant-..."
              helpText="Calls Anthropic's own API (api.anthropic.com) directly from your browser with your own Anthropic API key — bypasses the gateway entirely. Some networks or browser privacy settings can block direct cross-origin API calls; if extraction fails to reach it, try the gateway instead."
            />
          )}
          {provider === "openai" && (
            <ProviderFields
              key="openai"
              apiKey={openaiApiKey}
              setApiKey={setOpenaiApiKey}
              model={openaiModel}
              setModel={setOpenaiModel}
              defaultModel={DEFAULT_OPENAI_MODEL}
              knownModels={[]}
              placeholder="sk-..."
              helpText="Calls OpenAI's own API (api.openai.com) directly from your browser with your own OpenAI API key — bypasses the gateway entirely. Needs a vision-capable model (the default, gpt-4o, supports screenshots)."
            />
          )}
          {provider === "gemini" && (
            <ProviderFields
              key="gemini"
              apiKey={geminiApiKey}
              setApiKey={setGeminiApiKey}
              model={geminiModel}
              setModel={setGeminiModel}
              defaultModel={DEFAULT_GEMINI_MODEL}
              knownModels={[]}
              placeholder="AIzaSy..."
              helpText="Calls Google's Gemini API directly from your browser with your own Gemini API key (from Google AI Studio) — bypasses the gateway entirely."
            />
          )}
          {provider === "perplexity" && (
            <ProviderFields
              key="perplexity"
              apiKey={perplexityApiKey}
              setApiKey={setPerplexityApiKey}
              model={perplexityModel}
              setModel={setPerplexityModel}
              defaultModel={DEFAULT_PERPLEXITY_MODEL}
              knownModels={[]}
              placeholder="pplx-..."
              helpText="Calls Perplexity's own API directly from your browser with your own Perplexity API key. Perplexity has no vision support, so screenshot extraction is unavailable while it's selected — caption-text extraction still works."
            />
          )}
        </div>

        <div className="border-t border-neutral-100 pt-4">
          <label className="mb-1 block text-sm font-medium text-neutral-700">Map provider</label>
          <div className="mt-1 flex rounded-lg border border-neutral-300 p-1 text-sm">
            {(["free", "google"] as MapProvider[]).map((provider) => (
              <button
                key={provider}
                onClick={() => setMapProvider(provider)}
                className={`flex-1 rounded-md px-3 py-1.5 font-medium ${
                  mapProvider === provider ? "bg-brand-500 text-white" : "text-neutral-600"
                }`}
              >
                {provider === "free" ? "Free (OpenStreetMap)" : "Google Maps"}
              </button>
            ))}
          </div>

          {mapProvider === "google" ? (
            <>
              <input
                type="password"
                value={googleKeyInput}
                onChange={(e) => setGoogleKeyInput(e.target.value)}
                placeholder="AIzaSy..."
                spellCheck={false}
                className="mt-2 w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
              <p className="mt-2 text-xs text-neutral-400">
                Requires your own Google Maps API key (with the Maps JavaScript and Geocoding APIs
                enabled) from a Google Cloud project with billing set up — Google's free monthly
                credit covers light personal use. The map and address lookups call Google's APIs
                directly from your browser.
              </p>
              <div className="mt-2 flex gap-2">
                <button
                  onClick={() => setGoogleMapsApiKey(googleKeyInput)}
                  className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600"
                >
                  Save
                </button>
                {googleMapsApiKey && (
                  <button
                    onClick={() => {
                      setGoogleMapsApiKey(null);
                      setGoogleKeyInput("");
                    }}
                    className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
                  >
                    Remove key
                  </button>
                )}
              </div>
            </>
          ) : (
            <p className="mt-2 text-xs text-neutral-400">
              OpenStreetMap and Nominatim need no API key and no account — this is the default.
            </p>
          )}
        </div>
      </div>
    </Modal>
  );
}
