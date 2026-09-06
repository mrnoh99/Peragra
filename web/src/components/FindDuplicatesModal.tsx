import { useMemo, useState } from "react";
import { findDuplicateGroups } from "../lib/duplicatePlaces";
import { useStore } from "../store/useStore";
import type { Place } from "../types";
import { Modal } from "./Modal";

/** Scans one board's places for likely duplicates and lets the user review
 *  each group before merging it — picking which copy stays as the
 *  "primary" (keeping its own name/category/coordinates, but filling in
 *  anything only a duplicate had) and deleting the rest. Groups are found
 *  fresh from the store on every render, so a merged group disappears from
 *  the list immediately rather than needing a re-scan. */
export function FindDuplicatesModal({ places, onClose }: { places: Place[]; onClose: () => void }) {
  const mergePlaces = useStore((s) => s.mergePlaces);
  const [primaryByGroup, setPrimaryByGroup] = useState<Record<number, string>>({});
  const [mergedGroupIndexes, setMergedGroupIndexes] = useState<Set<number>>(new Set());

  const groups = useMemo(() => findDuplicateGroups(places), [places]);

  function primaryFor(groupIndex: number, group: Place[]): string {
    return primaryByGroup[groupIndex] ?? group[0].id;
  }

  function merge(groupIndex: number, group: Place[]) {
    const primaryId = primaryFor(groupIndex, group);
    const duplicateIds = group.map((p) => p.id).filter((id) => id !== primaryId);
    mergePlaces(primaryId, duplicateIds);
    setMergedGroupIndexes((prev) => new Set(prev).add(groupIndex));
  }

  const remainingGroups = groups.filter((_, i) => !mergedGroupIndexes.has(i));

  return (
    <Modal title="Find duplicates" onClose={onClose}>
      {groups.length === 0 ? (
        <p className="text-sm text-neutral-500">
          No likely duplicates found on this board — places need a matching name plus a nearby
          location or address to be flagged.
        </p>
      ) : remainingGroups.length === 0 ? (
        <p className="text-sm text-neutral-500">All found duplicates have been merged.</p>
      ) : (
        <div className="space-y-5">
          <p className="text-sm text-neutral-500">
            Found {remainingGroups.length} group{remainingGroups.length === 1 ? "" : "s"} of places
            that look like the same spot saved more than once. Pick which one to keep, then merge —
            the others' notes, phone and links are folded in before they're removed.
          </p>
          {groups.map((group, groupIndex) => {
            if (mergedGroupIndexes.has(groupIndex)) return null;
            const primaryId = primaryFor(groupIndex, group);
            return (
              <div key={groupIndex} className="rounded-xl border border-neutral-200 p-3">
                <div className="space-y-1.5">
                  {group.map((place) => (
                    <label
                      key={place.id}
                      className={`flex cursor-pointer items-start gap-2 rounded-lg px-2 py-1.5 text-sm ${
                        place.id === primaryId ? "bg-brand-50" : "hover:bg-neutral-50"
                      }`}
                    >
                      <input
                        type="radio"
                        name={`primary-${groupIndex}`}
                        checked={place.id === primaryId}
                        onChange={() =>
                          setPrimaryByGroup((prev) => ({ ...prev, [groupIndex]: place.id }))
                        }
                        className="mt-1"
                      />
                      <span>
                        <span className="font-medium text-neutral-800">{place.name}</span>
                        {place.address && (
                          <span className="block text-xs text-neutral-500">{place.address}</span>
                        )}
                      </span>
                    </label>
                  ))}
                </div>
                <button
                  onClick={() => merge(groupIndex, group)}
                  className="mt-2 rounded-lg bg-brand-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-brand-600"
                >
                  Merge into "{group.find((p) => p.id === primaryId)?.name}"
                </button>
              </div>
            );
          })}
        </div>
      )}
    </Modal>
  );
}
