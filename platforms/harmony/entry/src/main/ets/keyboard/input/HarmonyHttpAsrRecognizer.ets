import audio from '@ohos.multimedia.audio';
import http from '@ohos.net.http';
import util from '@ohos.util';
import { KeyboardLog, describeError } from '../KeyboardLog';
import { utf8Length } from '../Utf8';
import { VoiceRecognitionPolicy } from './VoiceRecognitionPolicy';
import { HarmonyVoiceCaptureDevices } from './HarmonyVoiceCaptureDevices';
import { VoiceOutcome, VoiceResponsePolicy } from './VoiceResponsePolicy';
import { VoiceInputConfiguration } from './VoiceInputConfiguration';

const SAMPLE_RATE: number = 16000;
const SAMPLE_BYTES: number = 2;
const MAX_DURATION_MS: number = 120000;
const MAX_AUDIO_BYTES: number = SAMPLE_RATE * SAMPLE_BYTES * 120;
const MAX_RESPONSE_BYTES: number = 1024 * 1024;

interface AsrResponse {
  text?: string;
}

interface AsrProviderDefaults {
  endpoint: string;
  model: string;
}

const PROVIDER_DEFAULTS: AsrProviderDefaults[] = [
  { endpoint: 'https://api.openai.com/v1/audio/transcriptions', model: 'whisper-1' },
  { endpoint: 'https://api.siliconflow.cn/v1/audio/transcriptions', model: 'FunAudioLLM/SenseVoiceSmall' },
  { endpoint: 'https://api.groq.com/openai/v1/audio/transcriptions', model: 'whisper-large-v3-turbo' }
];

export type HttpAsrResultHandler = (text: string, final: boolean) => void;
export type HttpAsrErrorHandler = (message: string) => void;

/** Captures one bounded WAV and sends it to an OpenAI-compatible transcription endpoint. */
export class HarmonyHttpAsrRecognizer {
  private capturer: audio.AudioCapturer | undefined = undefined;
  private readCallback: ((data: ArrayBuffer) => void) | undefined = undefined;
  private request: http.HttpRequest | undefined = undefined;
  private chunks: Uint8Array[] = [];
  private audioBytes: number = 0;
  private sessionToken: number = 0;
  private stopping: boolean = false;
  private settled: boolean = false;
  private timeoutHandle: number | undefined = undefined;
  private resultHandler: HttpAsrResultHandler | undefined = undefined;
  private errorHandler: HttpAsrErrorHandler | undefined = undefined;

  isActive(): boolean {
    return this.capturer !== undefined || this.request !== undefined;
  }

  async start(config: VoiceInputConfiguration, onResult: HttpAsrResultHandler,
    onError: HttpAsrErrorHandler): Promise<void> {
    if (this.isActive()) throw new Error('语音识别正在进行');
    if (!this.validConfig(config)) throw new Error('请先配置有效的语音接口、模型和凭据');
    const token: number = this.sessionToken + 1;
    this.sessionToken = token;
    this.resultHandler = onResult;
    this.errorHandler = onError;
    this.chunks = [];
    this.audioBytes = 0;
    this.stopping = false;
    this.settled = false;
    this.timeoutHandle = setTimeout((): void => {
      if (token === this.sessionToken) void this.fail('语音识别超时。', token);
    }, MAX_DURATION_MS);
    try {
      await this.startCapturer(config, token);
    } catch (error) {
      if (token !== this.sessionToken) return;
      await this.fail(`语音采集启动失败：${describeError(error)}`, token);
      throw new Error('语音采集启动失败');
    }
  }

  stop(): void {
    if (!this.isActive() || this.stopping || this.settled) return;
    this.stopping = true;
    void this.finish(this.sessionToken);
  }

  cancel(): void {
    this.sessionToken += 1;
    this.stopping = true;
    this.settled = true;
    this.clearTimeout();
    void this.releaseCapturer();
    const request: http.HttpRequest | undefined = this.request;
    this.request = undefined;
    if (request !== undefined) request.destroy();
    this.chunks = [];
    this.audioBytes = 0;
    this.resultHandler = undefined;
    this.errorHandler = undefined;
  }

  shutdown(): void {
    this.cancel();
  }

