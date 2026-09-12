import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
export default defineConfig({ plugins: [react()], server: { port: 1420, strictPort: true }, clearScreen: false,
  test: { css: { include: [/styles\.css/, /variables\.css/, /skin-candidate-decorations\.css/, /skin-toolbar-preview\.css/, /external-skin-geometry\.css/] } },
});
