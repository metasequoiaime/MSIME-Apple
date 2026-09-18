/** The non-secret shape of the voice settings read from the Engine's prepared preferences. */
export interface VoiceInputConfiguration {
  asr_provider: string;
  language: string;
  asr_endpoint: string;
  asr_token: string;
  asr_app_key: string;
  doubao_auth_mode: string;
  asr_resource_id: string;
  asr_model: string;
  doubao_enable_itn: boolean;
  doubao_enable_punc: boolean;
  doubao_enable_ddc: boolean;
  doubao_boosting_table_id: string;
}

export const DEFAULT_VOICE_INPUT_CONFIGURATION: VoiceInputConfiguration = {
  asr_provider: 'doubao',
  language: 'zh-cn',
  asr_endpoint: 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async',
  asr_token: '',
  asr_app_key: '',
  doubao_auth_mode: 'api_key',
  asr_resource_id: 'volc.seedasr.sauc.duration',
  asr_model: '',
  doubao_enable_itn: true,
  doubao_enable_punc: true,
  doubao_enable_ddc: false,
  doubao_boosting_table_id: ''
};
