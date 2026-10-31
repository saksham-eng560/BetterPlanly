import { defineConfig } from "@playwright/test";

// Expects the stack to be running: backend on :8000 (fresh database), Vite on :5173 and
// Ollama or scripts/fake_ollama.py on :11434. `make e2e` does all of that.
export default defineConfig({
  testDir: "e2e",
  timeout: 60_000,
  use: { baseURL: process.env.PLANLY_URL ?? "http://localhost:5173", viewport: { width: 1440, height: 960 } },
});
