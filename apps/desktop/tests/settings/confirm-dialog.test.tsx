// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import { useConfirm } from "@msime/ui";

afterEach(cleanup);

function Harness({ onAnswer }: { onAnswer?: (confirmed: boolean) => void }) {
  const { confirm, confirmation } = useConfirm();
  const [answer, setAnswer] = useState("未问");
  return (
    <div>
      <button
        type="button"
        onClick={() =>
          void confirm({ message: "删除词条“你好”？", danger: true }).then((confirmed) => {
            setAnswer(confirmed ? "已确认" : "已取消");
            onAnswer?.(confirmed);
          })
        }
      >
        删除
      </button>
      <span data-testid="answer">{answer}</span>
      {confirmation}
    </div>
  );
}

test("confirming resolves true and cancelling resolves false", async () => {
  render(<Harness />);
  // Nothing is asked until the action is taken.
  expect(screen.queryByRole("alertdialog")).toBeNull();

  fireEvent.click(screen.getByRole("button", { name: "删除" }));
  expect(screen.getByRole("alertdialog").textContent).toContain("删除词条“你好”？");
  fireEvent.click(screen.getByRole("button", { name: "取消" }));
  await waitFor(() => expect(screen.getByTestId("answer").textContent).toBe("已取消"));
  expect(screen.queryByRole("alertdialog")).toBeNull();

  fireEvent.click(screen.getByRole("button", { name: "删除" }));
  fireEvent.click(screen.getByRole("button", { name: "确定" }));
  await waitFor(() => expect(screen.getByTestId("answer").textContent).toBe("已确认"));
});

test("escape and the backdrop both cancel", async () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "删除" }));
  fireEvent.keyDown(screen.getByRole("alertdialog"), { key: "Escape" });
  await waitFor(() => expect(screen.getByTestId("answer").textContent).toBe("已取消"));

  fireEvent.click(screen.getByRole("button", { name: "删除" }));
  const dialog = screen.getByRole("alertdialog");
  const backdrop = dialog.parentElement as HTMLElement;
  // A press that starts inside the dialog must not cancel just because it lands on the backdrop.
  fireEvent.mouseDown(dialog);
  expect(screen.getByRole("alertdialog")).toBeTruthy();
  fireEvent.mouseDown(backdrop);
  await waitFor(() => expect(screen.queryByRole("alertdialog")).toBeNull());
});

test("focus moves to the confirming button and returns where it came from", async () => {
  render(<Harness />);
  const trigger = screen.getByRole("button", { name: "删除" });
  trigger.focus();
  fireEvent.click(trigger);
  await waitFor(() =>
    expect(document.activeElement).toBe(screen.getByRole("button", { name: "确定" })),
  );
  fireEvent.click(screen.getByRole("button", { name: "取消" }));
  // Without this every confirmation would drop the user at the top of the page.
  await waitFor(() => expect(document.activeElement).toBe(trigger));
});

test("unmounting while open answers no rather than leaving the caller waiting", async () => {
  const answered = vi.fn();
  const view = render(<Harness onAnswer={answered} />);
  fireEvent.click(screen.getByRole("button", { name: "删除" }));
  view.unmount();
  await waitFor(() => expect(answered).toHaveBeenCalledWith(false));
});
