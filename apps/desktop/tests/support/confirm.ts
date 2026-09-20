import { expect } from "vitest";
import { fireEvent, screen, waitFor } from "@testing-library/react";

/**
 * Answers the shared in-page confirmation dialog.
 *
 * These tests used to stub `window.confirm`, which was never a dialog this application could rely
 * on: on the Apple hosts it does not appear at all and returns `false`, so the stub was asserting
 * against a control the user never sees. Answering the rendered dialog means the assertion covers
 * the same thing the user does.
 */
export async function answerConfirm(answer: "confirm" | "cancel"): Promise<void> {
  const dialog = await screen.findByRole("alertdialog");
  const label = answer === "confirm" ? "确定" : "取消";
  // The confirming button is relabelled per action ("删除", "恢复", …), so take it by position
  // rather than by name: cancel first, confirm second, as the dialog renders them.
  const buttons = Array.from(dialog.querySelectorAll("button"));
  const button =
    buttons.find((candidate) => candidate.textContent?.trim() === label) ??
    (answer === "confirm" ? buttons.at(-1) : buttons[0]);
  if (!button) throw new Error(`no ${answer} button in the confirmation dialog`);
  fireEvent.click(button);
  await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
}

/** True when a confirmation is currently being asked. */
export function confirmAsked(): boolean {
  return screen.queryByRole("alertdialog") !== null;
}
