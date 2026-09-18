import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { SettingsPage, type DictionaryClient, type DictionaryEntry, type DictionaryImportResult,
  type HostCapabilities, type LocalDictionaryFormat, type LocalDictionaryKind, type Preferences,
  type SettingsClient, type Snapshot } from "@msime/ui";
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
  appVersion(): string;
  dictionary(action: string): string;
  openExternalUrl(url: string): void;
  copyText(text: string): void;
  openSystemKeyboardSettings(): void;
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

function makeClient(native: NativeBridge): SettingsClient {
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
    openExternalUrl: async (url: string) => native.openExternalUrl(url),
    copyText: async (text: string) => native.copyText(text),
    openSystemKeyboardSettings: async () => native.openSystemKeyboardSettings(),
    dictionary,
  };
}

const root = document.getElementById("root");
if (root) {
  whenBridgeReady().then(native => {
    createRoot(root).render(
      <StrictMode>
        <SettingsPage client={makeClient(native)} />
      </StrictMode>
    );
  }).catch((error: Error) => {
    // A blank window explains nothing. This is the one failure the page has to render itself,
    // because it is the failure that means none of the rest of it can be rendered at all.
    root.textContent = error.message;
    root.setAttribute("style", "padding:24px;font:16px system-ui;color:#c0392b");
  });
}
