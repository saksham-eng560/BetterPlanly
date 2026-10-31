/** "Reduce transparency" preference.
 *
 * Safari has no `prefers-reduced-transparency`, so the app mirrors it with a switch that sets
 * `<html data-transparency="reduced|full">` (base.css swaps every glass tier for its opaque twin).
 * No stored choice means "follow the system". */

import { useState } from "react";

type Choice = "reduced" | "full";

const KEY = "planly:transparency";
const QUERY = "(prefers-reduced-transparency: reduce)";

function stored(): Choice | null {
  try {
    const value = localStorage.getItem(KEY);
    return value === "reduced" || value === "full" ? value : null;
  } catch {
    return null;
  }
}

function apply(choice: Choice | null) {
  const root = document.documentElement;
  if (choice) root.dataset.transparency = choice;
  else delete root.dataset.transparency;
}

function systemReduces(): boolean {
  return typeof window.matchMedia === "function" && window.matchMedia(QUERY).matches;
}

/** Call once before the first render, so glass never flashes on for someone who turned it off. */
export function initTransparency() {
  apply(stored());
}

export function useReducedTransparency(): [boolean, (reduced: boolean) => void] {
  const [reduced, setReduced] = useState(() => {
    const choice = stored();
    return choice ? choice === "reduced" : systemReduces();
  });
  const set = (next: boolean) => {
    const choice: Choice = next ? "reduced" : "full";
    try {
      localStorage.setItem(KEY, choice);
    } catch {
      // no storage: the choice still applies until reload
    }
    apply(choice);
    setReduced(next);
  };
  return [reduced, set];
}
