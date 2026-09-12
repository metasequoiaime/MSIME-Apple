import { expect, test, vi } from "vitest";
import { createVoiceRecognitionClient } from "./voice-recognition-client";

test("voice requests and cancellation retain identity across a restart", async () => {
  const pending: { resolve: (value: { text: string }) => void }[] = [];
  const requests: string[] = [];
  const cancelled: string[] = [];
  let publish!: (update: { request_id: string; text: string; final: boolean }) => void;
  const invoke = async <T,>(command: string, args?: Record<string, unknown>): Promise<T> => {
    if (command === "cancel_voice") {
      cancelled.push(args?.requestId as string);
      return undefined as T;
    }
    requests.push((args?.request as { request_id: string }).request_id);
    return new Promise<{ text: string }>(resolve => pending.push({ resolve })) as Promise<T>;
  };
  const stop = vi.fn();
  const client = createVoiceRecognitionClient(invoke, async listener => { publish = listener; return stop; });
  const receive = vi.fn();
  expect(await client.onVoiceUpdate(receive)).toBe(stop);
  const first = client.recognizeVoice("zh-CN");
  publish({ request_id: requests[0], text: "fixture-first", final: false });
  expect(receive).toHaveBeenCalledTimes(1);
  await client.cancelVoice();
  expect(cancelled).toEqual([requests[0]]);
  const second = client.recognizeVoice("zh-CN");
  expect(requests[1]).not.toBe(requests[0]);
  publish({ request_id: requests[0], text: "fixture-stale", final: true });
  pending[0].resolve({ text: "fixture-first-final" });
  await first;
  expect(receive).toHaveBeenCalledTimes(1);
  publish({ request_id: requests[1], text: "fixture-current", final: false });
  expect(receive).toHaveBeenCalledTimes(2);
  pending[1].resolve({ text: "fixture-second-final" });
  await second;
  publish({ request_id: requests[1], text: "fixture-late", final: false });
  expect(receive).toHaveBeenCalledTimes(2);
  await client.cancelVoice();
  expect(cancelled).toHaveLength(1);
});

test("stop retains the request identity for final streaming events", async () => {
  let resolve!: (value: { text: string }) => void;
  let requestId = "";
  let publish!: (update: { request_id: string; text: string; final: boolean }) => void;
  const stops: unknown[] = [];
  const invoke = async <T,>(command: string, args?: Record<string, unknown>): Promise<T> => {
    if (command === "stop_voice") { stops.push(args?.requestId); return undefined as T; }
    requestId = (args?.request as { request_id: string }).request_id;
    return new Promise<{ text: string }>(done => { resolve = done; }) as Promise<T>;
  };
  const client = createVoiceRecognitionClient(invoke, async listener => { publish = listener; return () => {}; });
  const receive = vi.fn();
  await client.onVoiceUpdate(receive);
  const recording = client.recognizeVoice("zh-CN");
  await client.stopVoice();
  expect(stops).toEqual([requestId]);
  publish({ request_id: requestId, text: "fixture-final", final: true });
  expect(receive).toHaveBeenCalledOnce();
  resolve({ text: "fixture-final" });
  await recording;
  await client.stopVoice();
  expect(stops).toHaveLength(1);
});
