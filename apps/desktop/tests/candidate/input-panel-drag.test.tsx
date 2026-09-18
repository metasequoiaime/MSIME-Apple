// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { HandwritingPanel, VoicePanel } from "@msime/ui";
import capability from "../src-tauri/capabilities/input-panel-drag.json";

afterEach(cleanup);
function pointer(target: Element, type: string, x: number, extra = {}) {
  const event = new Event(type, { bubbles: true });
  Object.assign(event, { pointerId: 1, clientX: x, clientY: 10, button: 0, buttons: 1, ...extra });
  fireEvent(target, event);
}

test("drag capability is restricted to the handwriting and voice windows", () => {
  expect(capability.windows).toEqual(["handwriting-panel", "voice-panel"]);
  expect(capability.permissions).toEqual(["core:window:allow-start-dragging"]);
});

for (const [name, Panel] of [["handwriting", HandwritingPanel], ["voice", VoicePanel]] as const) {
  test(`${name} titlebar starts one host drag after movement and excludes close`, () => {
    const beginWindowDrag = vi.fn().mockResolvedValue(undefined);
    const close = vi.fn().mockResolvedValue(undefined);
    const view = render(<Panel client={{ close, beginWindowDrag }} />);
    const header = view.container.querySelector("header")!;
    pointer(header, "pointerdown", 10);
    pointer(header, "pointermove", 11);
    expect(beginWindowDrag).not.toHaveBeenCalled();
    pointer(header, "pointermove", 13);
    pointer(header, "pointermove", 20);
    expect(beginWindowDrag).toHaveBeenCalledTimes(1);
    const button = screen.getByRole("button", { name: "关闭" });
    pointer(button, "pointerdown", 10);
    pointer(button, "pointermove", 20);
    expect(beginWindowDrag).toHaveBeenCalledTimes(1);
    expect(close).not.toHaveBeenCalled();
  });

  test.each(["pointerup", "pointercancel", "pointerout", "blur"])(`${name} cancels pending drag on %s`, reason => {
    const beginWindowDrag = vi.fn().mockResolvedValue(undefined);
    const view = render(<Panel client={{ close: vi.fn(), beginWindowDrag }} />);
    const header = view.container.querySelector("header")!;
    pointer(header, "pointerdown", 10);
    if (reason === "blur") fireEvent(window, new Event("blur"));
    else pointer(header, reason, 10);
    pointer(header, "pointermove", 20);
    expect(beginWindowDrag).not.toHaveBeenCalled();
  });

  test.each([false, true])(`${name} reports host drag failure (synchronous=%s)`, async synchronous => {
    const view = render(<Panel client={{ close: vi.fn(), beginWindowDrag: () => {
      if (synchronous) throw new Error("fixture");
      return Promise.reject(new Error("fixture"));
    } }} />);
    const header = view.container.querySelector("header")!;
    pointer(header, "pointerdown", 10);
    pointer(header, "pointermove", 20);
    await waitFor(() => expect(screen.getByRole("status").textContent).toContain("无法移动窗口"));
  });
}
