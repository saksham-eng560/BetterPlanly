import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { "/api": { target: process.env.PLANLY_API ?? "http://localhost:8000", changeOrigin: true } },
    fs: { allow: [".."] }, // examples/AGENT_PROMPT.md lives at the repo root
  },
  test: { include: ["src/**/*.test.ts"] },
});
