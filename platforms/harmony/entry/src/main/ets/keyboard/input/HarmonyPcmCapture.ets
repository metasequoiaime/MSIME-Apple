import audio from '@ohos.multimedia.audio';
import { KeyboardLog, describeError } from '../KeyboardLog';
import { HarmonyVoiceCaptureDevices } from './HarmonyVoiceCaptureDevices';

export type PcmChunkHandler = (data: ArrayBuffer) => void;

/**
 * One 16 kHz mono PCM16 microphone stream for the recognizers that are handed audio rather than opening the microphone themselves: CoreSpeechKit in its write-audio mode and the on-device sherpa-onnx recognizer.
 *
 * Buffers are passed on as they arrive and are not kept here, written to disk or logged. `start` resolves false rather than throwing when `stop` was called while the capturer was being created, so a cancelled start never leaves a live microphone behind.
 */
export class HarmonyPcmCapture {
  private capturer: audio.AudioCapturer | undefined = undefined;
  private readCallback: ((data: ArrayBuffer) => void) | undefined = undefined;
  private generation: number = 0;

  isActive(): boolean {
    return this.capturer !== undefined;
  }

  async start(backend: string, device: string, onChunk: PcmChunkHandler): Promise<boolean> {
    await this.stop();
    const generation: number = ++this.generation;
    // Routing is process-wide rather than per stream, so it is asserted before every capturer; a device that has gone away leaves the system default in place.
    await HarmonyVoiceCaptureDevices.select(backend, device);
    if (generation !== this.generation) return false;
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
    if (generation !== this.generation) {
      await capturer.release();
      return false;
    }
    const readCallback: (data: ArrayBuffer) => void = (data: ArrayBuffer): void => {
      if (generation === this.generation && data.byteLength > 0) onChunk(data);
    };
    this.capturer = capturer;
    this.readCallback = readCallback;
    capturer.on('readData', readCallback);
    try {
      await capturer.start();
    } catch (error) {
      await this.stop();
      throw new Error('Harmony 音频采集启动失败');
    }
    return generation === this.generation;
  }

  /** Stops delivering audio at once and releases the capturer. Safe to call at any time, including while `start` is still pending. */
  async stop(): Promise<void> {
    this.generation++;
    const capturer: audio.AudioCapturer | undefined = this.capturer;
    const readCallback: ((data: ArrayBuffer) => void) | undefined = this.readCallback;
    this.capturer = undefined;
    this.readCallback = undefined;
    if (capturer === undefined) return;
    if (readCallback !== undefined) capturer.off('readData', readCallback);
    try {
      await capturer.stop();
    } catch (error) {
      KeyboardLog.error(`Harmony 音频停止失败：${describeError(error)}`);
    }
    try {
      await capturer.release();
    } catch (error) {
      KeyboardLog.error(`Harmony 音频释放失败：${describeError(error)}`);
    }
  }
}
