import { StrictMode } from "react";
import { type ReactNode, useState } from "react";
import { createRoot } from "react-dom/client";
import { SettingsPage, type DictionaryClient, type DictionaryEntry, type DictionaryImportResult,
  type HostCapabilities, type LocalDictionaryFormat, type LocalDictionaryKind, type Preferences,
  type SkinCatalog, type SkinFont, type SkinImage,
  CloudClipboardPanel, CloudDictionaryPanel, CloudDictionaryCatalogPanel, CloudDictionaryFilesPanel, CloudDictionaryApplyPanel,
  CloudCandidatesPanel, type AccountClient, type CloudClipboardPanelClient,
  type CloudDictionaryAction, type CloudDictionaryPanelClient, type SettingsClient, type Snapshot, type TypingStatisticsClient, type TypingStatisticsStatus } from "@msime/ui";
import type { AiAssistantClient, ApiCredentialTestResult, ApiCredentialTestService, MobileKeyboardFeedback, VoiceCaptureDevice } from "@msime/ui";
import "@msime/ui/styles.css";

/**
 * The settings UI, hosted by the HarmonyOS application.
 *
 * Everything the page needs from the system arrives through one object the ArkTS side injects into
 * the Web component. It is deliberately thin: JSON in, JSON out, the same shape the shared C ABI
 * uses, so the bridge has no opinion about preferences and nothing to keep in sync with the schema.
 *
 * Only `load` and `save` are required of a SettingsClient. Everything else on the interface is a
 * capability some host happens to have, and the page renders what the host says it can do rather
 * than what the platform is called, so an unimplemented surface simply does not appear.
 */

interface NativeBridge {
  /** `{"ok":true,"value":{"revision":n,"preferences":{...}}}` or `{"ok":false,"error":"..."}`. */
  loadPreferences(): string;
  savePreferences(expectedRevision: number, document: string): string;
  /** The capability record for this host, as client-core writes it. */
  hostCapabilities(): string;
  scanSkinCatalog(): string;
  readSkinImage(id: string, relative: string): string;
  readSkinFont(id: string, relative: string): string;
  readSkinToolbarCss(id: string): string;
  appVersion(): string;
  dictionary(action: string): string;
  account(action: string): Promise<string>;
  cloudDictionary(action: string): Promise<string>;
  cloudDictionaryDownload(entry: string): string;
  cloudDictionarySnapshot(action: string): Promise<string>;
  typingStatistics(action: string): string;
  aiModels(request: string): Promise<string>;
  aiTest(request: string): Promise<string>;
  testApiCredential(request: string): Promise<string>;
  openExternalUrl(url: string): void;
  copyText(text: string): void;
  openSystemKeyboardSettings(): void;
  /** `{"ok":true,"value":[{backend,id,label},...]}`; a refusal is reported, not an empty list. */
  listVoiceCaptureDevices(): string;
  /** `{"ok":true,"value":["Family",...]}`; a refusal is reported so the page can say so. */
  listFontFamilies(): string;
  /** `{operation:"load"|"save"|"preview",...}`; the reply carries the settings now in force. */
  keyboardFeedback(request: string): string;
}

declare global {
  interface Window {
    msimeHarmony?: NativeBridge;
  }
}

interface Reply<T> {
  ok: boolean;
  value: T;
  error: string;
}

function unwrap<T>(raw: string): T {
  const reply = JSON.parse(raw) as Reply<T>;
  if (!reply.ok) throw new Error(reply.error);
  return reply.value;
}

/**
 * The injected object is not guaranteed to exist the instant the document's script runs, and reading
 * it at module scope would take the whole page down with it when it does not. Wait for it instead,
 * and say so plainly if it never arrives rather than leaving a blank window to be puzzled over.
 */
