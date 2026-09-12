// Bundle a synthetic settings host with the real UI and styles for local tests.
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
const require = createRequire(new URL("../apps/desktop/package.json", import.meta.url));
const { build } = await import(require.resolve("vite"));
if (!process.argv[2]) throw new Error("pass a temporary output directory");
await build({
  configFile: false, publicDir: false,
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
  build: {
    outDir: resolve(process.argv[2]), emptyOutDir: false,
    lib: { entry: fileURLToPath(new URL("../apps/desktop/src/browser-fixtures/settings.tsx", import.meta.url)), formats: ["es"], cssFileName: "settings" },
    rollupOptions: { output: { entryFileNames: "settings.js" } },
  },
});