  private async startCapturer(config: VoiceInputConfiguration, token: number): Promise<void> {
    // Before the capturer exists, because the routing choice is process-wide rather than a property
    // of one stream. A device that has gone away leaves the system default in place.
    await HarmonyVoiceCaptureDevices.select(config.capture_backend, config.capture_device);
    if (token !== this.sessionToken || this.settled) {
      return;
    }
    const options: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
    };
    const capturer: audio.AudioCapturer = await audio.createAudioCapturer(options);
    if (token !== this.sessionToken || this.settled) {
      await capturer.release();
      return;
    }
    const readCallback: (data: ArrayBuffer) => void = (data: ArrayBuffer): void => {
      this.readAudio(data, token);
    };
    this.capturer = capturer;
    this.readCallback = readCallback;
    capturer.on('readData', readCallback);
    try {
      await capturer.start();
    } catch (error) {
      capturer.off('readData', readCallback);
      if (this.capturer === capturer) {
        this.capturer = undefined;
        this.readCallback = undefined;
      }
      await capturer.release();
      throw new Error('Harmony 音频采集启动失败');
    }
  }

  private readAudio(data: ArrayBuffer, token: number): void {
    if (token !== this.sessionToken || this.stopping || this.settled || data.byteLength === 0) return;
    if (this.audioBytes + data.byteLength > MAX_AUDIO_BYTES) {
      void this.fail('录音时间超过限制。', token);
      return;
    }
    const copy: Uint8Array = new Uint8Array(data.byteLength);
    copy.set(new Uint8Array(data));
    this.chunks.push(copy);
    this.audioBytes += copy.length;
  }

  private async finish(token: number): Promise<void> {
    await this.releaseCapturer();
    if (token !== this.sessionToken || this.settled) return;
    if (this.audioBytes === 0) {
      await this.fail('没有录到语音。', token);
      return;
    }
    const wav: ArrayBuffer = this.wavBytes();
    const config: VoiceInputConfiguration | undefined = this.currentConfig;
    if (config === undefined) {
      await this.fail('语音配置已失效。', token);
      return;
    }
    await this.send(config, wav, token);
  }

  private currentConfig: VoiceInputConfiguration | undefined = undefined;

  private async send(config: VoiceInputConfiguration, wav: ArrayBuffer, token: number): Promise<void> {
    const endpoint: string = this.endpoint(config);
    const model: string = this.model(config);
    const boundary: string = `----msime-${util.generateRandomUUID(false).replace(/-/g, '')}`;
    const body: ArrayBuffer = this.multipart(boundary, model, config.language, wav);
    const request: http.HttpRequest = http.createHttp();
    this.request = request;
    try {
      const response: http.HttpResponse = await request.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          Accept: 'application/json',
          'Content-Type': `multipart/form-data; boundary=${boundary}`,
          Authorization: `Bearer ${config.asr_token.trim()}`
        },
        connectTimeout: 5000,
        readTimeout: 60000,
        extraData: body
      });
      if (token !== this.sessionToken || this.settled) return;
      const outcome: VoiceOutcome = VoiceResponsePolicy.batchResult(response.responseCode,
        typeof response.result === 'string' ? response.result as string : null);
      if (outcome.failure.length > 0) {
        await this.fail(outcome.failure, token);
        return;
      }
      await this.complete(outcome.text, token);
    } catch (error) {
      if (token === this.sessionToken && !this.settled) {
        await this.fail(`语音服务请求失败：${describeError(error)}`, token);
      }
    } finally {
      if (this.request === request) this.request = undefined;
      request.destroy();
    }
  }

  private async complete(text: string, token: number): Promise<void> {
    if (token !== this.sessionToken || this.settled) return;
    this.settled = true;
    this.clearTimeout();
    this.chunks = [];
    this.audioBytes = 0;
    const handler: HttpAsrResultHandler | undefined = this.resultHandler;
    this.resultHandler = undefined;
    this.errorHandler = undefined;
    if (handler !== undefined) handler(text, true);
  }

  private async fail(message: string, token: number): Promise<void> {
    if (token !== this.sessionToken || this.settled) return;
    this.settled = true;
    this.clearTimeout();
    await this.releaseCapturer();
    const request: http.HttpRequest | undefined = this.request;
    this.request = undefined;
    if (request !== undefined) request.destroy();
    this.chunks = [];
    this.audioBytes = 0;
    const handler: HttpAsrErrorHandler | undefined = this.errorHandler;
    this.resultHandler = undefined;
    this.errorHandler = undefined;
    if (handler !== undefined) handler(message);
  }

  private wavBytes(): ArrayBuffer {
    const result: Uint8Array = new Uint8Array(44 + this.audioBytes);
    this.writeAscii(result, 0, 'RIFF');
    this.write32(result, 4, 36 + this.audioBytes);
    this.writeAscii(result, 8, 'WAVEfmt ');
    this.write32(result, 16, 16);
    this.write16(result, 20, 1);
    this.write16(result, 22, 1);
    this.write32(result, 24, SAMPLE_RATE);
    this.write32(result, 28, SAMPLE_RATE * SAMPLE_BYTES);
    this.write16(result, 32, SAMPLE_BYTES);
    this.write16(result, 34, 16);
    this.writeAscii(result, 36, 'data');
    this.write32(result, 40, this.audioBytes);
    let offset: number = 44;
    for (const chunk of this.chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result.buffer as ArrayBuffer;
  }

  private multipart(boundary: string, model: string, language: string, wav: ArrayBuffer): ArrayBuffer {
    const encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
    const head: Uint8Array = encoder.encode(
      `--${boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\n${model}`
      + `\r\n--${boundary}\r\nContent-Disposition: form-data; name="language"\r\n\r\n${this.language(language)}`
      + `\r\n--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="speech.wav"\r\n`
      + 'Content-Type: audio/wav\r\n\r\n');
    const tail: Uint8Array = encoder.encode(`\r\n--${boundary}--\r\n`);
    const audio: Uint8Array = new Uint8Array(wav);
    const result: Uint8Array = new Uint8Array(head.length + audio.length + tail.length);
    result.set(head, 0);
    result.set(audio, head.length);
    result.set(tail, head.length + audio.length);
    return result.buffer as ArrayBuffer;
  }

  private language(value: string): string {
    const language: string = value.trim();
    return language === 'auto' ? '' : language.slice(0, 32);
  }

  private endpoint(config: VoiceInputConfiguration): string {
    const defaults: AsrProviderDefaults | undefined = this.defaults(config.asr_provider);
    return config.asr_endpoint.trim() || (defaults?.endpoint ?? '');
  }

  private model(config: VoiceInputConfiguration): string {
    const defaults: AsrProviderDefaults | undefined = this.defaults(config.asr_provider);
    return config.asr_model.trim() || (defaults?.model ?? '');
  }

  private defaults(provider: string): AsrProviderDefaults | undefined {
    if (provider === 'openai') return PROVIDER_DEFAULTS[0];
    if (provider === 'siliconflow') return PROVIDER_DEFAULTS[1];
    if (provider === 'groq') return PROVIDER_DEFAULTS[2];
    return undefined;
  }

  private validConfig(config: VoiceInputConfiguration): boolean {
    this.currentConfig = config;
    const endpoint: string = this.endpoint(config);
    const model: string = this.model(config);
    const token: string = config.asr_token.trim();
    return (config.asr_provider === 'openai' || config.asr_provider === 'siliconflow'
      || config.asr_provider === 'groq') && endpoint.startsWith('https://')
      && utf8Length(endpoint) <= 2048 && !this.hasControl(endpoint)
      && model.length > 0 && utf8Length(model) <= 512 && !this.hasControl(model)
      && token.length > 0 && utf8Length(token) <= 16384 && !this.hasControl(token);
  }

  private hasControl(value: string): boolean {
    return Array.from(value).some((character: string): boolean => {
      const code: number = character.codePointAt(0) ?? 0;
      return code < 0x20 || (code >= 0x7f && code <= 0x9f);
    });
  }

  private writeAscii(target: Uint8Array, offset: number, value: string): void {
    for (let index = 0; index < value.length; index++) target[offset + index] = value.charCodeAt(index);
  }

  private write16(target: Uint8Array, offset: number, value: number): void {
    target[offset] = value & 0xff;
    target[offset + 1] = (value >>> 8) & 0xff;
  }

  private write32(target: Uint8Array, offset: number, value: number): void {
    target[offset] = value & 0xff;
    target[offset + 1] = (value >>> 8) & 0xff;
    target[offset + 2] = (value >>> 16) & 0xff;
    target[offset + 3] = (value >>> 24) & 0xff;
  }

  private async releaseCapturer(): Promise<void> {
    const capturer: audio.AudioCapturer | undefined = this.capturer;
    this.capturer = undefined;
    if (capturer === undefined) return;
    if (this.readCallback !== undefined) capturer.off('readData', this.readCallback);
    this.readCallback = undefined;
    try {
      await capturer.stop();
    } catch (error) {
      KeyboardLog.error(`Harmony HTTP ASR 音频停止失败：${describeError(error)}`);
    }
    try {
      await capturer.release();
    } catch (error) {
      KeyboardLog.error(`Harmony HTTP ASR 音频释放失败：${describeError(error)}`);
    }
  }

  private clearTimeout(): void {
    if (this.timeoutHandle !== undefined) clearTimeout(this.timeoutHandle);
    this.timeoutHandle = undefined;
  }
}