function whenBridgeReady(): Promise<NativeBridge> {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 5000;
    const poll = () => {
      const native = window.msimeHarmony;
      if (native) { resolve(native); return; }
      if (Date.now() > deadline) { reject(new Error("没有连接到水杉输入法。请从应用中打开设置。")); return; }
      setTimeout(poll, 50);
    };
    poll();
  });
}

function accountClient(native: NativeBridge): AccountClient {
  const request = <T,>(action: Record<string, unknown>): Promise<T> =>
    native.account(JSON.stringify(action)).then(unwrap<T>);
  const user = (value: { id: string; display_name: string; created_at: string }) => ({
    id: value.id, displayName: value.display_name, createdAt: value.created_at
  });
  const profile = (value: { user: { id: string; display_name: string; created_at: string }; identities: { provider: string }[] }) => ({
    user: user(value.user), providers: value.identities.map(identity => identity.provider)
  });
  return {
    status: async () => { const value = await request<{ user: { id: string; display_name: string; created_at: string } | null }>({ operation: "status" }); return { user: value.user ? user(value.user) : null }; },
    providers: async () => { const value = await request<{ providers: Record<string, boolean> }>({ operation: "providers" }); return { email: value.providers.email === true, phone: value.providers.phone === true, apple: value.providers.apple === true }; },
    requestCode: async (provider, target) => { const value = await request<{ challenge_id: string; expires_in: number }>({ operation: "request_code", provider, target }); return { challengeId: value.challenge_id, expiresIn: value.expires_in }; },
    login: async (challengeId, code) => { const value = await request<{ user: { id: string; display_name: string; created_at: string } }>({ operation: "login", challenge_id: challengeId, credential: code }); return { user: value.user ? user(value.user) : null }; },
    profile: async () => profile(await request<{ user: { id: string; display_name: string; created_at: string }; identities: { provider: string }[] }>({ operation: "profile" })),
    rename: async displayName => profile(await request<{ user: { id: string; display_name: string; created_at: string }; identities: { provider: string }[] }>({ operation: "rename", display_name: displayName })),
    logout: async all => { await request({ operation: "logout", all }); },
    deleteAccount: async () => { await request({ operation: "delete_account" }); },
    clearExpired: async () => { await request({ operation: "clear_expired" }); },
  };
}

function cloudClipboardClient(native: NativeBridge, close: () => void): CloudClipboardPanelClient {
  return {
    close: async () => close(),
    copyText: async text => native.copyText(text),
    request: async action => {
      const { operation, ...payload } = action;
      const value = await native.account(JSON.stringify({ operation: "clipboard", clipboard_operation: operation, ...payload }));
      return unwrap<{ items?: { id: string; text: string }[]; enabled?: boolean }>(value);
    },
  };
}

type CloudDictionaryPage = "main" | "catalog" | "candidates" | "files" | "apply";

function cloudDictionaryClient(native: NativeBridge, close: () => void, setPage: (page: CloudDictionaryPage) => void): CloudDictionaryPanelClient {
  type Response = Awaited<ReturnType<CloudDictionaryPanelClient["request"]>>;
  return {
    close: async () => close(),
    back: async () => setPage("main"),
    openCatalog: async () => setPage("catalog"),
    openCandidates: async () => setPage("candidates"),
    openFiles: async () => setPage("files"),
    openApply: async () => setPage("apply"),
    snapshot: true,
    snapshotNative: true,
    downloadToLocal: async entry => {
      unwrap<{ applied: boolean }>(native.cloudDictionaryDownload(JSON.stringify(entry)));
    },
    request: async (action: CloudDictionaryAction) => {
      const { operation, ...payload } = action;
      if (operation.startsWith("snapshot_")) {
        const snapshot = await native.cloudDictionarySnapshot(JSON.stringify(action));
        return unwrap<Response>(snapshot);
      }
      const value = await native.cloudDictionary(JSON.stringify({ operation: "dictionary", dictionary_operation: operation, ...payload }));
      return unwrap<Response>(value);
    },
  };
}

