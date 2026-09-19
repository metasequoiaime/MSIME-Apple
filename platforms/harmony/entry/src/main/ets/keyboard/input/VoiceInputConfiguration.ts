/** The non-secret shape of the voice settings read from the Engine's prepared preferences. */
export interface VoicePolishTokens {
  siliconflow?: string;
  openai?: string;
  deepseek?: string;
  groq?: string;
}

export interface VoiceInputConfiguration {
  /** Shared privacy/availability switch; omitted by older prepared preference documents. */
  enabled: boolean;
  asr_provider: string;
  language: string;
  asr_endpoint: string;
  asr_token: string;
  asr_app_key: string;
  doubao_auth_mode: string;
  asr_resource_id: string;
  asr_model: string;
  polish_enabled: boolean;
  polish_text: boolean;
  polish_provider: string;
  polish_token: string;
  polish_tokens: VoicePolishTokens;
  polish_endpoint: string;
  polish_model: string;
  polish_prompt_id: string;
  polish_prompt: string;
  polish_prompt_custom_1: string;
  polish_prompt_custom_2: string;
  polish_prompt_custom_3: string;
  doubao_enable_itn: boolean;
  doubao_enable_punc: boolean;
  doubao_enable_ddc: boolean;
  doubao_boosting_table_id: string;
}

export const DEFAULT_VOICE_INPUT_CONFIGURATION: VoiceInputConfiguration = {
  enabled: true,
  asr_provider: 'doubao',
  language: 'zh-cn',
  asr_endpoint: 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async',
  asr_token: '',
  asr_app_key: '',
  doubao_auth_mode: 'api_key',
  asr_resource_id: 'volc.seedasr.sauc.duration',
  asr_model: '',
  polish_enabled: false,
  polish_text: false,
  polish_provider: 'siliconflow',
  polish_token: '',
  polish_tokens: {},
  polish_endpoint: 'https://api.siliconflow.cn/v1/chat/completions',
  polish_model: 'Qwen/Qwen3-8B',
  polish_prompt_id: 'cleanup',
  polish_prompt: '',
  polish_prompt_custom_1: '',
  polish_prompt_custom_2: '',
  polish_prompt_custom_3: '',
  doubao_enable_itn: true,
  doubao_enable_punc: true,
  doubao_enable_ddc: false,
  doubao_boosting_table_id: ''
};

/** Keeps legacy prepared documents enabled unless they explicitly opt out. */
export class VoiceInputConfigurationPolicy {
  static enabled(value: boolean | undefined): boolean {
    return value !== false;
  }
}
