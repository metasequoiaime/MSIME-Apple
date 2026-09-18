import web_webview from '@ohos.web.webview';
import common from '@ohos.app.ability.common';
import client from 'libmsimeclient.so';
import pasteboard from '@ohos.pasteboard';
import Want from '@ohos.app.ability.Want';
import bundleManager from '@ohos.bundle.bundleManager';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { KeyboardLog, describeError } from '../keyboard/KeyboardLog';
import { KeyboardSession } from '../keyboard/KeyboardSession';
import { HarmonyAccountCloudBridge } from '../account/HarmonyAccountCloudBridge';
import { utf8Length } from '../keyboard/Utf8';

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

interface CloudDownloadEntry {
  kind: string;
  code: string;
  word: string;
  weight: number;
}

interface LocalDictionaryEntry {
  kind: string;
  key: string;
  value: string;
  weight: number;
}

interface LocalDictionaryEditRequest {
  operation: string;
  previous: LocalDictionaryEntry | null;
  replacement: LocalDictionaryEntry;
  request_id: string;
}

interface TypingStatisticsAction {
  operation: string;
  enabled?: boolean;
}

interface TypingStatisticsDocument {
  enabled: boolean;
  total: number;
  days: Record<string, number>;
  detail: Object;
  dailyDetails: Record<string, Object>;
}

interface TypingStatisticsReply {
  ok: boolean;
  value: TypingStatisticsDocument;
  error: string;
}

interface TypingStatisticsStatusValue {
  statistics: TypingStatisticsDocument;
  availability: string;
  lastWrittenMs: number | null;
}

interface TypingStatisticsStatusReply {
  ok: boolean;
  value: TypingStatisticsStatusValue;
}

interface AiModelsRequest {
  endpoint: string;
  token: string;
}

interface AiTestRequest {
  endpoint: string;
  model: string;
  prompt: string;
  token: string;
  text: string;
}

interface ApiCredentialRequest {
  service: string;
  config: AiCredentialConfig;
}

interface AiCredentialConfig {
  endpoint?: string;
  model?: string;
  token?: string;
  provider?: string;
}

interface AiModelRow {
  id?: string;
}

interface AiModelsDocument {
  data?: AiModelRow[];
}

interface AiMessage {
  content?: string;
}

interface AiChoice {
  message?: AiMessage;
}

interface AiCompletionDocument {
  choices?: AiChoice[];
}

interface AiMessageRequest {
  role: string;
  content: string;
}

interface AiTestBody {
  model: string;
  stream: boolean;
  temperature: number;
  messages: AiMessageRequest[];
}

interface AiReply<T> {
  ok: boolean;
  value: T;
  error: string;
}

interface ApiCredentialResult {
  ok: boolean;
  message: string;
}

