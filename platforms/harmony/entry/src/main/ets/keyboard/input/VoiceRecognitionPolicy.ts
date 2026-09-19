/** Bounds and normalizes the text crossing the native speech boundary. */
export const VOICE_MAX_TEXT: number = 4096;
export const VOICE_MAX_LANGUAGE: number = 32;

export class VoiceRecognitionPolicy {
  static language(value: string): string {
    const trimmed: string = value.trim();
    if (trimmed.length === 0) {
      return 'zh-CN';
    }
    return trimmed.slice(0, VOICE_MAX_LANGUAGE);
  }

  static sessionId(generation: number): string {
    const bounded: number = Math.max(1, Math.floor(generation)) % 1000000000;
    return `msime-voice-${bounded}`;
  }

  static result(value: string): string {
    let text: string = value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '');
    text = text.trim();
    return text.slice(0, VOICE_MAX_TEXT);
  }
}
