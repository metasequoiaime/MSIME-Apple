// @vitest-environment jsdom
import { act, cleanup, render, renderHook, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { useResolvedCandidateFonts } from "../../../packages/ui/src/resolved-candidate-fonts";
import { AppearanceCandidatePreview } from "../../../packages/ui/src/appearance-candidate-preview";
afterEach(cleanup);

test("the built-in preview consumes resolved CSS names", async () => {
  const preferences = { scheme: "quanpin" as const, shuangpin_profile: "xiaohe" as const,
    candidate_page_size: 6, learning: true, chinese_punctuation: true,
    candidate_font_family: "Synthetic W03", candidate_fallback_fonts: [] };
  const view = render(<AppearanceCandidatePreview preferences={preferences}
    resolveFonts={async () => ["Synthetic Family"]} />);
  await waitFor(() => expect((view.container.querySelector(".appearance-candidate-preview") as HTMLElement)
    .style.getPropertyValue("--appearance-font-family")).toBe('"Synthetic Family", sans-serif'));
  expect(preferences.candidate_font_family).toBe("Synthetic W03");
});

test("aliases affect presentation without changing preferences or fallback order", async () => {
  const preferences = { candidate_font_family: "Synthetic W03", candidate_fallback_fonts: ["Fallback W04", "Synthetic W03"] };
  const resolve = vi.fn().mockResolvedValue(["Synthetic", "Fallback", "Synthetic"]);
  const { result } = renderHook(() => useResolvedCandidateFonts(preferences, resolve));
  await waitFor(() => expect(result.current.candidate_font_family).toBe("Synthetic"));
  expect(result.current.candidate_fallback_fonts).toEqual(["Fallback", "Synthetic"]);
  expect(preferences.candidate_font_family).toBe("Synthetic W03");
  expect(resolve).toHaveBeenCalledTimes(1);
});

test("changing the request discards stale aliases immediately and ignores late replies", async () => {
  let complete!: (names: string[]) => void;
  const resolve = vi.fn().mockImplementationOnce(() => new Promise<string[]>(done => { complete = done; }))
    .mockResolvedValue(["New family"]);
  const { result, rerender } = renderHook(({ name }) => useResolvedCandidateFonts({ candidate_font_family: name, candidate_fallback_fonts: [] }, resolve), { initialProps: { name: "Old" } });
  rerender({ name: "New" });
  expect(result.current.candidate_font_family).toBe("New");
  await waitFor(() => expect(result.current.candidate_font_family).toBe("New family"));
  await act(async () => complete(["Old family"]));
  expect(result.current.candidate_font_family).toBe("New family");
});

test.each([[], [""], ["too", "many"], ["bad\nname"], ["x".repeat(129)], null].map(reply => ({ reply })))("invalid replies retain original names: $reply", async ({ reply }) => {
  const preferences = { candidate_font_family: "Original", candidate_fallback_fonts: [] };
  const resolve = vi.fn().mockResolvedValue(reply);
  const { result } = renderHook(() => useResolvedCandidateFonts(preferences, resolve));
  await act(async () => {});
  expect(result.current).toBe(preferences);
});

test("failed or unavailable resolution preserves the manual font", async () => {
  const preferences = { candidate_font_family: "Manual", candidate_fallback_fonts: [] };
  const resolve = vi.fn().mockRejectedValue(new Error("synthetic"));
  const { result, rerender } = renderHook(({ resolver }) => useResolvedCandidateFonts(preferences, resolver), { initialProps: { resolver: resolve as ((names: string[]) => Promise<string[]>) | undefined } });
  await act(async () => {});
  expect(result.current).toBe(preferences);
  rerender({ resolver: undefined });
  expect(result.current).toBe(preferences);
});
