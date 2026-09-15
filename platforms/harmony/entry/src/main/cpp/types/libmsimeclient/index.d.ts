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
export const savePreferences: (directory: string, expectedRevision: number, snapshot: string) => string;
export const updatePreferences: (handle: number, snapshot: string) => string;
export const typingStatistics: (request: string) => string;
export const emojiCatalog: (query: string, resources: string) => string;
export const candidateGlosses: (request: string, resources: string) => string;
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

export const character: (handle: number, ascii: number, shift: boolean) => string;
export const punctuationWithContext: (handle: number, ascii: number, preceding: number) => string;
export const command: (handle: number, command: number) => string;

export const select: (handle: number, generation: number, index: number) => string;
export const selectAnyCandidate: (handle: number, generation: number, index: number) => string;
export const pinCandidate: (handle: number, generation: number, index: number) => string;
export const fixCandidatePosition: (handle: number, generation: number, index: number, position: number) => string;
export const clearCandidatePosition: (handle: number, generation: number, index: number) => string;
export const removeCandidate: (handle: number, generation: number, index: number) => string;
export const chooseNineKeySpelling: (handle: number, generation: number, index: number) => string;

export const view: (handle: number) => string;
export const allCandidates: (handle: number) => string;
export const applyTranslations: (handle: number, generation: number, translations: string) => string;
