// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { act, cleanup, render, waitFor } from "@testing-library/react";
import { useToolbarCss } from "../../../packages/ui/src/use-toolbar-css";
import { installToolbarCss } from "../../../packages/ui/src/skin-toolbar-css";
import { prepareToolbarImages } from "../../../packages/ui/src/toolbar-images";
import type { SkinImageReader } from "../../../packages/ui/src/skin-image";
import type { SkinFontReader } from "../../../packages/ui/src/skin-font";
import { prepareToolbarFonts } from "../../../packages/ui/src/toolbar-fonts";

// jsdom does not implement CSSScopeRule. The real helper is exercised by the
// Chromium regression; these tests exercise asynchronous React ownership.
vi.mock("../../../packages/ui/src/skin-toolbar-css", () => ({ installToolbarCss: vi.fn() }));
vi.mock("../../../packages/ui/src/toolbar-images", () => ({ prepareToolbarImages: vi.fn() }));
vi.mock("../../../packages/ui/src/toolbar-fonts", () => ({ prepareToolbarFonts: vi.fn() }));
afterEach(() => { cleanup(); vi.resetAllMocks(); });
function Probe({ read, revision = 0, filename = "toolbar.css", readImage, readFont }: { read?: (id: string) => Promise<string | null>; revision?: number; filename?: string | null; readImage?: SkinImageReader; readFont?: SkinFontReader }) {
  return <span>{useToolbarCss(read, "sample", filename, revision, "scope", readImage, readFont)}</span>;
}
test("font preparation uses the package reader and owns font cleanup", async () => {
  const readFont = vi.fn().mockResolvedValue({ contentType: "font/woff2", bytes: [0, 1] });
  const removeFont = vi.fn(), removeStyle = vi.fn(), install = vi.fn(() => removeFont);
  vi.mocked(prepareToolbarFonts).mockImplementation(async (_css, resolve) => {
    expect(new Uint8Array(await resolve("fonts/test.woff2"))).toEqual(new Uint8Array([0, 1]));
    return { css: ".prepared {}", partial: false, install };
  });
  vi.mocked(installToolbarCss).mockReturnValue({ remove: removeStyle, partial: false });
  const mounted = render(<Probe read={async () => ".source {}"} readFont={readFont} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("ready"));
  expect(readFont).toHaveBeenCalledExactlyOnceWith("sample", "fonts/test.woff2");
  expect(install).toHaveBeenCalledTimes(1);
  mounted.unmount();
  expect(removeFont).toHaveBeenCalledTimes(1);
  expect(removeStyle).toHaveBeenCalledTimes(1);
});
test("unmounted font preparation never installs fonts or styles", async () => {
  let finish!: (value: Awaited<ReturnType<typeof prepareToolbarFonts>>) => void;
  vi.mocked(prepareToolbarFonts).mockImplementation(() => new Promise(resolve => { finish = resolve; }));
  const mounted = render(<Probe read={async () => ".source {}"} readFont={vi.fn()} />);
  await waitFor(() => expect(prepareToolbarFonts).toHaveBeenCalledTimes(1));
  mounted.unmount();
  const install = vi.fn();
  await act(async () => finish({ css: ".late {}", partial: false, install }));
  expect(install).not.toHaveBeenCalled();
  expect(installToolbarCss).not.toHaveBeenCalled();
});
test("failed font installation rolls back the adopted stylesheet", async () => {
  const remove = vi.fn();
  vi.mocked(prepareToolbarFonts).mockResolvedValue({ css: ".prepared {}", partial: false, install: () => { throw new Error("synthetic"); } });
  vi.mocked(installToolbarCss).mockReturnValue({ remove, partial: false });
  const mounted = render(<Probe read={async () => ".source {}"} readFont={vi.fn()} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("failed"));
  expect(remove).toHaveBeenCalledTimes(1);
});
test("image preparation uses the same package id and reports partial resources", async () => {
  const readImage = vi.fn().mockResolvedValue({ contentType: "image/png", bytes: [0] });
  vi.mocked(prepareToolbarImages).mockImplementation(async (_css, resolve) => {
    expect(await resolve("images/a.png")).toBe("data:image/png;base64,AA==");
    return { css: ".prepared {}", partial: true };
  });
  vi.mocked(installToolbarCss).mockReturnValue({ remove: vi.fn(), partial: false });
  const mounted = render(<Probe read={async () => ".source {}"} readImage={readImage} />);
  await waitFor(() => expect(mounted.container.textContent).toBe("partial"));
  expect(readImage).toHaveBeenCalledExactlyOnceWith("sample", "images/a.png");
  expect(installToolbarCss).toHaveBeenCalledWith("scope", ".prepared {}");
});
test("unmounted image preparation cannot adopt a late stylesheet", async () => {
  let finish!: (value: { css: string; partial: boolean }) => void;
  vi.mocked(prepareToolbarImages).mockImplementation(() => new Promise(resolve => { finish = resolve; }));
  const mounted = render(<Probe read={async () => ".source {}"} readImage={vi.fn()} />);
  await waitFor(() => expect(prepareToolbarImages).toHaveBeenCalledTimes(1));
  mounted.unmount();
  await act(async () => finish({ css: ".late {}", partial: false }));
  expect(installToolbarCss).not.toHaveBeenCalled();
});
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
