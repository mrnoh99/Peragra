import type { ReactNode } from "react";

export function Modal({
  title,
  onClose,
  children,
  closeLabel,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  /** Text for the close control instead of the default "✕" icon. */
  closeLabel?: string;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onClick={onClose}
    >
      <div
        className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-white p-6 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-neutral-900">{title}</h2>
          {closeLabel ? (
            <button
              onClick={onClose}
              className="rounded-lg px-3 py-1 text-sm font-medium text-neutral-500 hover:bg-neutral-100 hover:text-neutral-700"
            >
              {closeLabel}
            </button>
          ) : (
            <button
              onClick={onClose}
              className="grid h-8 w-8 place-items-center rounded-full text-neutral-400 hover:bg-neutral-100 hover:text-neutral-700"
              aria-label="Close"
            >
              ✕
            </button>
          )}
        </div>
        {children}
      </div>
    </div>
  );
}
