import type { SharedPlaceCandidate } from "./sharedPlaceImport";

// A share_target navigation (see App.tsx) is always a fresh full page
// load — the browser navigates to the action URL as a real GET request,
// remounting the whole app — so a plain module-level variable is enough
// to hand the parsed candidate from App.tsx's mount effect to the "From
// Map" trip page's first render, without round-tripping it through
// router state (which would need clearing afterward to stop a later
// back-navigation from reopening the same import).
let pending: SharedPlaceCandidate | null = null;

export function setPendingSharedPlace(candidate: SharedPlaceCandidate): void {
  pending = candidate;
}

/** Reads and clears in one step — meant to be read exactly once, in the
 *  destination page's initial render right after the navigation that
 *  followed setPendingSharedPlace. */
export function takePendingSharedPlace(): SharedPlaceCandidate | null {
  const value = pending;
  pending = null;
  return value;
}
