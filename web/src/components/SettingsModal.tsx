import { useState } from "react";
import { Modal } from "./Modal";
import { useAISettingsStore } from "../store/useAISettingsStore";
import { useMapSettingsStore, type MapProvider } from "../store/useMapSettingsStore";

export function SettingsModal({ onClose }: { onClose: () => void }) {
  const apiKey = useAISettingsStore((s) => s.apiKey);
  const setApiKey = useAISettingsStore((s) => s.setApiKey);
  const [input, setInput] = useState(apiKey ?? "");

  const mapProvider = useMapSettingsStore((s) => s.mapProvider);
  const setMapProvider = useMapSettingsStore((s) => s.setMapProvider);
  const googleMapsApiKey = useMapSettingsStore((s) => s.googleMapsApiKey);
  const setGoogleMapsApiKey = useMapSettingsStore((s) => s.setGoogleMapsApiKey);
  const [googleKeyInput, setGoogleKeyInput] = useState(googleMapsApiKey ?? "");

  return (
    <Modal title="Settings" onClose={onClose}>
      <div className="space-y-6">
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            AI extraction API key <span className="font-normal text-neutral-400">(optional)</span>
          </label>
          <input
            type="password"
            autoFocus
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="API key"
            spellCheck={false}
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <p className="mt-2 text-xs text-neutral-400">
            This app has no server — AI place extraction calls the gateway at
            factchat-cloud.mindlogic.ai directly from your browser using this key, and the key is
            stored only in this browser's local storage. This is a third-party gateway, not
            Anthropic's own API — your caption/screenshot data passes through it. Leave blank to
            skip AI — the free pattern-matching extraction still works without a key.
          </p>
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
