import { createVoiceRecognitionClient } from "./voice/voice-recognition-client";
import { StrictMode, useEffect, useRef, useState, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { getVersion } from "@tauri-apps/api/app";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  CloudCandidatesPanel,
  CloudClipboardPanel,
  CloudDictionaryApplyPanel,
  CloudDictionaryCatalogPanel,
  CloudDictionaryFilesPanel,
  CloudDictionaryPanel,
  EmojiPanel,
  HandwritingPanel,
  VoicePanel,
  SettingsPage,
  SettingsStartupPage,
  WelcomeFlowPage,
  LinuxSetupPage,
  useCandidatePreviewTheme,
  type AccountClient,
  type ApiCredentialTestResult,
  type ApiCredentialTestService,
  type ClipboardHistoryEntry,
  type CloudClipboardAction,
  type CloudClipboardPanelClient,
  type CloudDictionaryAction,
  type CloudDictionaryEntry,
  type CloudDictionaryPanelClient,
  type EmojiCatalogGroup,
  type EmojiPanelClient,
  type HostCapabilities,
  type ProviderCredentialClient,
  type ProviderCredentialStatus,
  type TypingStatisticsClient,
  type PanelClient,
  type VoicePanelClient,
  type Preferences,
  type SettingsClient,
  type Snapshot,
  type DictionaryClient,
  type DictionaryEntry,
  type LocalDictionaryKind,
  type LocalDictionaryFormat,
  type OnboardingActions,
  type OnboardingInputScheme,
  type LinuxSetupClient,
  type LinuxSetupLine,
  type LinuxSetupStatus,
} from "@msime/ui";
import "@msime/ui/styles.css";
import { subscribeWindowState } from "./input/window-state";
import { discoverFontReader } from "./candidate/system-font-client";
import { DesktopKeyboard } from "./input/desktop-keyboard";
import { DesktopCloudDictionary } from "./dictionary/desktop-cloud-dictionary";
import { testDesktopApiCredential } from "./account/credential-test-client";
import { cloudDictionaryCapabilities, isMobileHost } from "./input/mobile-host-capabilities";
import { createMobileHostServices } from "./core/mobile-host-services";

const dictionary: DictionaryClient = {
  // kind and query are omitted when absent so an older host still sees the
  // request shape it knows.
  list: (offset, limit, kind, query) =>
    invoke("dictionary_request", {
      action: {
        operation: "list",
        offset,
        limit,
        ...(kind ? { kind } : {}),
        ...(query ? { query } : {}),
      },
    }),
  edit: (
    previous: DictionaryEntry | null,
    replacement: DictionaryEntry | null,
    request_id: string,
  ) =>
    invoke("dictionary_request", {
      action: { operation: "edit", previous, replacement, request_id },
    }).then(() => undefined),
  import: (
    kind: LocalDictionaryKind,
    format: LocalDictionaryFormat,
    text: string,
    request_id: string,
  ) =>
    invoke("dictionary_request", {
      action: { operation: "import", kind, format, text, request_id },
    }),
  export: (
    kind: LocalDictionaryKind,
    format: Exclude<LocalDictionaryFormat, "rime" | "hans">,
    offset: number,
    limit: number,
  ) =>
    invoke("dictionary_request", { action: { operation: "export", kind, format, offset, limit } }),
  retry: (request_id) =>
    invoke("dictionary_request", { action: { operation: "retry", request_id } }).then(
      () => undefined,
    ),
  dismissFailure: (request_id) =>
    invoke("dictionary_request", { action: { operation: "dismiss_failure", request_id } }).then(
      () => undefined,
    ),
};
const mobileDictionary: DictionaryClient = {
  ...dictionary,
  importPersonal: (text: string, request_id: string) =>
    invoke("dictionary_request", { action: { operation: "import_personal", text, request_id } }),
};

