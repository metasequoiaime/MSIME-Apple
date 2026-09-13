/**
 * Per-provider endpoint and model defaults for voice input.
 *
 * These matter for more than convenience. The shipped `asr_endpoint` default is
 * the Doubao websocket URL, and the Windows host treats a `wss://` endpoint as
 * "this is Doubao". So a user who picked OpenAI but kept the stored endpoint
 * had their OpenAI token sent to ByteDance. Rewriting the endpoint when the
 * provider changes is what stops that at the source.
 */
export type ProviderDefaults = { endpoint: string; model: string };

export const ASR_PROVIDER_DEFAULTS: Record<string, ProviderDefaults> = {
  doubao: { endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async", model: "" },
  openai: { endpoint: "https://api.openai.com/v1/audio/transcriptions", model: "whisper-1" },
  siliconflow: { endpoint: "https://api.siliconflow.cn/v1/audio/transcriptions", model: "FunAudioLLM/SenseVoiceSmall" },
  groq: { endpoint: "https://api.groq.com/openai/v1/audio/transcriptions", model: "whisper-large-v3-turbo" },
};

export const POLISH_PROVIDER_DEFAULTS: Record<string, ProviderDefaults> = {
  siliconflow: { endpoint: "https://api.siliconflow.cn/v1/chat/completions", model: "Qwen/Qwen3-8B" },
  openai: { endpoint: "https://api.openai.com/v1/chat/completions", model: "gpt-4o-mini" },
  deepseek: { endpoint: "https://api.deepseek.com/chat/completions", model: "deepseek-v4-flash" },
  groq: { endpoint: "https://api.groq.com/openai/v1/chat/completions", model: "llama-3.3-70b-versatile" },
};

/** An older SiliconFlow default that should still be treated as untouched. */
const LEGACY_ASR_MODELS = ["TeleAI/TeleSpeechASR"];

function known(table: Record<string, ProviderDefaults>, field: keyof ProviderDefaults): string[] {
  return Object.values(table).map(entry => entry[field]).filter(Boolean);
}

/**
 * Replace `current` with the new provider's default, but only when the user has
 * not put something of their own there. An empty value or one of the shipped
 * defaults counts as untouched; anything else is kept.
 */
function fillIfDefault(current: string | undefined, next: string, defaults: string[]): string | undefined {
  const value = (current ?? "").trim();
  if (value && !defaults.includes(value)) return undefined;
  return next;
}

/** The voice fields to update when the recognition provider changes. */
export function asrProviderUpdate(provider: string, current: { asr_endpoint?: string; asr_model?: string }) {
  const defaults = ASR_PROVIDER_DEFAULTS[provider];
  const update: { asr_provider: string; asr_endpoint?: string; asr_model?: string } = { asr_provider: provider };
  if (!defaults) return update;
  const endpoint = fillIfDefault(current.asr_endpoint, defaults.endpoint, known(ASR_PROVIDER_DEFAULTS, "endpoint"));
  if (endpoint !== undefined) update.asr_endpoint = endpoint;
  const model = fillIfDefault(current.asr_model, defaults.model, [
    ...known(ASR_PROVIDER_DEFAULTS, "model"),
    ...LEGACY_ASR_MODELS,
  ]);
  if (model !== undefined) update.asr_model = model;
  return update;
}

/** The voice fields to update when the polish provider changes. */
export function polishProviderUpdate(provider: string, current: { polish_endpoint?: string; polish_model?: string }) {
  const defaults = POLISH_PROVIDER_DEFAULTS[provider];
  const update: { polish_provider: string; polish_endpoint?: string; polish_model?: string } = { polish_provider: provider };
  if (!defaults) return update;
  const endpoint = fillIfDefault(current.polish_endpoint, defaults.endpoint, known(POLISH_PROVIDER_DEFAULTS, "endpoint"));
  if (endpoint !== undefined) update.polish_endpoint = endpoint;
  const model = fillIfDefault(current.polish_model, defaults.model, known(POLISH_PROVIDER_DEFAULTS, "model"));
  if (model !== undefined) update.polish_model = model;
  return update;
}
