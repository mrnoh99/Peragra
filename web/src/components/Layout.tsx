import { useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { SettingsModal } from "./SettingsModal";

export function Layout({ children }: { children: ReactNode }) {
  const [showSettings, setShowSettings] = useState(false);

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-black/5 bg-white/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3 sm:px-6">
          <Link to="/" className="flex items-center gap-2">
            <img src={`${import.meta.env.BASE_URL}apple-touch-icon.png`} alt="" className="h-8 w-8 rounded-lg" />
            <span className="text-lg font-semibold tracking-tight text-neutral-900">
              Peragra
            </span>
          </Link>
          <div className="flex items-center gap-3">
            <p className="hidden text-sm text-neutral-500 sm:block">
              Turn saved Instagram spots into a real trip plan
            </p>
            <button
              onClick={() => setShowSettings(true)}
              className="grid h-8 w-8 place-items-center rounded-lg text-neutral-400 hover:bg-neutral-100 hover:text-neutral-600"
              aria-label="AI settings"
              title="AI settings"
            >
              ⚙️
            </button>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6 sm:px-6">{children}</main>
      <footer className="border-t border-black/5 py-4 text-center text-neutral-400">
        <p className="text-xs">Peragra — plan trips from the places you save</p>
        <p className="mt-1 text-[10px]">developed by JaiSung Noh, MD. · Version 1.0 · Build 2 · 2026</p>
      </footer>
      {showSettings && <SettingsModal onClose={() => setShowSettings(false)} />}
    </div>
  );
}