interface ApiCredentialReply {
  ok: boolean;
  value: ApiCredentialResult;
}

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
            'dictionary', 'account', 'cloudDictionary', 'cloudDictionaryDownload', 'cloudDictionarySnapshot',
            'typingStatistics', 'aiModels', 'aiTest', 'testApiCredential', 'openExternalUrl', 'copyText',
            'openSystemKeyboardSettings'],
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
      const entry: CloudDownloadEntry = JSON.parse(entryDocument) as CloudDownloadEntry;
      const kind: string = entry.kind;
      const code: string = entry.code;
      const word: string = entry.word;
      const weight: number = entry.weight;
      if (typeof kind !== 'string' || !['pinyin', 'wubi', 'quick', 'english'].includes(kind)
        || typeof code !== 'string' || code.length === 0 || code.length > 256
        || typeof word !== 'string' || word.length === 0 || word.length > 1024
        || typeof weight !== 'number' || !Number.isInteger(weight) || weight < 0) {
        return JSON.stringify({ ok: false, error: 'account_invalid' });
      }
      const replacement: LocalDictionaryEntry = {
        kind: kind === 'quick' ? 'quick_phrase' : kind,
        key: code,
        value: word,
        weight: weight
      };
      this.cloudDownloadRequest += 1;
      const request: LocalDictionaryEditRequest = {
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

  cloudDictionarySnapshot(action: string): Promise<string> {
    if (this.accountBridge === undefined || this.context === undefined) {
      return Promise.resolve(JSON.stringify({ ok: false, error: 'snapshot_unavailable' }));
    }
    return this.accountBridge.snapshot(action, `${this.context.filesDir}/engine`, this.stateDirectory);
  }

  typingStatistics(actionDocument: string): string {
    if (actionDocument.length === 0 || actionDocument.length > 4096) {
      return JSON.stringify({ ok: false, error: 'invalid typing statistics request' });
    }
    try {
      const action: TypingStatisticsAction = JSON.parse(actionDocument) as TypingStatisticsAction;
      if (!['load', 'set_enabled', 'reset'].includes(action.operation)
        || (action.operation === 'set_enabled' && typeof action.enabled !== 'boolean')) {
        return JSON.stringify({ ok: false, error: 'invalid typing statistics request' });
      }
      const raw: string = client.typingStatistics(JSON.stringify({
        directory: this.stateDirectory, action: action
      }));
      const reply: TypingStatisticsReply = JSON.parse(raw) as TypingStatisticsReply;
      if (!reply.ok) return raw;
      let lastWrittenMs: number | null = null;
      let available: boolean = false;
      const file: string = `${this.stateDirectory}/typing-statistics.json`;
      try {
        if (fs.accessSync(file)) {
          available = true;
          lastWrittenMs = fs.statSync(file).mtime;
        }
      } catch {
        available = false;
      }
      const status: TypingStatisticsStatusValue = {
        statistics: reply.value,
        availability: available ? 'ready' : 'neverWritten',
        lastWrittenMs: lastWrittenMs
      };
      const result: TypingStatisticsStatusReply = { ok: true, value: status };
      return JSON.stringify(result);
    } catch {
      return JSON.stringify({ ok: false, error: 'invalid typing statistics request' });
    }
  }

  async aiModels(requestDocument: string): Promise<string> {
    let request: AiModelsRequest;
    try {
      request = JSON.parse(requestDocument) as AiModelsRequest;
      if (typeof request.endpoint !== 'string' || typeof request.token !== 'string') {
        return JSON.stringify({ ok: false, error: 'ai_models_invalid' });
      }
    } catch {
      return JSON.stringify({ ok: false, error: 'ai_models_invalid' });
    }
    const endpoint: string | null = this.validAiEndpoint(request.endpoint);
    const token: string = request.token.trim();
    if (endpoint === null || token.length === 0 || utf8Length(token) > 16 * 1024
      || this.hasControl(token)) {
      return JSON.stringify({ ok: false, error: 'ai_invalid' });
    }
    const modelsUrl: string = this.aiModelsUrl(endpoint);
    const httpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(modelsUrl, {
        method: http.RequestMethod.GET,
        header: { Accept: 'application/json', Authorization: `Bearer ${token}` },
        connectTimeout: 5000,
        readTimeout: 15000
      });
      if (response.responseCode < 200 || response.responseCode >= 300
        || typeof response.result !== 'string' || utf8Length(response.result) > 1024 * 1024) {
        return JSON.stringify({ ok: false, error: 'ai_models_unavailable' });
      }
      const document: AiModelsDocument = JSON.parse(response.result) as AiModelsDocument;
      if (!Array.isArray(document.data)) {
        return JSON.stringify({ ok: false, error: 'ai_models_invalid' });
      }
      const models: string[] = [];
      for (const row of document.data) {
        const id: string | undefined = row.id;
        if (id === undefined || id.length === 0 || utf8Length(id) > 256 || this.hasControl(id)
          || models.includes(id)) continue;
        models.push(id);
        if (models.length === 128) break;
      }
      if (models.length === 0) return JSON.stringify({ ok: false, error: 'ai_models_invalid' });
      return JSON.stringify({ ok: true, value: models });
    } catch (error) {
      KeyboardLog.error(`AI model list unavailable: ${describeError(error)}`);
      return JSON.stringify({ ok: false, error: 'ai_models_unavailable' });
    } finally {
      httpRequest.destroy();
    }
  }

  async aiTest(requestDocument: string): Promise<string> {
    let request: AiTestRequest;
    try {
      request = JSON.parse(requestDocument) as AiTestRequest;
      if (typeof request.endpoint !== 'string' || typeof request.model !== 'string'
        || typeof request.prompt !== 'string' || typeof request.token !== 'string'
        || typeof request.text !== 'string') {
        return JSON.stringify({ ok: false, error: 'ai_invalid' });
      }
    } catch {
      return JSON.stringify({ ok: false, error: 'ai_invalid' });
    }
    const endpoint: string | null = this.validAiEndpoint(request.endpoint);
    const token: string = request.token.trim();
    const model: string = request.model.trim();
    if (endpoint === null || token.length === 0 || utf8Length(token) > 16 * 1024
      || this.hasControl(token) || model.length === 0 || utf8Length(model) > 256
      || this.hasControl(model) || !this.validAiText(request.prompt, true)
      || !this.validAiText(request.text, false)) {
      return JSON.stringify({ ok: false, error: 'ai_invalid' });
    }
    const body: AiTestBody = {
      model: model,
      stream: false,
      temperature: 0.2,
      messages: [
        { role: 'system', content: request.prompt },
        { role: 'user', content: request.text }
      ]
    };
    const httpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(endpoint, {
        method: http.RequestMethod.POST,
        header: { Accept: 'application/json', 'Content-Type': 'application/json',
          Authorization: `Bearer ${token}` },
        connectTimeout: 5000,
        readTimeout: 15000,
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300
        || typeof response.result !== 'string' || utf8Length(response.result) > 1024 * 1024) {
        return JSON.stringify({ ok: false, error: 'ai_test_unavailable' });
      }
      const document: AiCompletionDocument = JSON.parse(response.result) as AiCompletionDocument;
      const content: string | undefined = document.choices?.[0]?.message?.content;
      if (content === undefined || !this.validAiText(content, false)) {
        return JSON.stringify({ ok: false, error: 'ai_test_invalid' });
      }
      return JSON.stringify({ ok: true, value: content.trim() });
    } catch (error) {
      KeyboardLog.error(`AI test unavailable: ${describeError(error)}`);
      return JSON.stringify({ ok: false, error: 'ai_test_unavailable' });
    } finally {
      httpRequest.destroy();
    }
  }

  async testApiCredential(requestDocument: string): Promise<string> {
    let request: ApiCredentialRequest;
    try {
      request = JSON.parse(requestDocument) as ApiCredentialRequest;
    } catch {
      return this.credentialReply(false, '配置格式无效。');
    }
    if (request.service !== 'ai.assistant' || request.config === undefined) {
      return this.credentialReply(false, 'Harmony 当前只支持 AI 配置测试。');
    }
    const endpoint: string = request.config.endpoint ?? '';
    const token: string = request.config.token ?? '';
    const modelReply: string = await this.aiModels(JSON.stringify({ endpoint, token }));
    const result: AiReply<string[]> = JSON.parse(modelReply) as AiReply<string[]>;
    if (!result.ok) {
      return this.credentialReply(false, '无法连接 AI 服务，请检查接口地址和 Token。');
    }
    return this.credentialReply(true, `连接成功，可用模型 ${result.value.length} 个。`);
  }

  private credentialReply(ok: boolean, message: string): string {
    const value: ApiCredentialResult = { ok, message };
    const reply: ApiCredentialReply = { ok: true, value };
    return JSON.stringify(reply);
  }

  private validAiEndpoint(value: string): string | null {
    const endpoint: string = value.trim();
    if (endpoint.length === 0 || utf8Length(endpoint) > 2048 || this.hasControl(endpoint)
      || (!endpoint.startsWith('http://') && !endpoint.startsWith('https://'))
      || endpoint.includes('@') || endpoint.includes('#')) return null;
    const authority: string = endpoint.substring(endpoint.indexOf('://') + 3).split('/')[0]
      .split('?')[0];
    return authority.length === 0 ? null : endpoint;
  }

  private aiModelsUrl(endpoint: string): string {
    const query: number = endpoint.indexOf('?');
    const clean: string = query >= 0 ? endpoint.substring(0, query) : endpoint;
    const marker: string = '/v1/';
    const index: number = clean.indexOf(marker);
    const base: string = index >= 0 ? clean.substring(0, index) : clean.substring(0, clean.indexOf('/', 8) >= 0 ? clean.indexOf('/', 8) : clean.length);
    return `${base}/v1/models`;
  }

  private validAiText(value: string, allowEmpty: boolean): boolean {
    return (allowEmpty || value.trim().length > 0) && utf8Length(value) <= 16 * 1024
      && !value.includes('\u0000') && !Array.from(value).some((character: string): boolean => {
        const code: number = character.codePointAt(0) ?? 0;
        return code < 0x20 && code !== 0x09 && code !== 0x0a && code !== 0x0d;
      });
  }

  private hasControl(value: string): boolean {
    return Array.from(value).some((character: string): boolean => {
      const code: number = character.codePointAt(0) ?? 0;
      return code <= 0x1f || (code >= 0x7f && code <= 0x9f);
    });
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
