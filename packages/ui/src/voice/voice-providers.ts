/**
 * Per-provider endpoint and model defaults for voice input.
 *
 * These matter for more than convenience. The shipped `asr_endpoint` default is
 * the Doubao websocket URL, and the Windows host treats a `wss://` endpoint as
 * "this is Doubao". So a user who picked OpenAI but kept the stored endpoint
 * had their OpenAI token sent to ByteDance. Rewriting the endpoint when the
 * provider changes is what stops that at the source.
 */
/**
 * `models` is what the service is known to accept, so a user can pick one before
 * holding any credential; `documentation` is where that provider explains the
 * endpoint and how to obtain an API key. Both are presentation only -- the model
 * a request actually sends is still whatever is stored in preferences.
 */
export type ProviderDefaults = {
  endpoint: string;
  model: string;
  models?: readonly string[];
  documentation?: string;
};

export const ASR_PROVIDER_DEFAULTS: Record<string, ProviderDefaults> = {
  system: { endpoint: "", model: "" },
  // On-device Whisper. The model is a file the user points at, not a name a service resolves, so it lives in `asr_model_path` and there is no endpoint, token or model list to offer here.
  local: {
    endpoint: "",
    model: "",
    documentation: "https://huggingface.co/ggerganov/whisper.cpp/tree/main",
  },
  doubao: {
    endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
    model: "",
    documentation: "https://www.volcengine.com/docs/6561/1354869",
  },
  openai: {
    endpoint: "https://api.openai.com/v1/audio/transcriptions",
    model: "whisper-1",
    models: ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"],
    documentation: "https://developers.openai.com/api/docs/guides/speech-to-text",
  },
  siliconflow: {
    endpoint: "https://api.siliconflow.cn/v1/audio/transcriptions",
    model: "FunAudioLLM/SenseVoiceSmall",
    models: ["FunAudioLLM/SenseVoiceSmall"],
    documentation: "https://siliconflow.readme.io/reference/createaudiotranscriptions",
  },
  groq: {
    endpoint: "https://api.groq.com/openai/v1/audio/transcriptions",
    model: "whisper-large-v3-turbo",
    models: ["whisper-large-v3-turbo", "whisper-large-v3"],
    documentation: "https://console.groq.com/docs/speech-to-text",
  },
  everyapi: {
    endpoint: "https://api.everyapi.ai/v1/audio/transcriptions",
    model: "openai/whisper-large-v3-turbo",
    models: ["openai/whisper-large-v3-turbo", "volc.seedasr.sauc.duration"],
    documentation: "https://everyapi.ai/models",
  },
  mistral: {
    endpoint: "https://api.mistral.ai/v1/audio/transcriptions",
    model: "voxtral-mini-latest",
    models: ["voxtral-mini-latest"],
    documentation: "https://docs.mistral.ai/studio/audio/speech_to_text/offline_transcription",
  },
};

export const POLISH_PROVIDER_DEFAULTS: Record<string, ProviderDefaults> = {
  siliconflow: {
    endpoint: "https://api.siliconflow.cn/v1/chat/completions",
    model: "Qwen/Qwen3-8B",
    models: ["Qwen/Qwen3-8B", "Qwen/Qwen3.6-27B"],
    documentation: "https://docs.siliconflow.cn/docs/userguide/capabilities/text-generation",
  },
  openai: {
    endpoint: "https://api.openai.com/v1/chat/completions",
    model: "gpt-4o-mini",
    models: ["gpt-4o-mini", "gpt-4.1-mini"],
    documentation: "https://developers.openai.com/api/docs/models/gpt-4.1-mini",
  },
  deepseek: {
    endpoint: "https://api.deepseek.com/chat/completions",
    model: "deepseek-v4-flash",
    models: ["deepseek-v4-flash", "deepseek-v4-pro"],
    documentation: "https://api-docs.deepseek.com/",
  },
  groq: {
    endpoint: "https://api.groq.com/openai/v1/chat/completions",
    model: "llama-3.3-70b-versatile",
    models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
    documentation: "https://console.groq.com/docs/quickstart",
  },
};

