import { afterEach } from "vitest";

// The mobile settings page restores its current page from `window.history.state` when it remounts, which is how returning from onboarding lands back where it started (2cb75ca8b). jsdom keeps one window per test file, so without this the page one test navigated to becomes the next test's starting page, and a test that expects the home page finds some other one.
afterEach(() => {
  if (typeof window !== "undefined") window.history.replaceState(null, "");
});
