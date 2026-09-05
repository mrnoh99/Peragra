import { useRef, useMemo, useState } from "react";
import { Modal } from "./Modal";
import { buildBackup, parseBackup, saveBackupFile } from "../lib/backup";
import {
  chooseAutoBackupFolder,
  forgetAutoBackupFolder,
  isAutoBackupSupported,
  reauthorizeBackupFolder,
  runAutoBackupNow,
} from "../lib/autoBackup";
import { GATEWAY_MODELS } from "../lib/gatewayModels";
import { useStore } from "../store/useStore";
import {
  AI_EXTRACTION_LANGUAGES,
  DEFAULT_ANTHROPIC_MODEL,
  DEFAULT_GEMINI_MODEL,
  DEFAULT_OPENAI_MODEL,
  DEFAULT_PERPLEXITY_MODEL,
  useAISettingsStore,
  type AIProvider,
} from "../store/useAISettingsStore";
import { useMapSettingsStore, type MapProvider } from "../store/useMapSettingsStore";
import { useBackupSettingsStore, type AutoBackupInterval } from "../store/useBackupSettingsStore";

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

  const extractionLanguage = useAISettingsStore((s) => s.extractionLanguage);
  const setExtractionLanguage = useAISettingsStore((s) => s.setExtractionLanguage);

  const mapProvider = useMapSettingsStore((s) => s.mapProvider);
  const setMapProvider = useMapSettingsStore((s) => s.setMapProvider);
  const googleMapsApiKey = useMapSettingsStore((s) => s.googleMapsApiKey);
  const setGoogleMapsApiKey = useMapSettingsStore((s) => s.setGoogleMapsApiKey);
  const [googleKeyInput, setGoogleKeyInput] = useState(googleMapsApiKey ?? "");
  const naverClientId = useMapSettingsStore((s) => s.naverClientId);
  const setNaverClientId = useMapSettingsStore((s) => s.setNaverClientId);
  const [naverKeyInput, setNaverKeyInput] = useState(naverClientId ?? "");

  const [backupMessage, setBackupMessage] = useState<string | null>(null);
  const restoreInputRef = useRef<HTMLInputElement>(null);

  const autoBackupEnabled = useBackupSettingsStore((s) => s.autoBackupEnabled);
  const setAutoBackupEnabled = useBackupSettingsStore((s) => s.setAutoBackupEnabled);
  const autoBackupIntervalDays = useBackupSettingsStore((s) => s.autoBackupIntervalDays);
  const setAutoBackupIntervalDays = useBackupSettingsStore((s) => s.setAutoBackupIntervalDays);
  const backupFolderName = useBackupSettingsStore((s) => s.backupFolderName);
  const lastAutoBackupAt = useBackupSettingsStore((s) => s.lastAutoBackupAt);
  const needsReauthorization = useBackupSettingsStore((s) => s.needsReauthorization);
  const [autoBackupBusy, setAutoBackupBusy] = useState(false);

  async function handleBackup() {
    const { trips, places, collections } = useStore.getState();
    const data = buildBackup(trips, places, collections);
    try {
      const result = await saveBackupFile(data);
      setBackupMessage(result === "cancelled" ? null : "Backup saved.");
    } catch {
      setBackupMessage("Couldn't save the backup.");
    }
  }

  async function handleChooseAutoBackupFolder() {
    setAutoBackupBusy(true);
    try {
      const name = await chooseAutoBackupFolder();
      if (name) setAutoBackupEnabled(true);
    } catch {
      setBackupMessage("Couldn't set up that backup folder.");
    } finally {
      setAutoBackupBusy(false);
    }
  }

  async function handleReauthorize() {
    setAutoBackupBusy(true);
    try {
      const granted = await reauthorizeBackupFolder();
      if (!granted) setBackupMessage("Access wasn't granted — automatic backups stay paused.");
    } finally {
      setAutoBackupBusy(false);
    }
  }

  async function handleBackUpNow() {
    setAutoBackupBusy(true);
    try {
      const { trips, places, collections } = useStore.getState();
      const result = await runAutoBackupNow(trips, places, collections);
      setBackupMessage(
        result === "saved"
          ? "Backed up to your chosen folder."
          : result === "needs-permission"
            ? "Access to that folder needs to be re-granted below."
            : "No backup folder set.",
      );
    } catch {
      setBackupMessage("Couldn't write to that backup folder.");
    } finally {
      setAutoBackupBusy(false);
    }
  }

  function handleRestoreFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (restoreInputRef.current) restoreInputRef.current.value = "";
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const data = parseBackup(String(reader.result));
        const current = useStore.getState();
        const confirmed = confirm(
          `Replace all ${current.trips.length} current board${current.trips.length === 1 ? "" : "s"} and ${current.places.length} saved place${current.places.length === 1 ? "" : "s"} with the ${data.trips.length} board${data.trips.length === 1 ? "" : "s"} and ${data.places.length} saved place${data.places.length === 1 ? "" : "s"} in this backup? This can't be undone.`,
        );
        if (!confirmed) return;
        useStore.setState({ trips: data.trips, places: data.places, collections: data.collections });
        setBackupMessage("Restored from backup.");
      } catch (err) {
        setBackupMessage(err instanceof Error ? err.message : "Couldn't read that file.");
      }
    };
    reader.readAsText(file);
  }

  const [showHelp, setShowHelp] = useState(false);
  if (showHelp) {
    return <HelpModal onClose={() => setShowHelp(false)} />;
  }

  return (
    <Modal title="Settings" onClose={onClose} closeLabel="Close">
      <div className="space-y-6">
        <button
          onClick={() => setShowHelp(true)}
          className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
        >
          📖 User Guide
        </button>

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

          <label className="mb-1 mt-4 block text-sm font-medium text-neutral-700">
            AI extracted info language
          </label>
          <p className="mb-2 text-xs text-neutral-400">
            Language for the notes AI extracts from photos and screenshots. Names, addresses, and
            phone numbers are always kept exactly as written. This app's own menus and buttons
            always stay in English.
          </p>
          <select
            value={extractionLanguage}
            onChange={(e) => setExtractionLanguage(e.target.value)}
            aria-label="AI extracted info language"
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          >
            {AI_EXTRACTION_LANGUAGES.map((l) => (
              <option key={l.code} value={l.code}>
                {l.label}
              </option>
            ))}
          </select>
        </div>

        <div className="border-t border-neutral-100 pt-4">
          <label className="mb-1 block text-sm font-medium text-neutral-700">Map provider</label>
          <div className="mt-1 flex rounded-lg border border-neutral-300 p-1 text-sm">
            {(["free", "google", "naver"] as MapProvider[]).map((provider) => (
              <button
                key={provider}
                onClick={() => setMapProvider(provider)}
                className={`flex-1 rounded-md px-2 py-1.5 text-xs font-medium ${
                  mapProvider === provider ? "bg-brand-500 text-white" : "text-neutral-600"
                }`}
              >
                {provider === "free" ? "Free (OpenStreetMap)" : provider === "google" ? "Google Maps" : "Naver Maps"}
              </button>
            ))}
          </div>

          {mapProvider === "google" && (
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
          )}

          {mapProvider === "naver" && (
            <>
              <input
                type="password"
                value={naverKeyInput}
                onChange={(e) => setNaverKeyInput(e.target.value)}
                placeholder="Client ID"
                spellCheck={false}
                aria-label="Naver Maps Client ID"
                className="mt-2 w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
              <p className="mt-2 text-xs text-neutral-400">
                Requires your own free Naver Cloud Platform Maps Client ID (Console →
                AI·NAVER API → Maps), with this site's domain registered under it — the most
                accurate geocoder for Korean addresses. The map and address lookups call Naver's
                API directly from your browser.
              </p>
              <div className="mt-2 flex gap-2">
                <button
                  onClick={() => setNaverClientId(naverKeyInput)}
                  className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600"
                >
                  Save
                </button>
                {naverClientId && (
                  <button
                    onClick={() => {
                      setNaverClientId(null);
                      setNaverKeyInput("");
                    }}
                    className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
                  >
                    Remove Client ID
                  </button>
                )}
              </div>
            </>
          )}

          {mapProvider === "free" && (
            <p className="mt-2 text-xs text-neutral-400">
              OpenStreetMap and Nominatim need no API key and no account — this is the default.
            </p>
          )}
        </div>

        <div className="border-t border-neutral-100 pt-4">
          <label className="mb-1 block text-sm font-medium text-neutral-700">Data</label>
          <p className="mb-2 text-xs text-neutral-400">
            Back up every board and place to a file you choose, or restore from one —
            restoring replaces everything currently in the app.
          </p>
          <div className="flex flex-wrap gap-2">
            <button
              onClick={handleBackup}
              className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600"
            >
              Back up data
            </button>
            <input
              ref={restoreInputRef}
              type="file"
              accept="application/json"
              onChange={handleRestoreFile}
              className="hidden"
              id="restore-backup-input"
            />
            <label
              htmlFor="restore-backup-input"
              className="cursor-pointer rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50"
            >
              Restore from backup
            </label>
          </div>
          {backupMessage && <p className="mt-2 text-xs text-neutral-400">{backupMessage}</p>}

          {isAutoBackupSupported() ? (
            <div className="mt-4 border-t border-neutral-100 pt-3">
              <label className="mb-1 block text-sm font-medium text-neutral-700">Automatic backups</label>
              {!backupFolderName ? (
                <>
                  <p className="mb-2 text-xs text-neutral-400">
                    Pick a folder once, and Peragra keeps writing fresh backups there for you —
                    checked whenever you open the app, no more than once per the interval below.
                  </p>
                  <button
                    onClick={handleChooseAutoBackupFolder}
                    disabled={autoBackupBusy}
                    className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Choose backup folder…
                  </button>
                </>
              ) : (
                <>
                  <p className="mb-2 text-xs text-neutral-500">
                    Folder: <span className="font-medium text-neutral-700">{backupFolderName}</span>
                  </p>
                  <label className="mb-2 flex items-center gap-2 text-xs text-neutral-600">
                    <input
                      type="checkbox"
                      checked={autoBackupEnabled}
                      onChange={(e) => setAutoBackupEnabled(e.target.checked)}
                    />
                    Back up automatically
                  </label>
                  <div className="mb-2 flex items-center gap-2 text-xs text-neutral-600">
                    <span>Every</span>
                    <div className="flex rounded-lg border border-neutral-300 p-0.5">
                      {([1, 7] as AutoBackupInterval[]).map((days) => (
                        <button
                          key={days}
                          onClick={() => setAutoBackupIntervalDays(days)}
                          className={`rounded-md px-2 py-1 font-medium ${
                            autoBackupIntervalDays === days ? "bg-brand-500 text-white" : "text-neutral-600"
                          }`}
                        >
                          {days === 1 ? "Day" : "Week"}
                        </button>
                      ))}
                    </div>
                  </div>
                  {lastAutoBackupAt && (
                    <p className="mb-2 text-xs text-neutral-400">
                      Last backup: {new Date(lastAutoBackupAt).toLocaleString()}
                    </p>
                  )}
                  {needsReauthorization && (
                    <p className="mb-2 text-xs text-amber-600">
                      Access to this folder needs to be re-granted before backups can continue.
                    </p>
                  )}
                  <div className="flex flex-wrap gap-2">
                    {needsReauthorization && (
                      <button
                        onClick={handleReauthorize}
                        disabled={autoBackupBusy}
                        className="rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-40"
                      >
                        Re-allow access
                      </button>
                    )}
                    <button
                      onClick={handleBackUpNow}
                      disabled={autoBackupBusy}
                      className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Back up now
                    </button>
                    <button
                      onClick={handleChooseAutoBackupFolder}
                      disabled={autoBackupBusy}
                      className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Change folder
                    </button>
                    <button
                      onClick={() => void forgetAutoBackupFolder()}
                      disabled={autoBackupBusy}
                      className="rounded-lg border border-neutral-300 px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-neutral-50 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Turn off
                    </button>
                  </div>
                </>
              )}
            </div>
          ) : (
            <p className="mt-4 border-t border-neutral-100 pt-3 text-xs text-neutral-400">
              Automatic backups need a Chromium-based browser (Chrome, Edge) — not supported here.
              Use "Back up data" above instead.
            </p>
          )}
        </div>
      </div>
    </Modal>
  );
}

