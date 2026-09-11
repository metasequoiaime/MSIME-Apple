// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, render, waitFor } from "@testing-library/react";
import { useToolbarCss } from "../../../packages/ui/src/use-toolbar-css";
import { installToolbarCss } from "../../../packages/ui/src/skin-toolbar-css";

// jsdom does not implement CSSScopeRule. The real helper is exercised by the
// Chromium regression; these tests exercise asynchronous React ownership.
vi.mock("../../../packages/ui/src/skin-toolbar-css", () => ({ installToolbarCss: vi.fn() }));
afterEach(() => { cleanup(); vi.resetAllMocks(); });
function Probe({ read, revision = 0, filename = "toolbar.css" }: { read?: (id: string) => Promise<string | null>; revision?: number; filename?: string | null }) {
  return <span>{useToolbarCss(read, "sample", filename, revision, "scope")}</span>;
}
test("loads declared source by id and cleans up on refresh and unmount", async () => {
  const remove = vi.fn();
  vi.mocked(installToolbarCss).mockReturnValue({ remove, partial: false });
  const read = vi.fn().mockResolvedValue(".status-bar {}");
  const mounted = render(<Probe read={read} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("ready"));
  expect(read).toHaveBeenCalledExactlyOnceWith("sample");
  expect(installToolbarCss).toHaveBeenCalledWith("scope", ".status-bar {}");
  mounted.rerender(<Probe read={read} revision={1} />);
  await waitFor(() => expect(read).toHaveBeenCalledTimes(2));
  expect(remove).toHaveBeenCalledTimes(1);
  mounted.unmount();
  expect(remove).toHaveBeenCalledTimes(2);
});
test("stale source never installs and failures are sanitized", async () => {
  let resolve!: (css: string) => void;
  const read = vi.fn().mockImplementationOnce(() => new Promise<string>(done => { resolve = done; }))
    .mockRejectedValue(new Error("private diagnostic"));
  const mounted = render(<Probe read={read} />);
  mounted.rerender(<Probe read={read} revision={1} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("failed"));
  await act(async () => resolve(".old {}"));
  expect(installToolbarCss).not.toHaveBeenCalled();
  expect(mounted.container.textContent).toBe("failed");
});
test("absent capabilities and declarations do not read; missing source is inherited", async () => {
  const read = vi.fn().mockResolvedValue(null);
  const mounted = render(<Probe read={read} filename={null} />);
  expect(read).not.toHaveBeenCalled();
  mounted.rerender(<Probe read={read} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("ready"));
  expect(installToolbarCss).not.toHaveBeenCalled();
});
test("partial stylesheet support is reported and parser failure falls back", async () => {
  const read = vi.fn().mockResolvedValue(".status-bar {}");
  vi.mocked(installToolbarCss).mockReturnValueOnce({ remove: vi.fn(), partial: true }).mockImplementationOnce(() => { throw new Error("unsupported"); });
  const mounted = render(<Probe read={read} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("partial"));
  mounted.rerender(<Probe read={read} revision={1} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("failed"));
});
