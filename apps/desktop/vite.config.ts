import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
export default defineConfig({ plugins: [react()], server: { port: 1420, strictPort: true }, clearScreen: false,
  test: {
    css: { include: [/styles\.css/, /variables\.css/, /skin-candidate-decorations\.css/, /skin-toolbar-preview\.css/, /external-skin-geometry\.css/] },
    // These render the whole settings page, and some drive it through dozens
    // of changes; the font-size test alone re-renders 42 times. Vitest isolates
    // each file in its own worker - 60-odd of them here - so they also compete
    // for the machine while doing it. At the 5 s default, five tests failed on
    // timing alone while passing individually, which reads as a broken suite
    // rather than a slow one.
    testTimeout: 20000,
    hookTimeout: 20000,
  },
});
