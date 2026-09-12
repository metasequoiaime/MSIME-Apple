import { expect, test } from "vitest";
import base from "../src-tauri/tauri.conf.json";
import windows from "../src-tauri/tauri.windows.conf.json";
import capability from "../src-tauri/capabilities/default.json";

test("Windows custom titlebar disables native decorations without losing window constraints", () => {
  // Platform config replaces the windows array rather than merging its items.
  expect(windows.app.windows).toEqual(base.app.windows.map((window: object) => ({ ...window, decorations: false })));
  expect(base.app.windows[0]).not.toHaveProperty("decorations");
  expect(windows).not.toHaveProperty("build");
  expect(windows.app).not.toHaveProperty("security");
  expect(capability.windows).toContain("main");
  for (const action of ["start-dragging", "start-resize-dragging", "minimize", "maximize", "unmaximize", "close"])
    expect(capability.permissions).toContain(`core:window:allow-${action}`);
});