function makeClient(native: NativeBridge, openCloudClipboard: () => void, openCloudDictionary: () => void): SettingsClient {
  const dictionaryReply = <T,>(action: Record<string, unknown>): T =>
    unwrap<T>(native.dictionary(JSON.stringify(action)));
  const dictionary: DictionaryClient = {
    list: async (offset: number, limit: number, kind?: LocalDictionaryKind, query?: string) =>
      dictionaryReply<{ entries: DictionaryEntry[]; has_more: boolean }>({
        operation: "list", offset, limit, ...(kind ? { kind } : {}), ...(query ? { query } : {})
      }),
    edit: async (previous: DictionaryEntry | null, replacement: DictionaryEntry | null,
                 request_id: string) => {
      dictionaryReply<{ applied: boolean }>({ operation: "edit", previous, replacement, request_id });
    },
    import: async (kind: LocalDictionaryKind, format: LocalDictionaryFormat, text: string,
                   request_id: string): Promise<DictionaryImportResult> =>
      dictionaryReply<DictionaryImportResult>({ operation: "import", kind, format, text, request_id }),
    export: async (kind: LocalDictionaryKind, format: Exclude<LocalDictionaryFormat, "rime" | "hans">,
                   offset: number, limit: number) =>
      dictionaryReply<{ text: string; has_more: boolean }>({ operation: "export", kind, format, offset, limit }),
    retry: async (request_id: string) => {
      dictionaryReply<{ applied: boolean }>({ operation: "retry", request_id });
    },
    dismissFailure: async (request_id: string) => {
      dictionaryReply<{ applied: boolean }>({ operation: "dismiss_failure", request_id });
    },
  };
  const typingStatistics: TypingStatisticsClient = {
    load: async () => unwrap<TypingStatisticsStatus>(native.typingStatistics(JSON.stringify({ operation: "load" }))),
    setEnabled: async (enabled: boolean) => unwrap<TypingStatisticsStatus>(native.typingStatistics(JSON.stringify({ operation: "set_enabled", enabled }))),
    reset: async () => unwrap<TypingStatisticsStatus>(native.typingStatistics(JSON.stringify({ operation: "reset" }))),
  };
  const aiAssistant: AiAssistantClient = {
    fetchModels: configuration => native.aiModels(JSON.stringify(configuration))
      .then(unwrap<string[]>),
    test: configuration => native.aiTest(JSON.stringify(configuration)).then(unwrap<string>),
  };
  const testApiCredential = async (service: ApiCredentialTestService,
    config: Record<string, unknown>): Promise<ApiCredentialTestResult> =>
    unwrap<ApiCredentialTestResult>(await native.testApiCredential(JSON.stringify({ service, config })));
  return {
    // Wrapped like every other reply from the shared ABI. Reading it as the record itself leaves every
    // capability undefined, which the page reads as "this host cannot", and the whole surface silently
    // shrinks to the few controls that have no capability behind them.
    host: unwrap<HostCapabilities>(native.hostCapabilities()),
    load: async () => unwrap<Snapshot>(native.loadPreferences()),
    save: async (revision: number, preferences: Preferences) => {
      // The revision sent is the one the page read; the document carries the next. The store compares
      // the former against what is on disk and refuses the save if the keyboard moved in between.
      const document = JSON.stringify({ revision: revision + 1, preferences });
      return unwrap<Snapshot>(native.savePreferences(revision, document));
    },
    readAppVersion: async () => native.appVersion(),
    scanSkinCatalog: async () => unwrap<SkinCatalog>(native.scanSkinCatalog()),
    readSkinImage: async (id: string, relative: string) =>
      unwrap<SkinImage>(native.readSkinImage(id, relative)),
    readSkinFont: async (id: string, relative: string) =>
      unwrap<SkinFont>(native.readSkinFont(id, relative)),
    readSkinToolbarCss: async (id: string) =>
      unwrap<string | null>(native.readSkinToolbarCss(id)),
    openExternalUrl: async (url: string) => native.openExternalUrl(url),
    copyText: async (text: string) => native.copyText(text),
    openSystemKeyboardSettings: async () => native.openSystemKeyboardSettings(),
    listVoiceCaptureDevices: async () => unwrap<VoiceCaptureDevice[]>(native.listVoiceCaptureDevices()),
    listFontFamilies: async () => unwrap<string[]>(native.listFontFamilies()),
    mobileKeyboardFeedback: {
      load: async () => unwrap<MobileKeyboardFeedback>(
        native.keyboardFeedback(JSON.stringify({ operation: "load" }))),
      save: async settings => unwrap<MobileKeyboardFeedback>(
        native.keyboardFeedback(JSON.stringify({ operation: "save", settings }))),
      preview: async strength => {
        unwrap<MobileKeyboardFeedback>(
          native.keyboardFeedback(JSON.stringify({ operation: "preview", strength })));
      },
    },
    dictionary,
    typingStatistics,
    aiAssistant,
    testApiCredential,
    // Four surfaces the keyboard already honours. Each writes shared preferences and nothing else,
    // so opting in is all that was ever needed; without it the page saved nothing and the keyboard
    // went on reading defaults the user had no way to change.
    fuzzyPinyin: true,
    touchKeyboardSchemes: true,
    customTouchKeyboardSkins: true,
    candidateEnglishGloss: true,
    account: accountClient(native),
    openCloudClipboard: async () => openCloudClipboard(),
    openCloudDictionary: async () => openCloudDictionary(),
  };
}

