import { useState } from "react";
import { Modal } from "./Modal";
import { useAISettingsStore } from "../store/useAISettingsStore";

export function SettingsModal({ onClose }: { onClose: () => void }) {
  const apiKey = useAISettingsStore((s) => s.apiKey);
  const setApiKey = useAISettingsStore((s) => s.setApiKey);
  const [input, setInput] = useState(apiKey ?? "");

  return (
    <Modal title="AI settings" onClose={onClose}>
      <div className="space-y-4">
        <div>
          <label className="mb-1 block text-sm font-medium text-neutral-700">
            Anthropic API key <span className="font-normal text-neutral-400">(optional)</span>
          </label>
          <input
            type="password"
            autoFocus
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="sk-ant-..."
            spellCheck={false}
            className="w-full rounded-lg border border-neutral-300 px-3 py-2 font-mono text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <p className="mt-2 text-xs text-neutral-400">
            This app has no server — AI place extraction calls Anthropic's API directly from your
            browser using this key, and the key is stored only in this browser's local storage.
            Get one at{" "}
            <a
              href="https://console.anthropic.com/settings/keys"
              target="_blank"
              rel="noreferrer"
              className="text-brand-600 underline"
            >
              console.anthropic.com
            </a>
            . Leave blank to skip AI — the free pattern-matching extraction still works without a
            key.
          </p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => {
              setApiKey(input);
              onClose();
            }}
            className="flex-1 rounded-lg bg-brand-500 px-4 py-2 text-sm font-medium text-white hover:bg-brand-600"
          >
            Save
          </button>
          {apiKey && (
            <button
              onClick={() => {
                setApiKey(null);
                setInput("");
              }}
              className="rounded-lg border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
            >
              Remove key
            </button>
          )}
        </div>
      </div>
    </Modal>
  );
}
