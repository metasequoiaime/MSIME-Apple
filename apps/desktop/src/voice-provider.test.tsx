// @vitest-environment jsdom
import { afterEach, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { SettingsPage, type SettingsClient, type Snapshot } from "@msime/ui";

afterEach(cleanup);

const base: Snapshot = {
  format_version: 1,
  revision: 4,
  preferences: { scheme: "quanpin", shuangpin_profile: "xiaohe", candidate_page_size: 5, learning: true, chinese_punctuation: true },
};

function mount(client: Partial<SettingsClient>) {
  return render(<SettingsPage client={{ load: async () => base, save: vi.fn(), ...client }} />);
}

async function openVoice() {
  await screen.findByRole("button", { name: "保存设置" });
  fireEvent.click(screen.getByRole("button", { name: "语音输入" }));
  return screen.getByLabelText("识别服务") as HTMLSelectElement;
}

// The Linux voice provider builds ASR_PROVIDERS = {openai, groq, siliconflow, doubao}.
// Anything else makes select_profile return None and every recording fail with ok=false.
const REACHABLE = ["doubao", "siliconflow", "openai", "groq"];

test("the recognition dropdown only offers providers a backend implements", async () => {
  mount({});
  const select = await openVoice();
  const offered = Array.from(select.options).map(option => option.value);
  expect(offered.sort()).toEqual([...REACHABLE].sort());
  // These two shipped for a while and no backend has ever implemented them.
  expect(offered).not.toContain("local_whisper");
  expect(offered).not.toContain("cloud");
});

test("the default recognition provider is one the dropdown offers", async () => {
  mount({});
  const select = await openVoice();
  expect(REACHABLE).toContain(select.value);
  // A default outside the option list would render as an empty selection.
  expect(select.value).not.toBe("");
});

test("a stored provider selection round-trips through save", async () => {
  const save = vi.fn().mockImplementation(async (_revision, preferences) => ({ ...base, revision: 5, preferences }));
  mount({ save });
  const select = await openVoice();
  fireEvent.change(select, { target: { value: "siliconflow" } });
  fireEvent.click(screen.getByRole("button", { name: "保存设置" }));
  await vi.waitFor(() => expect(save).toHaveBeenCalled());
  expect(save.mock.calls[0][1].voice_input.asr_provider).toBe("siliconflow");
});