function HarmonySettings({ native }: { native: NativeBridge }): ReactNode {
  const [cloudClipboardOpen, setCloudClipboardOpen] = useState(false);
  const [cloudDictionaryOpen, setCloudDictionaryOpen] = useState(false);
  const [cloudDictionaryPage, setCloudDictionaryPage] = useState<CloudDictionaryPage>("main");
  const client = makeClient(native, () => setCloudClipboardOpen(true), () => { setCloudDictionaryPage("main"); setCloudDictionaryOpen(true); });
  const dictionaryClient = cloudDictionaryClient(native, () => setCloudDictionaryOpen(false), setCloudDictionaryPage);
  // Harmony's native snapshot path is an apply-to-device flow. The shared Files panel's
  // restore-to-cloud controls need a different provider capability and must stay hidden here.
  const filesClient: CloudDictionaryPanelClient = { ...dictionaryClient, snapshot: false, snapshotNative: false };
  return <>
    <SettingsPage client={client} />
    {cloudClipboardOpen && <CloudClipboardPanel client={cloudClipboardClient(native, () => setCloudClipboardOpen(false))} />}
    {cloudDictionaryOpen && cloudDictionaryPage === "main" && <CloudDictionaryPanel client={dictionaryClient} />}
    {cloudDictionaryOpen && cloudDictionaryPage === "catalog" && <CloudDictionaryCatalogPanel client={dictionaryClient} />}
    {cloudDictionaryOpen && cloudDictionaryPage === "candidates" && <CloudCandidatesPanel client={dictionaryClient} />}
    {cloudDictionaryOpen && cloudDictionaryPage === "files" && <CloudDictionaryFilesPanel client={filesClient} />}
    {cloudDictionaryOpen && cloudDictionaryPage === "apply" && <CloudDictionaryApplyPanel client={dictionaryClient} />}
  </>;
}

const root = document.getElementById("root");
if (root) {
  whenBridgeReady().then(native => {
    createRoot(root).render(
      <StrictMode><HarmonySettings native={native} /></StrictMode>
    );
  }).catch((error: Error) => {
    // A blank window explains nothing. This is the one failure the page has to render itself,
    // because it is the failure that means none of the rest of it can be rendered at all.
    root.textContent = error.message;
    root.setAttribute("style", "padding:24px;font:16px system-ui;color:#c0392b");
  });
}
