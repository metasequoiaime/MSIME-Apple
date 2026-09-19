import { speechRecognizer } from '@kit.CoreSpeechKit';
import { VoiceRecognitionPolicy } from './VoiceRecognitionPolicy';
import { HarmonyDoubaoRecognizer } from './HarmonyDoubaoRecognizer';
import { HarmonyHttpAsrRecognizer } from './HarmonyHttpAsrRecognizer';
import { HarmonyVoicePolisher } from './HarmonyVoicePolisher';
import { VoiceInputConfiguration } from './VoiceInputConfiguration';

export type VoiceResultHandler = (text: string, final: boolean) => void;
export type VoiceErrorHandler = (message: string) => void;

/**
 * Harmony's native speech boundary. It deliberately keeps audio inside CoreSpeechKit: no raw
 * microphone data is copied into the Engine, written to disk, or included in logs. The recognizer
 * is recreated only after shutdown, and callbacks are accepted only for the active bounded session.
 */
export class HarmonyVoiceRecognizer {
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private sessionId: string = '';
  private generation: number = 0;
  private resultHandler: VoiceResultHandler | undefined = undefined;
  private errorHandler: VoiceErrorHandler | undefined = undefined;
  private readonly doubao: HarmonyDoubaoRecognizer = new HarmonyDoubaoRecognizer();
  private readonly httpAsr: HarmonyHttpAsrRecognizer = new HarmonyHttpAsrRecognizer();
  private readonly polisher: HarmonyVoicePolisher = new HarmonyVoicePolisher();
  private polishGeneration: number = 0;
  private lastResultText: string = '';
  private finalDelivered: boolean = false;

  async start(language: string, config: VoiceInputConfiguration, onResult: VoiceResultHandler,
    onError: VoiceErrorHandler): Promise<void> {
    const doubaoProvider: boolean = config.asr_provider === 'doubao'
      && config.asr_token.trim().length > 0;
    const httpProvider: boolean = config.asr_provider === 'openai'
      || config.asr_provider === 'siliconflow' || config.asr_provider === 'groq';
    if (doubaoProvider && this.doubao.isActive()) throw new Error('豆包语音识别正在进行');
    if (httpProvider && this.httpAsr.isActive()) throw new Error('语音识别正在进行');
    if (config.asr_provider !== 'doubao' && !httpProvider && config.asr_provider !== 'system'
      && config.asr_provider.length > 0) {
      throw new Error('当前 Harmony 尚未支持该云端语音服务');
    }
    if (this.engine !== undefined && this.engine.isBusy()) {
      throw new Error('语音识别正在进行');
    }
    this.resultHandler = onResult;
    this.errorHandler = onError;
    this.lastResultText = '';
    this.finalDelivered = false;
    this.polishGeneration += 1;
    const deliver: VoiceResultHandler = (text: string, final: boolean): void => {
      this.deliver(config, text, final);
    };
    if (doubaoProvider) {
      await this.doubao.start(config, deliver, onError);
      return;
    }
    if (httpProvider) {
      await this.httpAsr.start(config, deliver, onError);
      return;
    }
    this.generation = (this.generation + 1) % 1000000000;
    this.sessionId = VoiceRecognitionPolicy.sessionId(this.generation);
    if (this.engine === undefined) {
      this.engine = await speechRecognizer.createEngine({
        language: VoiceRecognitionPolicy.language(language),
        // CoreSpeechKit's offline recognizer is the platform-specific Harmony path.
        online: 1,
        extraParams: { recognizerMode: 'short' }
      });
      this.engine.setListener({
        onStart: (): void => {},
        onEvent: (): void => {},
        onResult: (session: string, result: speechRecognizer.SpeechRecognitionResult): void => {
          if (session !== this.sessionId || this.resultHandler === undefined) {
            return;
          }
          this.deliver(config, result.result, result.isFinal);
        },
        onComplete: (session: string): void => {
          if (session === this.sessionId) this.deliver(config, this.lastResultText, true);
        },
        onError: (session: string, code: number, message: string): void => {
          if (session === this.sessionId && this.errorHandler !== undefined) {
            this.errorHandler(`语音识别失败（${code}）`);
          }
        }
      });
    }
    this.engine.startListening({
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16
      },
      extraParams: { recognizerMode: 'short' }
    });
  }

  stop(): void {
    if (this.doubao.isActive()) {
      this.doubao.stop();
      return;
    }
    if (this.httpAsr.isActive()) {
      this.httpAsr.stop();
      return;
    }
    if (this.engine !== undefined && this.sessionId.length > 0) {
      this.engine.finish(this.sessionId);
    }
  }

  cancel(): void {
    this.polishGeneration += 1;
    this.polisher.cancel();
    this.doubao.cancel();
    this.httpAsr.cancel();
    if (this.engine !== undefined && this.sessionId.length > 0) {
      this.engine.cancel(this.sessionId);
    }
    this.sessionId = '';
    this.lastResultText = '';
    this.finalDelivered = false;
  }

  shutdown(): void {
    this.polishGeneration += 1;
    this.polisher.cancel();
    this.doubao.shutdown();
    this.httpAsr.shutdown();
    try {
      this.cancel();
    } catch (error) {
      // A recognizer that already completed rejects cancel; shutdown must still release it.
      this.sessionId = '';
    }
    if (this.engine !== undefined) {
      try {
        this.engine.shutdown();
      } catch (error) {
        // The service may already have released a failed engine.
      }
      this.engine = undefined;
    }
    this.resultHandler = undefined;
    this.errorHandler = undefined;
  }

  private deliver(config: VoiceInputConfiguration, text: string, final: boolean): void {
    const handler: VoiceResultHandler | undefined = this.resultHandler;
    if (handler === undefined) return;
    const normalized: string = VoiceRecognitionPolicy.result(text);
    if (!final) {
      if (normalized.length > 0) this.lastResultText = normalized;
      handler(normalized, false);
      return;
    }
    if (this.finalDelivered) return;
    this.finalDelivered = true;
    const finalText: string = normalized.length > 0 ? normalized : this.lastResultText;
    if (finalText.length === 0 || (!config.polish_enabled && !config.polish_text)) {
      handler(finalText, true);
      return;
    }
    const polishGeneration: number = ++this.polishGeneration;
    void this.polisher.polish(config, finalText).then((polished: string | null): void => {
      if (polishGeneration !== this.polishGeneration || this.resultHandler === undefined) return;
      handler(polished ?? finalText, true);
    }).catch((): void => {
      if (polishGeneration === this.polishGeneration && this.resultHandler !== undefined) {
        handler(finalText, true);
      }
    });
  }
}
