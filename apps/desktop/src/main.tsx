import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { SettingsPage, type SettingsClient, type Snapshot, type DictionaryClient, type DictionaryEntry, type ExternalSkinSummary } from "@msime/ui";
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
  dictionary,
  about: { openExternalUrl: url => invoke("open_external_url", { url }) },
  feedback: { openExternalUrl: url => invoke("open_external_url", { url }) },
  update: { check: () => invoke<{ found: boolean; version?: string; installer_name?: string; installer_sha256?: string; signed?: boolean }>("check_for_updates") },
  diagnostics: {
    server: enabled => invoke("set_diagnostic_log", { scope: "server", enabled }),
    tsf: enabled => invoke("set_diagnostic_log", { scope: "tsf", enabled }),
    state: scope => invoke<boolean>("get_diagnostic_log", { scope }),
  },
  clipboard: { clear: () => invoke("clear_clipboard_history"), list: () => invoke<string[]>("list_clipboard_history"), copy: text => invoke("copy_text", { text }) },
  screen_keyboard: { open: () => invoke("open_screen_keyboard") },
  handwriting: { open: () => invoke("open_handwriting") },
  skin: {
    openDirectory: () => invoke("open_skin_directory"),
    refresh: () => invoke("refresh_skin_catalog"),
    list: () => invoke<ExternalSkinSummary[]>("list_external_skins"),
    selected: () => invoke<string | null>("selected_skin"),
    select: id => invoke("select_skin", { id }),
  },
};
createRoot(document.getElementById("root")!).render(<StrictMode><SettingsPage client={client} /></StrictMode>);