function HelpModal({ onClose }: { onClose: () => void }) {
  return (
    <Modal title="User Guide" onClose={onClose} closeLabel="Back">
      <div className="space-y-4 text-sm text-neutral-700">
        <Section title="Boards">
          Your Boards lists each board you're organizing (what used to be called a "trip") — a
          board is a destination, and the places you save inside it. Tap + New board to create
          one, and the pencil next to its name to rename it.
        </Section>
        <Section title="Adding saved places">
          Inside a board, tap + Add Places. Paste an Instagram caption to auto-fill a name and
          address, upload a screenshot for AI to read, or use Upload On-Site Photos / Take Photo
          Here to log a place you're standing at right now — that marks it Visited automatically,
          timestamped to the photo.
        </Section>
        <Section title="Correcting a saved place">
          When editing a place, upload a screenshot of its info card from a map app (Google Maps,
          Naver Map, Kakao Map, ...) and AI reads its name, address, and phone off the screen.
          Unlike the other photo options, this can correct a name or address that's already
          filled in — review the result before applying it.
        </Section>
        <Section title="Organizing">
          Star a place to favorite it, tap the checkmark to mark it visited, or make your own
          custom list. Search, filter by category, and sort by name or by distance from a place
          you pick.
        </Section>
        <Section title="Open in Map">
          Every place has an Open in Map menu: Google Maps always, plus Naver Map, Kakao Map and
          Tmap when that place is in Korea.
        </Section>
        <Section title="All Places">
          See and edit every saved place across every board in one combined list, from the All
          Places link on Your Boards.
        </Section>
        <Section title="AI place extraction">
          Optional. Add an API key below (Gateway, Anthropic, OpenAI, Gemini, or Perplexity) to
          let AI read screenshots and photos and fill in details. Without one, pasted captions
          are still parsed with free pattern-matching. The AI extracted info language setting
          controls what language AI writes extracted notes in — names, addresses, and phone
          numbers are always kept exactly as written.
        </Section>
        <Section title="Map provider">
          Free (OpenStreetMap) needs no key. Switch to Google Maps for a nicer map, or Naver Maps
          for the most accurate geocoding in Korea, if you add your own key/Client ID.
        </Section>
        <Section title="Backup & Restore">
          Back up every board and place to a file you choose, and restore from one later.
          Automatic backups (Chrome/Edge) let you pick a folder once and Peragra keeps a fresh
          backup there for you, checked daily or weekly whenever you open the app.
        </Section>
        <div className="border-t border-neutral-100 pt-3 text-xs text-neutral-400">
          Peragra — developed by JaiSung Noh, MD. · Version 1.0 · Build 3 · 2026
        </div>
      </div>
    </Modal>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="mb-0.5 font-semibold text-neutral-900">{title}</h3>
      <p className="text-neutral-500">{children}</p>
    </div>
  );
}
