interface VoiceUpdate { request_id: string; text: string; final: boolean; phase?: "recording" | "recognizing" | "polishing"; }
type Invoke = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;

export function createVoiceRecognitionClient(invoke: Invoke, subscribe: (listener: (update: VoiceUpdate) => void) => Promise<() => void>) {
  let activeRequest: string | undefined;
  return {
    async recognizeVoice(language: string): Promise<{ text: string }> {
      const request_id = crypto.randomUUID();
      activeRequest = request_id;
      try {
        return await invoke("recognize_voice", { request: { language, request_id } });
      } finally {
        if (activeRequest === request_id) activeRequest = undefined;
      }
    },
    async stopVoice(): Promise<void> {
      const requestId = activeRequest;
      if (requestId) await invoke("stop_voice", { requestId });
    },
    async cancelVoice(): Promise<void> {
      const requestId = activeRequest;
      activeRequest = undefined;
      if (requestId) await invoke("cancel_voice", { requestId });
    },
    onVoiceUpdate(listener: (update: { text: string; final: boolean; phase?: "recording" | "recognizing" | "polishing" }) => void) {
      return subscribe(update => {
        if (activeRequest && update.request_id === activeRequest) listener(update);
      });
    },
  };
}
