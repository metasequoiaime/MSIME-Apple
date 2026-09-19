import { defineConfig } from "vite-plus";

// Vite+ reads lint and format configuration from a single config at the
// repository root. This file exists only for that: the desktop and HarmonyOS
// apps keep their own vite.config.ts for dev, build and test.
export default defineConfig({
  lint: {
    rules: {
      // This client rejects control characters on purpose, at every boundary it
      // owns; the Rust side does the same with `chars().any(char::is_control)`.
      // The regexes the rule objects to are that check, so following its advice
      // would delete the validation rather than fix anything.
      "no-control-regex": "off",
      // The two uses are size-limit fixtures - `new Array(8 * 1024 * 1024 + 1)` -
      // where nothing about the argument is ambiguous, and the suggested
      // `Array.from({ length: n }, ...)` runs a callback eight million times to
      // build the same thing.
      "unicorn/no-new-array": "off",
    },
    ignorePatterns: [
      // Verbatim upstream copies; they stay byte-identical to what they are
      // diffed against. Same reasoning as their .editorconfig exception.
      "packages/ui/src/upstream/**",
      // Tauri scaffolding, rewritten by the generator.
      "apps/desktop/src-tauri/gen/**",
    ],
  },
  fmt: {
    // Oxfmt keeps its own ignore list rather than inheriting the one above, and
    // a first run proved it: it reformatted the vendored upstream HTML before
    // these patterns were added here.
    ignorePatterns: ["packages/ui/src/upstream/**", "apps/desktop/src-tauri/gen/**"],
  },
});
