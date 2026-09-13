// @vitest-environment jsdom
import { expect, test } from "vitest";
import {
  ASR_PROVIDER_DEFAULTS,
  POLISH_PROVIDER_DEFAULTS,
  asrProviderUpdate,
  polishProviderUpdate,
} from "@msime/ui";

const doubaoEndpoint = ASR_PROVIDER_DEFAULTS.doubao.endpoint;

test("picking a non-Doubao provider rewrites the shipped Doubao endpoint", () => {
  // The defect: asr_endpoint defaults to Doubao's websocket URL, and the
  // Windows host routes any websocket endpoint to DoubaoAsrClient. Leaving it
  // in place sent the user's OpenAI token to ByteDance.
  const update = asrProviderUpdate("openai", { asr_endpoint: doubaoEndpoint, asr_model: "" });
  expect(update.asr_provider).toBe("openai");
  expect(update.asr_endpoint).toBe(ASR_PROVIDER_DEFAULTS.openai.endpoint);
  expect(update.asr_endpoint?.startsWith("https://")).toBe(true);
  expect(update.asr_model).toBe("whisper-1");
});

test("every provider's default endpoint is rewritten on switch", () => {
  for (const provider of ["doubao", "openai", "siliconflow", "groq"]) {
    const update = asrProviderUpdate(provider, { asr_endpoint: doubaoEndpoint });
    expect(update.asr_endpoint).toBe(ASR_PROVIDER_DEFAULTS[provider].endpoint);
  }
  // Only Doubao keeps a websocket endpoint; the rest must be HTTPS, because
  // the native side reads the scheme to decide which client to build.
  for (const provider of ["openai", "siliconflow", "groq"]) {
    expect(ASR_PROVIDER_DEFAULTS[provider].endpoint.startsWith("wss://")).toBe(false);
  }
  expect(ASR_PROVIDER_DEFAULTS.doubao.endpoint.startsWith("wss://")).toBe(true);
});

test("a self-hosted endpoint the user typed is never overwritten", () => {
  const mine = "https://asr.internal.example/v1/audio/transcriptions";
  const update = asrProviderUpdate("groq", { asr_endpoint: mine, asr_model: "my-model" });
  expect(update.asr_endpoint).toBeUndefined();
  expect(update.asr_model).toBeUndefined();
  expect(update.asr_provider).toBe("groq");
});

test("an empty field is filled rather than left blank", () => {
  const update = asrProviderUpdate("siliconflow", { asr_endpoint: "", asr_model: "   " });
  expect(update.asr_endpoint).toBe(ASR_PROVIDER_DEFAULTS.siliconflow.endpoint);
  expect(update.asr_model).toBe(ASR_PROVIDER_DEFAULTS.siliconflow.model);
});

test("a superseded shipped default still counts as untouched", () => {
  // Someone who never edited the model but carries an older default should
  // still be moved forward rather than pinned to a stale value.
  const update = asrProviderUpdate("openai", { asr_model: "TeleAI/TeleSpeechASR" });
  expect(update.asr_model).toBe("whisper-1");
});

test("Doubao takes no model, so switching to it clears one", () => {
  const update = asrProviderUpdate("doubao", { asr_model: "whisper-1" });
  expect(update.asr_model).toBe("");
});

test("an unknown provider changes nothing but the id", () => {
  const update = asrProviderUpdate("nonsense", { asr_endpoint: doubaoEndpoint, asr_model: "whisper-1" });
  expect(update).toEqual({ asr_provider: "nonsense" });
});

test("the polish provider follows the same rules", () => {
  const update = polishProviderUpdate("deepseek", {
    polish_endpoint: POLISH_PROVIDER_DEFAULTS.siliconflow.endpoint,
    polish_model: POLISH_PROVIDER_DEFAULTS.siliconflow.model,
  });
  expect(update.polish_endpoint).toBe(POLISH_PROVIDER_DEFAULTS.deepseek.endpoint);
  expect(update.polish_model).toBe(POLISH_PROVIDER_DEFAULTS.deepseek.model);

  const custom = polishProviderUpdate("openai", { polish_endpoint: "https://llm.internal.example/v1/chat" });
  expect(custom.polish_endpoint).toBeUndefined();
});
