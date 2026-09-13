// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { HandwritingPanel } from "@msime/ui";

afterEach(cleanup);

function setup() {
  const recognizeHandwriting = vi.fn().mockResolvedValue({ candidates: [] });
  render(<HandwritingPanel client={{ close: vi.fn(), recognizeHandwriting }} />);
  const canvas = screen.getByLabelText("手写画布");
  function pointer(type: string, pointerId: number, x = 20, y = 20, extra = {}) {
    const event = new Event(type, { bubbles: true });
    Object.assign(event, { pointerId, clientX: x, clientY: y, button: 0, isPrimary: true, ...extra });
    fireEvent(canvas, event);
  }
  return { canvas, pointer, recognizeHandwriting };
}

test("handwriting keeps one pointer and includes the release endpoint", () => {
  const { pointer, recognizeHandwriting } = setup();
  pointer("pointerdown", 1);
  pointer("pointerdown", 2, 200, 200);
  pointer("pointermove", 2, 300, 300);
  pointer("pointerup", 2, 300, 300);
  expect(recognizeHandwriting).not.toHaveBeenCalled();
  pointer("pointermove", 1, 40, 40);
  pointer("pointerup", 1, 60, 60);
  expect(recognizeHandwriting).toHaveBeenCalledExactlyOnceWith({ language: "zh-CN", strokes: [{ points: [{ x: 20, y: 20 }, { x: 40, y: 40 }, { x: 60, y: 60 }] }] });
});

test.each(["pointercancel", "lostpointercapture"])("handwriting discards incomplete ink on %s", type => {
  const { canvas, pointer, recognizeHandwriting } = setup();
  pointer("pointerdown", 1);
  pointer("pointermove", 1, 40, 40);
  pointer(type, 1);
  pointer("pointerup", 1, 60, 60);
  expect(recognizeHandwriting).not.toHaveBeenCalled();
  expect(canvas.querySelectorAll("polyline")).toHaveLength(0);
  pointer("pointerdown", 2);
  pointer("pointerup", 2);
  expect(recognizeHandwriting).not.toHaveBeenCalled();
});

test("cancel preserves completed strokes without including the interrupted stroke", () => {
  const { pointer, recognizeHandwriting } = setup();
  pointer("pointerdown", 1);
  pointer("pointerup", 1, 40, 40);
  pointer("pointerdown", 2, 100, 100);
  pointer("pointermove", 2, 120, 120);
  pointer("pointercancel", 2);
  expect(recognizeHandwriting).toHaveBeenLastCalledWith({ language: "zh-CN", strokes: [{ points: [{ x: 20, y: 20 }, { x: 40, y: 40 }] }] });
});

test("handwriting ignores right clicks, secondary touches and isolated taps", () => {
  const { canvas, pointer, recognizeHandwriting } = setup();
  pointer("pointerdown", 1, 20, 20, { button: 2 });
  pointer("pointermove", 1, 40, 40);
  pointer("pointerup", 1, 40, 40);
  pointer("pointerdown", 2, 20, 20, { isPrimary: false });
  pointer("pointermove", 2, 40, 40);
  pointer("pointerup", 2, 40, 40);
  pointer("pointerdown", 3);
  pointer("pointerup", 3);
  expect(recognizeHandwriting).not.toHaveBeenCalled();
  expect(canvas.querySelectorAll("polyline")).toHaveLength(0);
});

test.each([/撤销/, /重写/])("handwriting releases active drawing when using %s", name => {
  const { canvas, pointer, recognizeHandwriting } = setup();
  pointer("pointerdown", 1);
  pointer("pointermove", 1, 40, 40);
  fireEvent.click(screen.getByRole("button", { name }));
  pointer("pointermove", 1, 60, 60);
  pointer("pointerup", 1, 80, 80);
  expect(recognizeHandwriting).not.toHaveBeenCalled();
  expect(canvas.querySelectorAll("polyline")).toHaveLength(0);
});
