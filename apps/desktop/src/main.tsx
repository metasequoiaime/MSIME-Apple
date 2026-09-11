import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { SettingsPage, type SettingsClient, type Snapshot, type DictionaryClient, type DictionaryEntry } from "@msime/ui";
import "@msime/ui/styles.css";

const dictionary: DictionaryClient = {
  list: (offset, limit) => invoke("dictionary_request", { action: { operation: "list", offset, limit } }),
  edit: (previous: DictionaryEntry | null, replacement: DictionaryEntry | null, request_id: string) => invoke("dictionary_request", { action: { operation: "edit", previous, replacement, request_id } }).then(() => undefined),
};
const client: SettingsClient = {
  load: () => {
    if (!isTauri()) return Promise.reject(new Error("请通过客户端应用打开设置。浏览器预览不会写入本地配置。"));
    return invoke<Snapshot>("load_preferences");
  },
  save: (expectedRevision, preferences) => invoke<Snapshot>("save_preferences", { expectedRevision, preferences }),
  openExternalUrl: url => invoke("open_external_url", { url }),
  copyText: text => invoke("copy_text", { text }),
  openScreenKeyboard: () => invoke("open_keyboard_panel"),
  openHandwriting: () => invoke("open_handwriting_panel"),
  clipboard: {
    clear: () => invoke("clear_clipboard_history"),
    list: () => invoke<string[]>("list_clipboard_history"),
    sync: () => invoke<string[]>("sync_clipboard_history"),
    copy: text => invoke("copy_text", { text }),
  },
  dictionary,
};
createRoot(document.getElementById("root")!).render(<StrictMode><SettingsPage client={client} /></StrictMode>);
