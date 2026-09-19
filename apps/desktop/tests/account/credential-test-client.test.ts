import { expect, test, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { testDesktopApiCredential } from "../../src/account/credential-test-client";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

test("desktop credential probes use the bounded Tauri command", async () => {
  vi.mocked(invoke).mockResolvedValueOnce({ ok: true, message: "fixture complete" });
  const config = { provider: "openai", token: "synthetic-token" };
  await expect(testDesktopApiCredential("voice.asr", config)).resolves.toEqual({ ok: true, message: "fixture complete" });
  expect(invoke).toHaveBeenCalledWith("test_api_credential", { service: "voice.asr", config });
});