async function downloadCloudEntryToLocal(
  entry: CloudDictionaryEntry,
  dictionaryClient: DictionaryClient,
): Promise<void> {
  if (!dictionaryClient.importPersonal)
    throw new Error("personal dictionary import is unavailable");
  const text = JSON.stringify({
    format: "msime-personal-dictionary",
    version: 1,
    entries: [
      {
        kind: entry.kind === "quick" ? "quickPhrase" : entry.kind,
        key: entry.code,
        value: entry.word,
        weight: entry.weight,
      },
    ],
  });
  await dictionaryClient.importPersonal(text, `ui-cloud-download-${Date.now()}`);
}
const linuxSetupClient: LinuxSetupClient = {
  run: async (download, onLine) => {
    const unlisten = await listen<LinuxSetupLine>("linux-setup-output", (event) =>
      onLine(event.payload),
    );
    try {
      return await invoke<LinuxSetupStatus>("run_linux_setup", { download });
    } finally {
      unlisten();
    }
  },
};
const typingStatistics: TypingStatisticsClient = {
  load: () => invoke("load_typing_statistics"),
  setEnabled: (enabled: boolean) => invoke("set_typing_statistics_enabled", { enabled }),
  setRetention: (retention: string) => invoke("set_typing_statistics_retention", { retention }),
  reset: () => invoke("reset_typing_statistics"),
};
const client: SettingsClient = {
  readAppVersion: getVersion,
  resolveFontFamilies: (names) => invoke("resolve_font_families", { names }),
  scanSkinCatalog: () => invoke("scan_skin_catalog"),
  readSkinToolbarCss: (id, relative) =>
    relative
      ? invoke("read_skin_stylesheet", { id, relative })
      : invoke("read_skin_toolbar_stylesheet", { id }),
  readSkinImage: (id, relative) => invoke("read_skin_image", { id, relative }),
  readSkinFont: (id, relative) => invoke("read_skin_font", { id, relative }),
  openSkinDirectory: () => invoke("open_skin_directory"),
  // The reference tells the user to drop this file into the profile directory. On macOS that directory
  // is inside ~/Library, which the Finder hides, so the page edits it instead.
  customTranslations: {
    load: () => invoke("read_custom_translations"),
    save: (text) => invoke("write_custom_translations", { text }),
  },
  load: () => {
    if (!isTauri())
      return Promise.reject(new Error("请通过客户端应用打开设置。浏览器预览不会写入本地配置。"));
    return invoke<Snapshot>("load_preferences");
  },
  save: (expectedRevision, preferences) =>
    invoke<Snapshot>("save_preferences", { expectedRevision, preferences }),
  onPreferencesChanged: (listener) =>
    listen<Snapshot>("preferences-changed", (event) => listener(event.payload)),
  openExternalUrl: (url) => invoke("open_external_url", { url }),
  openThirdPartyLicenses: () => invoke("open_third_party_licenses"),
  loadMacosShuangpinKeymap: () => invoke<boolean>("load_macos_shuangpin_keymap"),
  saveMacosShuangpinKeymap: (enabled) => invoke("save_macos_shuangpin_keymap", { enabled }),
  loadMacosWubiAutoCommitUnique: () => invoke<boolean>("load_macos_wubi_auto_commit_unique"),
  saveMacosWubiAutoCommitUnique: (enabled) =>
    invoke("save_macos_wubi_auto_commit_unique", { enabled }),
  copyText: (text) => invoke("copy_text", { text }),
  openScreenKeyboard: () => invoke("open_keyboard_panel"),
  openHandwriting: () => invoke("open_handwriting_panel"),
  listVoiceCaptureDevices: () => invoke("list_voice_capture_devices"),
  openVoice: () => invoke("open_voice_panel"),
  openCloudClipboard: () => invoke("open_cloud_clipboard_panel"),
  openCloudDictionary: () => invoke("open_cloud_dictionary_panel"),
  restartInputMethod: () => invoke("restart_input_method"),
  installInputSource: () => invoke("install_input_source"),
  uninstallInputSource: (removeUserData) => invoke("uninstall_input_source", { removeUserData }),
  dataDirectory: {
    status: () => invoke("data_directory_status"),
    pick: () => invoke("pick_data_directory"),
    move: () => invoke("move_data_directory"),
  },
  pickVoiceModelPath: () => invoke("pick_voice_model_path"),
  windowControl: async (action) => {
    const window = getCurrentWindow();
    if (action === "minimize") return window.minimize();
    if (action === "close") return window.close();
    if (action === "restore") return window.unmaximize();
    return window.maximize();
  },
  beginWindowDrag: () => getCurrentWindow().startDragging(),
  resizeWindow: (edge) =>
    getCurrentWindow().startResizeDragging(
      {
        n: "North",
        s: "South",
        e: "East",
        w: "West",
        ne: "NorthEast",
        nw: "NorthWest",
        se: "SouthEast",
        sw: "SouthWest",
      }[edge] as Parameters<ReturnType<typeof getCurrentWindow>["startResizeDragging"]>[0],
    ),
  onWindowStateChanged: (listener, onError) =>
    subscribeWindowState(getCurrentWindow(), listener, onError),
  clipboard: {
    clear: () => invoke("clear_clipboard_history"),
    list: () => invoke<ClipboardHistoryEntry[]>("list_clipboard_history"),
    sync: () => invoke<ClipboardHistoryEntry[]>("sync_clipboard_history"),
    copy: (text) => invoke("copy_text", { text }),
    remove: (text) => invoke("remove_clipboard_history", { text }),
    setPinned: (text, pinned) => invoke("set_clipboard_history_pinned", { text, pinned }),
  },
  dictionary,
  resetLearnedData: () =>
    invoke("dictionary_request", { action: { operation: "reset" } }).then(() => undefined),
  loadDefaultPreferences: () => invoke<Preferences>("restored_default_preferences"),
  /* mobile host services are injected after host_capabilities resolves */
};
const panelClients: {
  keyboard: PanelClient;
  handwriting: PanelClient;
  voice: VoicePanelClient;
  cloudClipboard: CloudClipboardPanelClient;
  cloudDictionary: CloudDictionaryPanelClient;
  emoji: EmojiPanelClient;
} = {
  keyboard: {
    beginWindowDrag: () => getCurrentWindow().startDragging(),
    close: () => invoke("close_panel", { label: "keyboard-panel" }),
    openVoice: () => invoke("open_voice_panel"),
    rememberInputTarget: () => invoke("remember_input_target"),
    sendKey: (request) => invoke("send_key", { request }),
  },
  handwriting: {
    beginWindowDrag: () => getCurrentWindow().startDragging(),
    close: () => invoke("close_panel", { label: "handwriting-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    recognizeHandwriting: (request) => invoke("recognize_handwriting", { request }),
    submitHandwritingCandidate: (candidate) =>
      invoke("submit_handwriting_candidate", { candidate }),
    copyHandwritingCandidate: (text) => invoke("copy_text", { text }),
  },
  voice: {
    maxSubmitBytes: 4096,
    beginWindowDrag: () => getCurrentWindow().startDragging(),
    close: () => invoke("close_panel", { label: "voice-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    loadVoiceLanguage: () => invoke<string>("voice_input_language"),
    ...createVoiceRecognitionClient(invoke, (listener) =>
      listen<{
        request_id: string;
        text: string;
        final: boolean;
        phase?: "recording" | "recognizing" | "polishing";
        level?: number;
      }>("voice-update", (event) => listener(event.payload)),
    ),
    sendText: (text) => invoke("send_text", { text }),
    sendVoiceText: (text) => invoke("send_voice_text", { text }),
    copyText: (text) => invoke("copy_text", { text }),
  },
  cloudClipboard: {
    canSendText: () => invoke<boolean>("cloud_clipboard_can_send_text"),
    close: () => invoke("close_panel", { label: "cloud-clipboard-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    sendText: (text) => invoke("send_text", { text }),
    copyText: (text) => invoke("copy_text", { text }),
    request: (action: CloudClipboardAction) => invoke("cloud_clipboard_request", { action }),
  },
  cloudDictionary: {
    close: () => invoke("close_panel", { label: "cloud-dictionary-panel" }),
    request: (action: CloudDictionaryAction) => invoke("cloud_dictionary_request", { action }),
  },
  emoji: {
    close: () => invoke("close_panel", { label: "emoji-panel" }),
    rememberInputTarget: () => invoke("remember_input_target"),
    sendText: (text) => invoke("send_text", { text }),
    copyText: (text) => invoke("copy_text", { text }),
    loadCatalog: () =>
      invoke<{
        emoji: EmojiCatalogGroup[];
        kaomoji: EmojiCatalogGroup[];
        symbols: EmojiCatalogGroup[];
        unavailable?: ("emoji" | "kaomoji" | "symbols")[];
      }>("load_emoji_catalog"),
    clipboard: {
      list: () =>
        invoke<ClipboardHistoryEntry[]>("list_clipboard_history").then((entries) =>
          entries.map((entry) => entry.text),
        ),
      isEnabled: async () => (await client.load()).preferences.clipboard_history ?? false,
      enable: async () => {
        const snapshot = await client.load();
        if (!snapshot.preferences.clipboard_history) {
          await client.save(snapshot.revision, {
            ...snapshot.preferences,
            clipboard_history: true,
          });
        }
      },
      onChanged: async (listener) => {
        const stopHistory = await listen("clipboard-history-changed", () => listener());
        try {
          const stopPreferences = await listen("preferences-changed", () => listener());
          return () => {
            stopHistory();
            stopPreferences();
          };
        } catch (error) {
          stopHistory();
          throw error;
        }
      },
      remove: (text) => invoke("remove_clipboard_history", { text }),
      clear: () => invoke("clear_clipboard_history"),
      sync: () =>
        invoke<ClipboardHistoryEntry[]>("sync_clipboard_history").then((entries) =>
          entries.map((entry) => entry.text),
        ),
      copy: (text) => invoke("copy_text", { text }),
    },
  },
};
const panel = new URLSearchParams(window.location.search).get("panel");
function DesktopPanelTheme({
  preferences,
  surface,
  children,
}: {
  preferences: Pick<SettingsClient, "load" | "onPreferencesChanged">;
  surface: "handwriting" | "voice" | "emoji";
  children: (theme: "dark" | "light") => ReactNode;
}) {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    let latestRevision = -1;
    const apply = (value: Snapshot) => {
      if (!active || value.revision <= latestRevision) return;
      latestRevision = value.revision;
      setSnapshot(value);
    };
    const start = async () => {
      try {
        const stop = await preferences.onPreferencesChanged?.(apply);
        if (!active) {
          stop?.();
          return;
        }
        unsubscribe = stop;
      } catch {
        /* Initial loading still works when event subscription is unavailable. */
      }
      if (active) {
        try {
          apply(await preferences.load());
        } catch {
          /* Keep the dark panel default. */
        }
      }
    };
    void start();
    return () => {
      active = false;
      unsubscribe?.();
    };
  }, [preferences]);
  const surfaceTheme =
    surface === "handwriting"
      ? snapshot?.preferences.handwriting_theme
      : surface === "voice"
        ? snapshot?.preferences.voice_theme
        : snapshot?.preferences.emoji_theme;
  return children(useCandidatePreviewTheme(snapshot?.preferences.theme, surfaceTheme));
}
// The host reports what it supports. Typing statistics were previously gated on
// an Android user-agent match, which left the category dead on every desktop
// even though the commands were registered.
async function discoverHostCapabilities(): Promise<HostCapabilities | null> {
  if (!isTauri()) return null;
  try {
    return await invoke<HostCapabilities>("host_capabilities");
  } catch {
    return null; // A host without the command keeps its previous behaviour.
  }
}

function DesktopSettings() {
  const [settingsClient, setSettingsClient] = useState<SettingsClient | null>(null);
  const [bootstrapRequired, setBootstrapRequired] = useState<boolean | null>(null);
  const [linuxSetup, setLinuxSetup] = useState<LinuxSetupStatus | null>(null);
  const [replayOnboarding, setReplayOnboarding] = useState(false);
  const [mobilePanel, setMobilePanel] = useState<
    | "voice"
    | "emoji"
    | "clipboard"
    | "cloud-clipboard"
    | "cloud-dictionary"
    | "cloud-dictionary-catalog"
    | "cloud-candidates"
    | "cloud-dictionary-files"
    | "cloud-dictionary-apply"
    | null
  >(null);
  const mobilePanelRef = useRef(mobilePanel);
  const [initialPage, setInitialPage] = useState<string | undefined>();
  useEffect(() => {
    mobilePanelRef.current = mobilePanel;
  }, [mobilePanel]);
  const navigateMobilePanel = (next: NonNullable<typeof mobilePanel>, replace = false) => {
    if (typeof window !== "undefined") {
      const current = window.history.state;
      const state = {
        ...(current && typeof current === "object" ? current : {}),
        msimeSettings: true,
        panel: next,
      };
      if (replace) window.history.replaceState(state, "");
      else window.history.pushState(state, "");
    }
    setMobilePanel(next);
  };
  const closeMobilePanel = () => {
    if (
      typeof window !== "undefined" &&
      window.history.state?.msimeSettings === true &&
      window.history.state?.panel
    ) {
      window.history.back();
    } else {
      setMobilePanel(null);
    }
  };
  useEffect(() => {
    const onPopState = (event: PopStateEvent) => {
      const state = event.state;
      if (state?.msimeSettings === true && typeof state.panel === "string") {
        setMobilePanel(state.panel as NonNullable<typeof mobilePanel>);
      } else if (mobilePanelRef.current !== null) {
        setMobilePanel(null);
      }
    };
    const onNativePanel = (event: Event) => {
      const panel = (event as CustomEvent<unknown>).detail;
      if (
        typeof panel === "string" &&
        [
          "voice",
          "emoji",
          "clipboard",
          "cloud-clipboard",
          "cloud-dictionary",
          "cloud-dictionary-catalog",
          "cloud-candidates",
          "cloud-dictionary-files",
          "cloud-dictionary-apply",
        ].includes(panel)
      ) {
        setMobilePanel(panel as NonNullable<typeof mobilePanel>);
      }
    };
    const onNativeSettingsPage = (event: Event) => {
      const page = (event as CustomEvent<unknown>).detail;
      if (
        typeof page === "string" &&
        ["home", "appearance", "dictionary", "account", "about", "help", "feedback"].includes(page)
      ) {
        setInitialPage(page);
        setMobilePanel(null);
      }
    };
    window.addEventListener("popstate", onPopState);
    window.addEventListener("msime-mobile-panel", onNativePanel);
    window.addEventListener("msime-settings-page", onNativeSettingsPage);
    return () => {
      window.removeEventListener("popstate", onPopState);
      window.removeEventListener("msime-mobile-panel", onNativePanel);
      window.removeEventListener("msime-settings-page", onNativeSettingsPage);
    };
  }, []);
  // The host menu entry that started this window names a section; resolve it
  // before mounting so the page never opens on one and then jumps.
  useEffect(() => {
    let active = true;
    let unsubscribe: (() => void) | undefined;
    if (isTauri()) {
      void listen<string>("settings-route", (event) => {
        if (active) setInitialPage(event.payload || undefined);
      })
        .then((stop) => {
          if (active) unsubscribe = stop;
          else stop();
        })
        .catch(() => {});
    }
    const requested = isTauri()
      ? invoke<string | null>("initial_settings_page").catch(() => null)
      : Promise.resolve(null);
    void Promise.all([
      discoverFontReader(isTauri(), invoke),
      requested,
      discoverHostCapabilities(),
    ]).then(async ([reader, page, host]) => {
      if (!active) return;
      const android = host?.platform === "android";
      const ios = host?.platform === "ios";
      const ready = android
        ? await invoke<boolean>("android_bootstrap_status").catch(() => false)
        : ios
          ? await invoke<boolean>("ios_onboarding_status").catch(() => false)
          : true;
      // Linux prepares its runtime options from the first-run page instead of refusing to start without them.
      const linuxSetupStatus =
        host?.platform === "linux"
          ? await invoke<LinuxSetupStatus>("linux_setup_status").catch(() => null)
          : null;
      if (!active) return;
      if (linuxSetupStatus && !linuxSetupStatus.prepared) setLinuxSetup(linuxSetupStatus);
      setBootstrapRequired((android || ios) && !ready);
      setInitialPage(page ?? undefined);
      const hosted: SettingsClient = host
        ? {
            ...client,
            host,
            dictionary: isMobileHost(host.platform) ? mobileDictionary : dictionary,
            // Windows and macOS resolve the offline gloss in their native
            // candidate controllers, so the setting is real on both hosts.
            candidateEnglishGloss:
              host.platform === "linux" ||
              host.platform === "android" ||
              host.platform === "windows" ||
              host.platform === "macos" ||
              host.platform === "ios",
            // A file manager is only reachable on the desktop hosts; iOS and Android get the same
            // page without the button rather than one that fails when pressed.
            ...(host.typing_statistics
              ? {
                  typingStatistics: isMobileHost(host.platform)
                    ? typingStatistics
                    : {
                        ...typingStatistics,
                        openDirectory: () => invoke<void>("open_typing_statistics_directory"),
                      },
                }
              : {}),
            ...(host.fuzzy_pinyin ? { fuzzyPinyin: true } : {}),
            ...(host.platform === "ios" || host.platform === "android"
              ? createMobileHostServices(host.platform, {
                  invoke,
                  listen,
                  navigateVoice: () => navigateMobilePanel("voice"),
                })
              : {}),
            ...(host.platform === "ios" || host.platform === "android"
              ? {
                  openSystemKeyboardSettings: () =>
                    invoke(
                      host.platform === "ios"
                        ? "open_system_keyboard_settings"
                        : "android_open_input_method_settings",
                    ),
                }
              : {}),
            ...(host.platform === "linux"
              ? {
                  customTouchKeyboardSkins: true,
                  customSkinLibrary: {
                    load: () => invoke("load_custom_skin_library"),
                    mutate: (action) => invoke("mutate_custom_skin_library", { action }),
                  },
                  testApiCredential: (
                    service: ApiCredentialTestService,
                    config: Record<string, unknown>,
                  ) => invoke<ApiCredentialTestResult>("test_api_credential", { service, config }),
                  providerCredentials: {
                    status: () => invoke<ProviderCredentialStatus>("provider_credentials_status"),
                    saveAi: ({ provider, endpoint, model, token }) =>
                      invoke<ProviderCredentialStatus>("save_ai_provider_credential", {
                        provider,
                        endpoint,
                        model,
                        token,
                      }),
                    clearAi: (provider) =>
                      invoke<ProviderCredentialStatus>("clear_ai_provider_credential", {
                        provider,
                      }),
                    saveTencent: ({ secretId, secretKey, region }) =>
                      invoke<ProviderCredentialStatus>("save_tencent_provider_credential", {
                        secretId,
                        secretKey,
                        region,
                      }),
                    clearTencent: () =>
                      invoke<ProviderCredentialStatus>("clear_tencent_provider_credential"),
                  } satisfies ProviderCredentialClient,
                }
              : {}),
            ...(host.platform === "windows" || host.platform === "macos"
              ? {
                  testApiCredential: testDesktopApiCredential,
                  aiAssistant: {
                    fetchModels: ({ endpoint, token }) =>
                      invoke<string[]>("ai_models", { endpoint, token }),
                    test: ({ endpoint, model, prompt, token, text }) =>
                      invoke<string>("ai_test", { endpoint, model, prompt, token, text }),
                  },
                }
              : {}),
            // Same two commands, and the host resolves them through the provider
            // service that holds the credential. The token is deliberately not
            // passed: it is not in this process on this platform.
            ...(host.platform === "linux"
              ? {
                  aiAssistant: {
                    fetchModels: ({ endpoint, provider }) =>
                      invoke<string[]>("ai_models", { endpoint, provider }),
                    test: ({ endpoint, model, prompt, text, provider }) =>
                      invoke<string>("ai_test", { endpoint, model, prompt, text, provider }),
                  },
                }
              : {}),
            ...(host.platform === "windows" ||
            host.platform === "macos" ||
            host.platform === "linux"
              ? {
                  account: {
                    status: () => invoke("account_status"),
                    providers: () => invoke("account_providers"),
                    requestCode: (provider: string, target: string) =>
                      invoke("account_request_code", { provider, target }),
                    login: (challengeId: string, code: string) =>
                      invoke("account_login", { challengeId, code }),
                    profile: () => invoke("account_profile"),
                    rename: (displayName: string) => invoke("account_rename", { displayName }),
                    logout: (all: boolean) => invoke("account_logout", { all }),
                    deleteAccount: () => invoke("account_delete"),
                    clearExpired: () => invoke("account_forget"),
                  } satisfies AccountClient,
                }
              : {}),
            ...(host.platform === "ios"
              ? {
                  testApiCredential: (
                    service: ApiCredentialTestService,
                    config: Record<string, unknown>,
                  ) => invoke<ApiCredentialTestResult>("test_api_credential", { service, config }),
                }
              : {}),
          }
        : client;
      const mobileHosted =
        host?.platform === "android"
          ? {
              ...hosted,
              home: {
                ...hosted.home,
                openEmojiPanel: async () => navigateMobilePanel("emoji"),
                openClipboardPanel: async () => navigateMobilePanel("clipboard"),
              },
              openCloudClipboard: async () => navigateMobilePanel("cloud-clipboard"),
              openCloudDictionary: async () => navigateMobilePanel("cloud-dictionary"),
            }
          : host?.platform === "ios"
            ? {
                ...hosted,
                openCloudClipboard: async () => navigateMobilePanel("cloud-clipboard"),
                openCloudDictionary: async () => navigateMobilePanel("cloud-dictionary"),
              }
            : hosted;
      setSettingsClient(reader ? { ...mobileHosted, listFontFamilies: reader } : mobileHosted);
    });
    return () => {
      active = false;
      unsubscribe?.();
    };
  }, []);
  const onboardingPlatform = settingsClient?.host?.platform;
  const onboardingActions: OnboardingActions = {
    platform: onboardingPlatform === "ios" ? "ios" : "android",
    prepareResources:
      onboardingPlatform === "android" || !onboardingPlatform
        ? () => invoke("android_prepare_bootstrap").then(() => undefined)
        : async () => undefined,
    openSystemKeyboardSettings:
      onboardingPlatform === "ios"
        ? () => invoke("open_system_keyboard_settings").then(() => undefined)
        : () => invoke("android_open_input_method_settings").then(() => undefined),
    showInputMethodPicker:
      onboardingPlatform === "android" || !onboardingPlatform
        ? () => invoke("android_show_input_method_picker").then(() => undefined)
        : async () => undefined,
  };
  const completeOnboarding = async (scheme: OnboardingInputScheme) => {
    const snapshot = await client.load();
    const enabled = [...(snapshot.preferences.touch_keyboard_schemes?.enabled ?? [])];
    if (!enabled.includes(scheme)) enabled.push(scheme);
    await client.save(snapshot.revision, {
      ...snapshot.preferences,
      scheme: "quanpin",
      last_chinese_scheme: "quanpin",
      touch_keyboard_layout: scheme === "nine_key" ? "nine_key" : "twenty_six_key",
      touch_keyboard_schemes: {
        ...snapshot.preferences.touch_keyboard_schemes,
        enabled,
        selected: scheme,
      },
    });
    if (onboardingPlatform === "ios") await invoke("ios_onboarding_complete");
    setBootstrapRequired(false);
    setReplayOnboarding(false);
  };
  const skipOnboarding = async () => {
    if (onboardingPlatform === "ios") await invoke("ios_onboarding_complete");
    setBootstrapRequired(false);
    setReplayOnboarding(false);
  };
  if (linuxSetup)
    return (
      <LinuxSetupPage
        status={linuxSetup}
        client={linuxSetupClient}
        onComplete={() => setLinuxSetup(null)}
      />
    );
  // Mount once after discovery: replacing the client later would reload draft preferences.
  if (bootstrapRequired || replayOnboarding)
    return (
      <WelcomeFlowPage
        actions={onboardingActions}
        onComplete={completeOnboarding}
        onSkip={onboardingPlatform === "ios" ? skipOnboarding : undefined}
      />
    );
  if (!settingsClient)
    return (
      <SettingsStartupPage
        onClose={
          isTauri()
            ? () => {
                void getCurrentWindow().close();
              }
            : undefined
        }
      />
    );
  const cloudDictionary = {
    ...panelClients.cloudDictionary,
    ...cloudDictionaryCapabilities(settingsClient.host?.platform),
    ...(isMobileHost(settingsClient.host?.platform)
      ? {
          downloadToLocal: (entry: CloudDictionaryEntry) =>
            downloadCloudEntryToLocal(entry, mobileDictionary),
        }
      : {}),
  };
  if (mobilePanel === "voice") {
    const ios = settingsClient.host?.platform === "ios";
    return (
      <VoicePanel
        client={{
          ...panelClients.voice,
          close: async () => closeMobilePanel(),
          rememberInputTarget: undefined,
          ...(ios
            ? {
                description:
                  "iOS App 负责录音和识别；识别结果不会直接写入键盘扩展，确认提交后会保存为待插入的语音结果。",
                submitNotice:
                  "已发送到本机键盘。返回目标 App，打开键盘“更多 → 语音结果”，确认后插入。",
              }
            : {}),
        }}
        theme="light"
      />
    );
  }
  if (mobilePanel === "emoji" || mobilePanel === "clipboard") {
    return (
      <DesktopPanelTheme preferences={settingsClient} surface="emoji">
        {(theme) => (
          <DesktopEmojiPanel
            theme={theme}
            initialPage={mobilePanel === "clipboard" ? "clipboard" : "home"}
            client={{
              ...panelClients.emoji,
              close: async () => closeMobilePanel(),
              rememberInputTarget: undefined,
              sendText: undefined,
            }}
            close={async () => closeMobilePanel()}
          />
        )}
      </DesktopPanelTheme>
    );
  }
  if (mobilePanel === "cloud-clipboard") {
    return (
      <CloudClipboardPanel
        client={{
          ...panelClients.cloudClipboard,
          rememberInputTarget: undefined,
          sendText: undefined,
          close: async () => closeMobilePanel(),
        }}
      />
    );
  }
  if (mobilePanel === "cloud-dictionary") {
    return (
      <CloudDictionaryPanel
        client={{
          ...cloudDictionary,
          openCatalog: async () => navigateMobilePanel("cloud-dictionary-catalog"),
          openCandidates: async () => navigateMobilePanel("cloud-candidates"),
          openFiles: async () => navigateMobilePanel("cloud-dictionary-files"),
          openApply: async () => navigateMobilePanel("cloud-dictionary-apply"),
          close: async () => closeMobilePanel(),
        }}
      />
    );
  }
  if (mobilePanel === "cloud-dictionary-catalog") {
    return (
      <CloudDictionaryCatalogPanel
        client={{
          ...cloudDictionary,
          back: async () => navigateMobilePanel("cloud-dictionary", true),
          close: async () => closeMobilePanel(),
        }}
      />
    );
  }
  if (mobilePanel === "cloud-candidates") {
    return (
      <CloudCandidatesPanel
        client={{
          ...cloudDictionary,
          back: async () => navigateMobilePanel("cloud-dictionary", true),
          close: async () => closeMobilePanel(),
        }}
      />
    );
  }
  if (mobilePanel === "cloud-dictionary-files") {
    return (
      <CloudDictionaryFilesPanel
        client={{
          ...cloudDictionary,
          back: async () => navigateMobilePanel("cloud-dictionary", true),
          close: async () => closeMobilePanel(),
        }}
      />
    );
  }
  if (mobilePanel === "cloud-dictionary-apply") {
    return (
      <CloudDictionaryApplyPanel
        client={{
          ...cloudDictionary,
          back: async () => navigateMobilePanel("cloud-dictionary", true),
          close: async () => closeMobilePanel(),
        }}
      />
    );
  }
  return (
    <SettingsPage
      key={initialPage ?? "default"}
      client={settingsClient}
      initialPage={initialPage}
      onReplayOnboarding={() => setReplayOnboarding(true)}
    />
  );
}
function DesktopCloudDictionarySurface() {
  const [host, setHost] = useState<HostCapabilities | null | undefined>(undefined);
  useEffect(() => {
    let active = true;
    void discoverHostCapabilities().then((value) => {
      if (active) setHost(value);
    });
    return () => {
      active = false;
    };
  }, []);
  if (host === undefined) return <p role="status">正在连接云词库…</p>;
  const capabilities = cloudDictionaryCapabilities(host?.platform);
  const cloudDictionary = {
    ...panelClients.cloudDictionary,
    ...capabilities,
    ...(isMobileHost(host?.platform)
      ? {
          downloadToLocal: (entry: CloudDictionaryEntry) =>
            downloadCloudEntryToLocal(entry, mobileDictionary),
        }
      : {}),
  };
  return <DesktopCloudDictionary client={cloudDictionary} />;
}
function DesktopEmojiPanel({
  theme,
  initialPage = "home",
  client: providedClient,
  close,
}: {
  theme: "dark" | "light";
  initialPage?: "home" | "clipboard";
  client?: EmojiPanelClient;
  close?: () => Promise<void>;
}) {
  const [emojiClient, setEmojiClient] = useState<EmojiPanelClient | null>(null);
  const panelLabel = initialPage === "clipboard" ? "clipboard-panel" : "emoji-panel";
  useEffect(() => {
    let active = true;
    const capability = isTauri()
      ? invoke<boolean>("supports_clipboard_paste").catch(() => false)
      : Promise.resolve(false);
    void capability.then((supported) => {
      if (!active) return;
      const baseClient = providedClient ?? panelClients.emoji;
      const closePanel = close ?? (() => invoke("close_panel", { label: panelLabel }));
      setEmojiClient(
        supported
          ? {
              ...baseClient,
              close: closePanel,
              clipboard: baseClient.clipboard
                ? {
                    ...baseClient.clipboard,
                    paste: (text) => invoke<void>("paste_clipboard_text", { text }),
                  }
                : undefined,
            }
          : { ...baseClient, close: closePanel },
      );
    });
    return () => {
      active = false;
    };
  }, [close, panelLabel, providedClient]);
  return emojiClient ? (
    <EmojiPanel client={emojiClient} theme={theme} initialPage={initialPage} />
  ) : (
    <p role="status">正在连接面板…</p>
  );
}

const content =
  panel === "keyboard" ? (
    <DesktopKeyboard client={panelClients.keyboard} preferences={client} />
  ) : panel === "handwriting" ? (
    <DesktopPanelTheme preferences={client} surface="handwriting">
      {(theme) => <HandwritingPanel client={panelClients.handwriting} theme={theme} />}
    </DesktopPanelTheme>
  ) : panel === "voice" ? (
    <DesktopPanelTheme preferences={client} surface="voice">
      {(theme) => <VoicePanel client={panelClients.voice} theme={theme} />}
    </DesktopPanelTheme>
  ) : panel === "cloud-clipboard" ? (
    <CloudClipboardPanel client={panelClients.cloudClipboard} />
  ) : panel === "cloud-dictionary" ? (
    <DesktopCloudDictionarySurface />
  ) : panel === "clipboard" ? (
    <DesktopPanelTheme preferences={client} surface="emoji">
      {(theme) => <DesktopEmojiPanel theme={theme} initialPage="clipboard" />}
    </DesktopPanelTheme>
  ) : panel === "emoji" ? (
    <DesktopPanelTheme preferences={client} surface="emoji">
      {(theme) => <DesktopEmojiPanel theme={theme} />}
    </DesktopPanelTheme>
  ) : (
    <DesktopSettings />
  );
createRoot(document.getElementById("root")!).render(<StrictMode>{content}</StrictMode>);
