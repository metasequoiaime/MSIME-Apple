/** Whether a new provider may claim the keyboard's single microphone session. */
export class VoiceSessionPolicy {
  static canStart(doubao: boolean, httpAsr: boolean, local: boolean, capture: boolean,
    engineBusy: boolean): boolean {
    return !doubao && !httpAsr && !local && !capture && !engineBusy;
  }
}
