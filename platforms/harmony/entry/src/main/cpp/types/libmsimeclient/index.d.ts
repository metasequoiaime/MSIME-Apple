/**
 * Type surface of platforms/harmony/native/client_napi.cpp.
 *
 * Every method takes and returns UTF-8 JSON as an ArkTS string, mirroring the shared C ABI in
 * crates/host-api. Responses carry {"ok":true,"value":...} or {"ok":false,"error":...}; callers parse
 * them rather than relying on exceptions, exactly as the Android NativeClient does.
 */

/** Native ABI revision. The host refuses to run against a version it does not know. */
export const abiVersion: () => number;

/** Capabilities for a named platform, e.g. "harmony". Drives what the shared settings UI renders. */
export const hostCapabilities: (platform: string) => string;

export const loadPreferences: (directory: string) => string;
export const skinCatalog: (directory: string) => string;
/** JSON resource request; returns a structured response containing contentType and byte values. */
export const skinResource: (request: string) => string;
/** JSON stylesheet request; returns a nullable stylesheet in the structured response. */
export const skinToolbarStylesheet: (request: string) => string;
export const savePreferences: (
  directory: string,
  expectedRevision: number,
  snapshot: string,
) => string;
export const dictionary: (request: string) => string;
export const updatePreferences: (handle: number, snapshot: string) => string;
export const typingStatistics: (request: string) => string;
export const emojiCatalog: (query: string, resources: string) => string;
export const candidateGlosses: (request: string, resources: string) => string;
/** `{prefix,limit}` against the packaged English dictionary; no session, safe off the UI thread. */
export const englishCompletions: (request: string, resources: string) => string;
/** Clear the session's Engine candidate cache and refresh its view. */
export const resetCache: (handle: number) => string;
export const translationGlossSave: (request: string, userData: string) => string;
export const translationPlan: (request: string) => string;
export const tencentTranslationHttpRequest: (request: string) => string;
export const niuTransTranslationHttpRequest: (request: string) => string;
export const customTranslationHttpRequest: (request: string) => string;
export const parseTencentTranslationResponse: (body: string, expected: number) => string;
export const parseNiuTransTranslationResponse: (body: string) => string;
export const parseCustomTranslationResponse: (body: string) => string;
export const translationQuery: (handle: number) => string;
export const onlineQuery: (handle: number) => string;
export const cloudRequestUrl: (query: string) => string;
export const aiRequestForQuery: (handle: number, query: string) => string;
export const aiHttpRequest: (request: string) => string;
export const parseAiResponse: (body: string, limit: number) => string;
export const applyCloudResponse: (handle: number, query: string, body: string) => string;
export const applyOnlineCandidates: (
  handle: number,
  query: string,
  candidates: string,
  source: number,
) => string;
export const personalDictionarySync: (options: string) => string;
export const prepareHost: (options: string) => string;

export const snapshotVersion: (options: string) => string;
export const snapshotPrepare: (request: string, file: string) => string;
export const snapshotDiscard: (handle: number) => string;
export const snapshotActivate: (handle: number, expected: string) => string;

export const create: (options: string) => string;
export const destroy: (handle: number) => string;
export const focus: (handle: number, focused: boolean) => string;
export const setNineKeyMode: (handle: number, enabled: boolean) => string;
export const setEnglishMode: (handle: number, enabled: boolean) => string;
/** Whether ASCII is committed as its fullwidth twin, which Ctrl+Shift+F toggles. */
export const setCharacterWidth: (handle: number, fullwidth: boolean) => string;

export const character: (handle: number, ascii: number, shift: boolean) => string;
export const punctuationWithContext: (handle: number, ascii: number, preceding: number) => string;
export const balancePairedPunctuationAfterAutoClose: (handle: number, opening: number) => string;
export const command: (handle: number, command: number) => string;

export const select: (handle: number, generation: number, index: number) => string;
export const selectEdge: (
  handle: number,
  generation: number,
  index: number,
  edge: number,
) => string;
export const selectAnyCandidate: (handle: number, generation: number, index: number) => string;
export const pinCandidate: (handle: number, generation: number, index: number) => string;
export const fixCandidatePosition: (
  handle: number,
  generation: number,
  index: number,
  position: number,
) => string;
export const clearCandidatePosition: (handle: number, generation: number, index: number) => string;
export const removeCandidate: (handle: number, generation: number, index: number) => string;
export const chooseNineKeySpelling: (handle: number, generation: number, index: number) => string;

export const view: (handle: number) => string;
export const allCandidates: (handle: number) => string;
export const applyTranslations: (
  handle: number,
  generation: number,
  translations: string,
) => string;
/** Start/cancel the shared voice generation used to reject stale asynchronous recognition. */
export const voiceStart: (handle: number) => string;
export const voiceCancel: (handle: number) => string;
export const voiceApply: (handle: number, generation: number, text: string) => string;

export interface DoubaoFrameResult {
  last: boolean;
  payload: string;
}

/** Native gzip framing keeps the ArkTS WebSocket adapter free of credential or transcript logging. */
export const doubaoEncodeFrame: (
  messageType: number,
  flags: number,
  sequence: number,
  payload: ArrayBuffer,
) => ArrayBuffer;
export const doubaoDecodeFrame: (frame: ArrayBuffer) => DoubaoFrameResult | null;
