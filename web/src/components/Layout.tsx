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
            <span className="grid h-8 w-8 place-items-center rounded-lg bg-brand-500 text-sm font-bold text-white">
              P
            </span>
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
      <footer className="border-t border-black/5 py-4 text-center text-xs text-neutral-400">
        Peragra — plan trips from the places you save
      </footer>
      {showSettings && <SettingsModal onClose={() => setShowSettings(false)} />}
    </div>
  );
}
