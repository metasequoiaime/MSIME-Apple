import web_webview from '@ohos.web.webview';
import common from '@ohos.app.ability.common';
import client from 'libmsimeclient.so';
import pasteboard from '@ohos.pasteboard';
import Want from '@ohos.app.ability.Want';
import bundleManager from '@ohos.bundle.bundleManager';
import fs from '@ohos.file.fs';
import { KeyboardLog, describeError } from '../keyboard/KeyboardLog';
import { KeyboardSession } from '../keyboard/KeyboardSession';
import { HarmonyAccountCloudBridge } from '../account/HarmonyAccountCloudBridge';

/**
 * The settings window, which is the shared settings UI rather than a second one written here.
 *
 * Every host renders the same React surface from packages/ui and differs only in what it declares it
 * can do: the page draws a control when the host says the control is connected to something, so a
 * platform never shows a switch that saves and does nothing. Writing a HarmonyOS-shaped imitation of
 * that page would have meant maintaining a second, worse copy of every screen in it.
 *
 * The bundle is built into rawfile and loaded from there, so the window needs no network. Everything
 * it needs from the system comes through one injected object, which is deliberately thin: JSON in,
 * JSON out, the same shape the shared C ABI already uses, leaving the bridge with no opinion about
 * preferences and nothing to keep in sync with the schema.
 */

const BRIDGE_NAME: string = 'msimeHarmony';
const PLATFORM: string = 'harmony';

@Entry
@Component
struct Settings {
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private bridge: SettingsBridge = new SettingsBridge();

  aboutToAppear(): void {
    this.bridge.attach(this.context);
  }

  build() {
    Column() {
      Web({ src: $rawfile('settings/index.html'), controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        // Registered before the first load, so the page finds it already there rather than racing it.
        .javaScriptProxy({
          object: this.bridge,
          name: BRIDGE_NAME,
          methodList: ['loadPreferences', 'savePreferences', 'hostCapabilities', 'appVersion',
            'dictionary', 'account', 'cloudDictionary', 'cloudDictionaryDownload', 'openExternalUrl', 'copyText', 'openSystemKeyboardSettings'],
          controller: this.controller
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * What the settings page is allowed to ask of the system.
 *
 * Each method answers the JSON the shared C ABI already returns, so a reply that the Engine refused
 * arrives at the page as the refusal rather than as an exception thrown across the bridge.
 */
class SettingsBridge {
  private stateDirectory: string = '';
  private context: common.UIAbilityContext | undefined = undefined;
  private accountBridge: HarmonyAccountCloudBridge | undefined = undefined;
  private cloudDownloadRequest: number = 0;

  attach(context: common.UIAbilityContext): void {
    this.context = context;
    this.stateDirectory = `${context.filesDir}/state`;
    this.accountBridge = new HarmonyAccountCloudBridge(context);
    this.stageResources(`${context.resourceDir}/engine`, `${context.filesDir}/engine`);
  }

  private stageResources(packaged: string, destination: string): void {
    try {
      if (!fs.accessSync(packaged)) {
        return;
      }
      if (!fs.accessSync(destination)) {
        fs.mkdirSync(destination, true);
      }
      for (const name of fs.listFileSync(packaged)) {
        fs.copyFileSync(`${packaged}/${name}`, `${destination}/${name}`);
      }
    } catch (error) {
      KeyboardLog.error(`settings resources unavailable: ${describeError(error)}`);
    }
  }

  loadPreferences(): string {
    return client.loadPreferences(this.stateDirectory);
  }

  /**
   * The revision is what the page read, not what it is writing: the store compares it against what
   * is on disk and refuses the save if the keyboard changed something in between, which is the whole
   * point of having one.
   */
  savePreferences(expectedRevision: number, document: string): string {
    return client.savePreferences(this.stateDirectory, expectedRevision, document);
  }

  hostCapabilities(): string {
    return client.hostCapabilities(PLATFORM);
  }

  dictionary(action: string): string {
    if (this.context === undefined) {
      return JSON.stringify({ ok: false, error: 'settings context unavailable' });
    }
    return KeyboardSession.shared.dictionary(action, `${this.context.filesDir}/engine`,
      this.stateDirectory);
  }

  /** Account and cloud clipboard requests stay native; the WebView sees only safe JSON DTOs. */
  account(action: string): Promise<string> {
    if (this.accountBridge === undefined) {
      return Promise.resolve(JSON.stringify({ ok: false, error: 'account_unavailable' }));
    }
    return this.accountBridge.request(action);
  }

  cloudDictionary(action: string): Promise<string> {
    if (this.accountBridge === undefined) {
      return Promise.resolve(JSON.stringify({ ok: false, error: 'account_unavailable' }));
    }
    return this.accountBridge.request(action);
  }

  /** Add one explicitly selected cloud entry through the Engine's existing maintenance boundary. */
  cloudDictionaryDownload(entryDocument: string): string {
    if (this.context === undefined) {
      return JSON.stringify({ ok: false, error: 'settings context unavailable' });
    }
    try {
      const entry: Record<string, Object> = JSON.parse(entryDocument) as Record<string, Object>;
      const kind: Object | undefined = entry.kind;
      const code: Object | undefined = entry.code;
      const word: Object | undefined = entry.word;
      const weight: Object | undefined = entry.weight;
      if (typeof kind !== 'string' || !['pinyin', 'wubi', 'quick', 'english'].includes(kind)
        || typeof code !== 'string' || code.length === 0 || code.length > 256
        || typeof word !== 'string' || word.length === 0 || word.length > 1024
        || typeof weight !== 'number' || !Number.isInteger(weight) || weight < 0) {
        return JSON.stringify({ ok: false, error: 'account_invalid' });
      }
      const replacement: Record<string, Object> = {
        kind: kind === 'quick' ? 'quick_phrase' : kind,
        key: code,
        value: word,
        weight: weight
      };
      this.cloudDownloadRequest += 1;
      const request: Record<string, Object> = {
        operation: 'edit',
        previous: null,
        replacement: replacement,
        request_id: `cloud-download-${this.cloudDownloadRequest}`
      };
      return KeyboardSession.shared.dictionary(JSON.stringify(request), `${this.context.filesDir}/engine`,
        this.stateDirectory);
    } catch {
      return JSON.stringify({ ok: false, error: 'account_invalid' });
    }
  }

  appVersion(): string {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (error) {
      KeyboardLog.error(`version unreadable: ${describeError(error)}`);
      return '';
    }
  }

  openExternalUrl(url: string): void {
    // Only the two schemes a settings page has any business opening; anything else is not a link the
    // page should be able to make this application follow.
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      KeyboardLog.error('refused to open a non-web link');
      return;
    }
    const want: Want = { action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: url };
    if (this.context !== undefined) {
      this.context.startAbility(want).catch((error: Object): void => {
        KeyboardLog.error(`link would not open: ${describeError(error)}`);
      });
    }
  }

  copyText(text: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).catch((error: Object): void => {
      KeyboardLog.error(`copy failed: ${describeError(error)}`);
    });
  }

  /** Where the user turns the keyboard on, which is a system screen rather than one of ours. */
  openSystemKeyboardSettings(): void {
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'input_method_settings'
    };
    if (this.context !== undefined) {
      this.context.startAbility(want).catch((error: Object): void => {
        KeyboardLog.error(`keyboard settings would not open: ${describeError(error)}`);
      });
    }
  }
}