/** An older SiliconFlow default that should still be treated as untouched. */
const LEGACY_ASR_MODELS = ["TeleAI/TeleSpeechASR"];

function known(table: Record<string, ProviderDefaults>, field: "endpoint" | "model"): string[] {
  return Object.values(table)
    .map((entry) => entry[field])
    .filter(Boolean);
}

/**
 * Replace `current` with the new provider's default, but only when the user has
 * not put something of their own there. An empty value or one of the shipped
 * defaults counts as untouched; anything else is kept.
 */
function fillIfDefault(
  current: string | undefined,
  next: string,
  defaults: string[],
): string | undefined {
  const value = (current ?? "").trim();
  if (value && !defaults.includes(value)) return undefined;
  return next;
}

type TokenMap = Record<string, string>;

/**
 * Move the token box from one provider's slot to another's.
 *
 * A single flat token meant switching provider left the previous provider's key
 * in the box, so it was sent to the new endpoint until the user noticed, and
 * the old key was gone the moment they retyped.
 */
function swapTokenSlot(from: string, to: string, box: string, slots: TokenMap | undefined) {
  const next: TokenMap = { ...slots };
  // Stash whatever is in the box under the provider being left.
  if (from) {
    if (box) next[from] = box;
    else delete next[from];
  }
  return { tokens: next, token: next[to] ?? "" };
}

/** The voice fields to update when the recognition provider changes. */
export function asrProviderUpdate(
  provider: string,
  current: {
    asr_provider?: string;
    asr_endpoint?: string;
    asr_model?: string;
    asr_token?: string;
    asr_tokens?: TokenMap;
  },
) {
  const defaults = ASR_PROVIDER_DEFAULTS[provider];
  const swapped = swapTokenSlot(
    current.asr_provider ?? "",
    provider,
    current.asr_token ?? "",
    current.asr_tokens,
  );
  const update: {
    asr_provider: string;
    asr_endpoint?: string;
    asr_model?: string;
    asr_token: string;
    asr_tokens: TokenMap;
  } = {
    asr_provider: provider,
    asr_token: swapped.token,
    asr_tokens: swapped.tokens,
  };
  // Neither of these sends anything to a service, so neither keeps a credential slot.
  if (provider === "system" || provider === "local") {
    update.asr_token = "";
    delete update.asr_tokens[provider];
  }
  if (!defaults) return update;
  const endpoint = fillIfDefault(
    current.asr_endpoint,
    defaults.endpoint,
    known(ASR_PROVIDER_DEFAULTS, "endpoint"),
  );
  if (endpoint !== undefined) update.asr_endpoint = endpoint;
  const model = fillIfDefault(current.asr_model, defaults.model, [
    ...known(ASR_PROVIDER_DEFAULTS, "model"),
    ...LEGACY_ASR_MODELS,
  ]);
  if (model !== undefined) update.asr_model = model;
  return update;
}

/** The voice fields to update when the polish provider changes. */
export function polishProviderUpdate(
  provider: string,
  current: {
    polish_provider?: string;
    polish_endpoint?: string;
    polish_model?: string;
    polish_token?: string;
    polish_tokens?: TokenMap;
  },
) {
  const defaults = POLISH_PROVIDER_DEFAULTS[provider];
  const swapped = swapTokenSlot(
    current.polish_provider ?? "",
    provider,
    current.polish_token ?? "",
    current.polish_tokens,
  );
  const update: {
    polish_provider: string;
    polish_endpoint?: string;
    polish_model?: string;
    polish_token: string;
    polish_tokens: TokenMap;
  } = {
    polish_provider: provider,
    polish_token: swapped.token,
    polish_tokens: swapped.tokens,
  };
  if (!defaults) return update;
  const endpoint = fillIfDefault(
    current.polish_endpoint,
    defaults.endpoint,
    known(POLISH_PROVIDER_DEFAULTS, "endpoint"),
  );
  if (endpoint !== undefined) update.polish_endpoint = endpoint;
  const model = fillIfDefault(
    current.polish_model,
    defaults.model,
    known(POLISH_PROVIDER_DEFAULTS, "model"),
  );
  if (model !== undefined) update.polish_model = model;
  return update;
}
