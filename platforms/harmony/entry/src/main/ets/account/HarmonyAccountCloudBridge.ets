import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import client from 'libmsimeclient.so';
import { AccountCloudBridge, AccountSessionStore, AccountTransport, AccountTransportResponse } from './AccountCloudBridge';
import { KeyboardSession } from '../keyboard/KeyboardSession';
import { utf8Length } from '../keyboard/Utf8';
import { KeyboardFeedbackBridge } from '../keyboard/KeyboardFeedbackBridge';
import { HarmonyAiSkins } from './HarmonyAiSkins';
import {
  AccountPreferenceFields,
  AccountPreferences,
  AccountPreferenceSchema,
  AccountPreferenceSettings,
  AppliedPreferences,
  FeedbackValues,
  applyAccountPreferences,
  localAccountPreferences,
  mergeAccountPreferences
} from './AccountPreferencePlan';

const ACCOUNT_ORIGIN: string = 'https://api.msime.app';

class FileSessionStore implements AccountSessionStore {
  private readonly file: string;

  constructor(directory: string) {
    this.file = `${directory}/account-session.json`;
  }

  load(): string | null {
    try {
      return fs.accessSync(this.file) ? fs.readTextSync(this.file) : null;
    } catch {
      return null;
    }
  }

  save(value: string): void {
    const handle = fs.openSync(this.file, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(handle.fd, value);
    } finally {
      fs.closeSync(handle);
    }
  }

  clear(): void {
    try {
      if (fs.accessSync(this.file)) fs.unlinkSync(this.file);
    } catch {
      // Clearing an already absent session is idempotent.
    }
  }
}

interface SnapshotAction {
  operation: string;
  token?: string;
}

interface AccountOperation {
  operation?: string;
  dictionary_operation?: string;
  kind?: string;
  format?: string;
}

interface AccountOperationReply {
  ok?: boolean;
}

/** One settings-sync request from the page: read the schema or document, upload, or apply. */
interface PreferenceSyncAction {
  operation: string;
  user_id?: string;
}

interface SnapshotRequest {
  id: string;
  cloudRevision: number;
  expectedLocalVersion: string;
  fileSha256: string;
  status: string;
}

interface NativeSnapshotRequest extends SnapshotRequest {
  accountId: string;
}

interface SnapshotQueueState {
  localVersion?: string;
  request?: NativeSnapshotRequest | null;
}

interface SnapshotQueueReply {
  ok: boolean;
  value?: SnapshotQueueState;
  error?: string;
}

interface SnapshotQueueStateAction {
  operation: string;
  directory: string;
  options: Object;
  acknowledge: boolean;
}

interface SnapshotQueueEnqueueAction {
  operation: string;
  directory: string;
  source: string;
  account_id: string;
  cloud_revision: number;
  expected_local_version: string;
  file_sha256: string;
}

interface SnapshotQueueCancelAction {
  operation: string;
  directory: string;
  account_id: string;
}

interface SnapshotValue {
  version?: string;
  handle?: number;
  localVersion?: string;
  request?: SnapshotRequest | null;
  saved?: boolean;
  snapshot?: SnapshotMetadata;
  previewToken?: string;
}

interface SnapshotReply {
  ok: boolean;
  value: SnapshotValue;
  error?: string;
}

interface HttpHeaders {
  Accept: string;
  Authorization?: string;
  'Content-Type': string;
}

/** A declared response size lets native downloads reject a connection that ended early. */
function responseContentLength(headers: Object): number | undefined {
  const values: Record<string, Object> = headers as Record<string, Object>;
  const keys: string[] = Object.keys(values);
  for (const key of keys) {
    if (key.toLowerCase() !== 'content-length') continue;
    const raw: Object = values[key];
    if (typeof raw !== 'string') return -1;
    const parsed: number = Number(raw);
    return Number.isInteger(parsed) && parsed >= 0 ? parsed : -1;
  }
  return undefined;
}

class HarmonyTransport implements AccountTransport {
  async request(method: string, path: string, token?: string, body?: Object,
    timeoutMs?: number): Promise<AccountTransportResponse> {
    if (!path.startsWith('/v1/') || path.includes('\\')) throw new Error('account_invalid');
    const request = http.createHttp();
    const headers: HttpHeaders = { Accept: 'application/json', 'Content-Type': 'application/json' };
    if (token !== undefined) headers.Authorization = `Bearer ${token}`;
    // Only the read side takes the caller's budget. Connecting is connecting on every endpoint, and
    // a chat request to an unreachable host should still fail in seconds rather than in two minutes.
    const options: http.HttpRequestOptions = {
      method: this.method(method),
      header: headers,
      connectTimeout: 30000,
      readTimeout: timeoutMs === undefined ? 30000 : timeoutMs,
      extraData: body === undefined ? undefined : JSON.stringify(body)
    };
    try {
      const response = await request.request(`${ACCOUNT_ORIGIN}${path}`, options);
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        contentLength: responseContentLength(response.header)
      };
    } finally {
      request.destroy();
    }
  }

  private method(value: string): http.RequestMethod {
    switch (value) {
      case 'POST': return http.RequestMethod.POST;
      case 'PUT': return http.RequestMethod.PUT;
      // The current SDK enum omits PATCH, but the HTTP stack accepts the wire method.
      case 'PATCH': return 'PATCH' as http.RequestMethod;
      case 'DELETE': return http.RequestMethod.DELETE;
      default: return http.RequestMethod.GET;
    }
  }
}

interface SnapshotMetadata {
  cloudRevision: number;
  sha256: string;
  fileSha256: string;
  bytes: number;
  records: number;
  entries: number;
  overlays: number;
  positions: number;
  selections: number;
  engineRecords: number;
}

interface SnapshotInspectReply {
  ok: boolean;
  value?: SnapshotMetadata;
  error?: string;
}

interface SnapshotChanges {
  changes?: Object[];
}

/** Account and cloud clipboard state stays in the host; WebView receives only bounded DTOs. */
export class HarmonyAccountCloudBridge {
  private readonly bridge: AccountCloudBridge;
  private readonly context: common.UIAbilityContext;
  private snapshotFile: string = '';
  private snapshotToken: string = '';
  private snapshotAccountId: string = '';
  private snapshotExpectedVersion: string = '';
  private snapshotMetadata: SnapshotMetadata | undefined = undefined;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    const directory = `${context.filesDir}/state`;
    try {
      if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
    } catch {
      // The store reports an unavailable session if the sandbox cannot be prepared.
    }
    this.bridge = new AccountCloudBridge(new HarmonyTransport(), new FileSessionStore(directory));
  }

  async request(action: string): Promise<string> {
    const accountId: string | null = this.bridge.currentUserId();
    let operation: string = '';
    let decoded: AccountOperation | undefined = undefined;
    try {
      decoded = JSON.parse(action) as AccountOperation;
      operation = typeof decoded.operation === 'string' ? decoded.operation : '';
    } catch {
      // The account bridge reports malformed action documents.
    }
    if (accountId !== null && (operation === 'logout' || operation === 'delete_account'
      || operation === 'login' || operation === 'clear_expired')) {
      if (!this.cancelQueueForAccount(accountId)) return this.failure('snapshot_unavailable');
    }
    if (decoded !== undefined && operation === 'dictionary'
      && decoded.dictionary_operation === 'export') {
      return this.exportDictionary(decoded);
    }
    const result = await this.bridge.handle(action);
    if (accountId === null || this.bridge.currentUserId() === accountId) return result;
    try {
      const reply: AccountOperationReply = JSON.parse(result) as AccountOperationReply;
      if (operation.length > 0 && reply.ok === true) {
        this.cancelQueueForAccount(accountId);
      }
    } catch {
      // The account bridge already owns malformed request and response reporting.
    }
    return result;
  }

  /** Download and validate privately before asking the user where the finished export should go. */
  private async exportDictionary(action: AccountOperation): Promise<string> {
    const kind: string = typeof action.kind === 'string' ? action.kind : '';
    const format: string = typeof action.format === 'string' ? action.format : '';
    const downloaded = await this.bridge.downloadDictionary(kind, format);
    if (downloaded.body === undefined) {
      return this.failure(downloaded.error ?? 'account_unavailable');
    }
    const directory: string = `${this.context.filesDir}/state/dictionary-exports`;
    const staging: string = `${directory}/${util.generateRandomUUID(false)}.tsv`;
    let destination: string = '';
    try {
      if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
      const handle = fs.openSync(staging,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(handle.fd, downloaded.body); } finally { fs.closeSync(handle); }
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`msime-${kind}-dictionary.tsv`];
      options.fileSuffixChoices = ['TSV|.tsv'];
      const selected: string[] = await new picker.DocumentViewPicker(this.context).save(options);
      if (selected.length === 0) return this.success({ saved: false });
      destination = selected[0];
      fs.copyFileSync(staging, destination);
      return this.success({ saved: true });
    } catch {
      try {
        if (destination.length > 0 && fs.accessSync(destination)) fs.unlinkSync(destination);
      } catch {
        // Refusing the export matters more than a picker URI which has already disappeared.
      }
      return this.failure('account_storage');
    } finally {
      try {
        if (fs.accessSync(staging)) fs.unlinkSync(staging);
      } catch {
        // A missing staging file is already the desired postcondition.
      }
    }
  }

  private cancelQueueForAccount(accountId: string): boolean {
    try {
      const action: SnapshotQueueCancelAction = {
        operation: 'cancel', directory: `${this.context.filesDir}/state/dictionary-snapshots`,
        account_id: accountId
      };
      const reply: SnapshotQueueReply =
        JSON.parse(client.snapshotQueue(JSON.stringify(action))) as SnapshotQueueReply;
      return reply.ok;
    } catch {
      return false;
    }
  }

  /**
   * The AI skin runner, which shares this bridge's session rather than holding one of its own.
   *
   * Its four requests are authenticated as the same user the rest of the account surface is, and a
   * sign-out has to stop a run that is in flight. A second session object would have missed that.
   */
  aiSkins(): HarmonyAiSkins {
    return new HarmonyAiSkins(this.bridge);
  }

  /**
   * The settings sync, which is the only account surface that writes to the device.
   *
   * It is kept here rather than in `AccountCloudBridge` because the mapping needs two things that
   * bridge has no business holding: the local preference document, which only the shared NAPI can
   * read and write, and the key-feedback file, which lives beside it. The bridge stays what it is —
   * a session and a transport — and the decisions about which settings are account settings live in
   * `AccountPreferencePlan`, where they can be tested without either.
   */
  async preferencesSync(actionDocument: string, stateRoot: string): Promise<string> {
    let action: PreferenceSyncAction;
    try {
      action = JSON.parse(actionDocument) as PreferenceSyncAction;
      if (typeof action.operation !== 'string') return this.failure('account_invalid');
    } catch {
      return this.failure('account_invalid');
    }
    try {
      switch (action.operation) {
        case 'preferences_schema':
          return await this.preferenceSchema();
        case 'preferences_load':
          return await this.preferenceDocument();
        case 'preferences_upload':
          return await this.uploadPreferences(stateRoot);
        case 'preferences_apply':
          return await this.applyPreferences(String(action.user_id ?? ''), stateRoot);
        default:
          return this.failure('account_invalid');
      }
    } catch (error) {
      return this.failure(error instanceof Error ? error.message : 'account_unavailable');
    }
  }

  /**
   * The schema, renamed to what the page reads.
   *
   * The service answers in snake_case and the shared settings surface expects camelCase — the Tauri
   * hosts rename it on the way through, and a host that forwarded the wire shape would leave the
   * page reading `undefined` for the byte limit and the update mode, which it then treats as a
   * schema it cannot trust.
   */
  private async preferenceSchema(): Promise<string> {
    const reply = await this.bridge.preferenceSchema();
    if (reply.error !== undefined || reply.value === undefined) {
      return this.failure(reply.error ?? 'account_unavailable');
    }
    const schema = this.schemaOf(reply.value);
    return schema === null ? this.failure('account_unavailable')
      : JSON.stringify({ ok: true, value: schema });
  }

  private schemaOf(document: Record<string, Object>): AccountPreferenceSchema | null {
    const fields: Object | undefined = document['fields'];
    const maximumBytes: Object | undefined = document['maximum_bytes'];
    const updateMode: Object | undefined = document['update_mode'];
    const revisionRequired: Object | undefined = document['revision_required'];
    if (fields === undefined || fields === null || typeof fields !== 'object'
      || typeof maximumBytes !== 'number' || typeof updateMode !== 'string'
      || typeof revisionRequired !== 'boolean') {
      return null;
    }
    return {
      fields: fields as AccountPreferenceFields,
      maximumBytes: maximumBytes,
      updateMode: updateMode,
      revisionRequired: revisionRequired
    };
  }

  private async preferenceDocument(): Promise<string> {
    const reply = await this.bridge.loadPreferenceDocument();
    if (reply.error !== undefined || reply.value === undefined) {
      return this.failure(reply.error ?? 'account_unavailable');
    }
    const cloud = this.cloudOf(reply.value);
    return cloud === null ? this.failure('account_unavailable')
      : JSON.stringify({ ok: true, value: cloud });
  }

  private cloudOf(document: Record<string, Object>): AccountPreferences | null {
    const revision: Object | undefined = document['revision'];
    const settings: Object | undefined = document['settings'];
    if (typeof revision !== 'number' || settings === undefined || settings === null
      || typeof settings !== 'object' || Array.isArray(settings)) {
      return null;
    }
    return {
      revision: revision,
      settings: settings as AccountPreferenceSettings
    };
  }

  /** What the local document says, read the same way the settings page reads it. */
  private localDocument(stateRoot: string): Record<string, Object> | null {
    try {
      const reply: Record<string, Object> =
        JSON.parse(client.loadPreferences(stateRoot)) as Record<string, Object>;
      if (reply['ok'] !== true) return null;
      const value: Record<string, Object> = reply['value'] as Record<string, Object>;
      const preferences: Object | undefined = value['preferences'];
      const revision: Object | undefined = value['revision'];
      if (preferences === undefined || typeof preferences !== 'object'
        || typeof revision !== 'number') {
        return null;
      }
      return value;
    } catch {
      return null;
    }
  }

  private feedbackValues(stateRoot: string): FeedbackValues {
    const shared = KeyboardFeedbackBridge.toShared(KeyboardSession.feedbackIn(stateRoot));
    return {
      soundEnabled: shared.soundEnabled,
      hapticsEnabled: shared.hapticsEnabled,
      hapticStrength: shared.hapticStrength
    };
  }

  /**
   * This device's settings, written over what the account already holds.
   *
   * The cloud document is read first and merged into rather than replaced: it carries the fields of
   * every other device the user has signed in from, and an upload from a phone has no business
   * clearing what a desktop wrote. Keys the schema has not declared are dropped here rather than
   * sent, because the service rejects the whole write for one unknown key — which would make this
   * button fail entirely for the sake of a setting that simply has nowhere to go yet.
   */
  private async uploadPreferences(stateRoot: string): Promise<string> {
    const schemaReply = await this.bridge.preferenceSchema();
    if (schemaReply.error !== undefined || schemaReply.value === undefined) {
      return this.failure(schemaReply.error ?? 'account_unavailable');
    }
    const schema = this.schemaOf(schemaReply.value);
    if (schema === null) return this.failure('account_unavailable');
    const cloudReply = await this.bridge.loadPreferenceDocument();
    if (cloudReply.error !== undefined || cloudReply.value === undefined) {
      return this.failure(cloudReply.error ?? 'account_unavailable');
    }
    const cloud = this.cloudOf(cloudReply.value);
    if (cloud === null) return this.failure('account_unavailable');
    const local = this.localDocument(stateRoot);
    if (local === null) return this.failure('account_storage');
    const values = localAccountPreferences(
      local['preferences'] as Record<string, Object>, this.feedbackValues(stateRoot));
    const declared: AccountPreferenceSettings = {};
    let declaredAny = false;
    for (const key of Object.keys(values)) {
      if (schema.fields[key] !== undefined) {
        declared[key] = values[key];
        declaredAny = true;
      }
    }
    if (!declaredAny) return this.failure('account_unavailable');
    const merged = mergeAccountPreferences(cloud, declared, schema);
    const putReply = await this.bridge.putPreferenceDocument(
      merged as Object as Record<string, Object>);
    if (putReply.error !== undefined || putReply.value === undefined) {
      return this.failure(putReply.error ?? 'account_unavailable');
    }
    const updated = this.cloudOf(putReply.value);
    return updated === null ? this.failure('account_unavailable')
      : JSON.stringify({ ok: true, value: updated });
  }

  /**
   * The account's settings, written onto this device.
   *
   * The user id the page names is checked against the session first. It is the one guard this
   * direction needs: the page read those values under one account, and if a different one is signed
   * in by the time the confirmation is answered, writing them replaces the user's own settings with
   * a stranger's and nothing on this screen can put them back.
   */
  private async applyPreferences(userId: string, stateRoot: string): Promise<string> {
    if (userId.length === 0 || this.bridge.currentUserId() !== userId) {
      return this.failure('account_unauthorized');
    }
    const schemaReply = await this.bridge.preferenceSchema();
    if (schemaReply.error !== undefined || schemaReply.value === undefined) {
      return this.failure(schemaReply.error ?? 'account_unavailable');
    }
    const schema = this.schemaOf(schemaReply.value);
    if (schema === null) return this.failure('account_unavailable');
    const cloudReply = await this.bridge.loadPreferenceDocument();
    if (cloudReply.error !== undefined || cloudReply.value === undefined) {
      return this.failure(cloudReply.error ?? 'account_unavailable');
    }
    const cloud = this.cloudOf(cloudReply.value);
    if (cloud === null) return this.failure('account_unavailable');
    // Re-checked after the round trip: a sign-out during it invalidates the answer that just came
    // back, and this is the last point before the write where saying so still costs nothing.
    if (this.bridge.currentUserId() !== userId) return this.failure('account_cancelled');
    const local = this.localDocument(stateRoot);
    if (local === null) return this.failure('account_storage');
    const applied: AppliedPreferences = applyAccountPreferences(
      local['preferences'] as Record<string, Object>, cloud, schema,
      this.feedbackValues(stateRoot));
    const revision: number = local['revision'] as number;
    const saved: string = client.savePreferences(stateRoot, revision,
      JSON.stringify(applied.preferences));
    try {
      const reply: Record<string, Object> = JSON.parse(saved) as Record<string, Object>;
      if (reply['ok'] !== true) return this.failure('account_storage');
    } catch {
      return this.failure('account_storage');
    }
    // The feedback file is written after the document, and its failure is reported rather than
    // rolled back: the settings that did land are correct, and a second attempt is harmless.
    if (applied.feedback !== null) {
      const written = KeyboardSession.saveFeedbackIn(stateRoot,
        KeyboardFeedbackBridge.fromShared({
          soundEnabled: applied.feedback.soundEnabled,
          hapticsEnabled: applied.feedback.hapticsEnabled,
          hapticStrength: applied.feedback.hapticStrength
        }));
      if (!written) return this.failure('account_storage');
    }
    return this.success({});
  }

  async snapshot(actionDocument: string, resources: string, stateRoot: string): Promise<string> {
    let action: SnapshotAction;
    try {
      action = JSON.parse(actionDocument) as SnapshotAction;
      if (typeof action.operation !== 'string') return this.failure('snapshot_invalid');
    } catch {
      return this.failure('snapshot_invalid');
    }
    switch (action.operation) {
      case 'snapshot_status':
        return this.status(resources, stateRoot);
      case 'snapshot_export':
        return this.exportSnapshot(resources, stateRoot);
      case 'snapshot_preview':
        return this.preview(resources, stateRoot);
      case 'snapshot_enqueue':
        return this.enqueue(String(action.token ?? ''), stateRoot);
      case 'snapshot_cancel':
        return this.cancel(stateRoot);
      default:
        return this.failure('snapshot_unavailable');
    }
  }

  private failure(code: string): string {
    return JSON.stringify({ ok: false, error: code });
  }

  private success(value: SnapshotValue): string {
    return JSON.stringify({ ok: true, value: value });
  }

  private options(resources: string, stateRoot: string): Object | null {
    try {
      const reply: SnapshotReply = JSON.parse(client.prepareHost(JSON.stringify({
        resources: resources, state_root: stateRoot
      }))) as SnapshotReply;
      return reply.ok ? reply.value : null;
    } catch {
      return null;
    }
  }

  private queueDirectory(stateRoot: string): string {
    return `${stateRoot}/dictionary-snapshots`;
  }

  private queueState(resources: string, stateRoot: string,
    acknowledge: boolean): SnapshotQueueState | null {
    const options = this.options(resources, stateRoot);
    if (options === null) return null;
    try {
      const action: SnapshotQueueStateAction = {
        operation: 'state', directory: this.queueDirectory(stateRoot),
        options: options, acknowledge: acknowledge
      };
      const reply: SnapshotQueueReply =
        JSON.parse(client.snapshotQueue(JSON.stringify(action))) as SnapshotQueueReply;
      return reply.ok && reply.value !== undefined ? reply.value : null;
    } catch {
      return null;
    }
  }

  private publicRequest(request: NativeSnapshotRequest | null | undefined): SnapshotRequest | null {
    if (request === undefined || request === null) return null;
    return {
      id: request.id,
      cloudRevision: request.cloudRevision,
      expectedLocalVersion: request.expectedLocalVersion,
      fileSha256: request.fileSha256,
      status: request.status
    };
  }

  private async status(resources: string, stateRoot: string): Promise<string> {
    const state = this.queueState(resources, stateRoot, true);
    if (state === null || typeof state.localVersion !== 'string') {
      return this.failure('snapshot_unavailable');
    }
    return this.success({
      localVersion: state.localVersion,
      request: this.publicRequest(state.request)
    });
  }

  private async exportSnapshot(resources: string, stateRoot: string): Promise<string> {
    const result = await this.downloadSnapshot(stateRoot);
    if (result === null) return this.failure('snapshot_unavailable');
    const answer = this.success({ saved: true, snapshot: result });
    this.clearSnapshotPreview();
    return answer;
  }

  private async preview(resources: string, stateRoot: string): Promise<string> {
    const accountId: string | null = this.bridge.currentUserId();
    if (accountId === null) return this.failure('account_unauthorized');
    const result = await this.downloadSnapshot(stateRoot);
    const state = this.queueState(resources, stateRoot, false);
    if (result === null || state === null || typeof state.localVersion !== 'string') {
      this.clearSnapshotPreview();
      return this.failure('snapshot_unavailable');
    }
    if (this.bridge.currentUserId() !== accountId) {
      this.clearSnapshotPreview();
      return this.failure('account_cancelled');
    }
    this.snapshotAccountId = accountId;
    this.snapshotExpectedVersion = state.localVersion;
    this.snapshotToken = util.generateRandomUUID(false);
    return this.success({ previewToken: this.snapshotToken, snapshot: result });
  }

  private inspectSnapshot(file: string): SnapshotMetadata | null {
    try {
      const reply: SnapshotInspectReply = JSON.parse(client.snapshotInspect(file)) as SnapshotInspectReply;
      return reply.ok && reply.value !== undefined ? reply.value : null;
    } catch {
      return null;
    }
  }

  private clearSnapshotPreview(): void {
    try {
      if (this.snapshotFile.length > 0 && fs.accessSync(this.snapshotFile)) fs.unlinkSync(this.snapshotFile);
    } catch {
      // A failed or already absent download has nothing left to remove.
    }
    this.snapshotToken = '';
    this.snapshotAccountId = '';
    this.snapshotFile = '';
    this.snapshotExpectedVersion = '';
    this.snapshotMetadata = undefined;
  }

  private async downloadSnapshot(stateRoot: string): Promise<SnapshotMetadata | null> {
    const response = await this.bridge.rawAuthenticated('GET', '/v1/users/me/dictionary/snapshot');
    if (response.status < 200 || response.status >= 300 || response.body.length === 0) return null;
    if (utf8Length(response.body) > 512 * 1024 * 1024) return null;
    try {
      this.clearSnapshotPreview();
      const directory = `${stateRoot}/cloud-snapshot`;
      if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
      this.snapshotFile = `${directory}/snapshot.ndjson`;
      const handle = fs.openSync(this.snapshotFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(handle.fd, response.body); } finally { fs.closeSync(handle); }
      const metadata = this.inspectSnapshot(this.snapshotFile);
      if (metadata === null) {
        this.clearSnapshotPreview();
        return null;
      }
      this.snapshotMetadata = metadata;
      return this.snapshotMetadata;
    } catch {
      this.clearSnapshotPreview();
      return null;
    }
  }

  private async enqueue(token: string, stateRoot: string): Promise<string> {
    if (token.length === 0 || token !== this.snapshotToken || this.snapshotFile.length === 0
      || this.snapshotMetadata === undefined || this.snapshotExpectedVersion.length === 0
      || this.snapshotAccountId.length === 0
      || this.bridge.currentUserId() !== this.snapshotAccountId) {
      return this.failure('snapshot_invalid');
    }
    try {
      const changes = await this.bridge.rawAuthenticated('GET',
        `/v1/users/me/dictionary/changes?after=${this.snapshotMetadata.cloudRevision}&limit=1`);
      if (changes.status < 200 || changes.status >= 300 || changes.body.length === 0) {
        return this.failure('snapshot_unavailable');
      }
      const page: SnapshotChanges = JSON.parse(changes.body) as SnapshotChanges;
      if (!Array.isArray(page.changes)) return this.failure('snapshot_unavailable');
      if (page.changes.length > 0 || token !== this.snapshotToken
        || this.snapshotMetadata === undefined || this.snapshotFile.length === 0
        || this.bridge.currentUserId() !== this.snapshotAccountId) {
        this.clearSnapshotPreview();
        return this.failure('snapshot_conflict');
      }
      const inspected = this.inspectSnapshot(this.snapshotFile);
      if (inspected === null || inspected.fileSha256 !== this.snapshotMetadata.fileSha256
        || inspected.sha256 !== this.snapshotMetadata.sha256
        || inspected.engineRecords !== this.snapshotMetadata.engineRecords) {
        this.clearSnapshotPreview();
        return this.failure('snapshot_invalid');
      }
      const action: SnapshotQueueEnqueueAction = {
        operation: 'enqueue', directory: this.queueDirectory(stateRoot), source: this.snapshotFile,
        account_id: this.snapshotAccountId, cloud_revision: this.snapshotMetadata.cloudRevision,
        expected_local_version: this.snapshotExpectedVersion,
        file_sha256: this.snapshotMetadata.fileSha256
      };
      const reply: SnapshotQueueReply =
        JSON.parse(client.snapshotQueue(JSON.stringify(action))) as SnapshotQueueReply;
      if (!reply.ok || reply.value === undefined) {
        return this.failure(reply.error ?? 'snapshot_unavailable');
      }
      const request: SnapshotRequest | null = this.publicRequest(reply.value.request);
      this.clearSnapshotPreview();
      return this.success({ request: request });
    } catch {
      return this.failure('snapshot_unavailable');
    }
  }

  private cancel(stateRoot: string): string {
    const accountId: string | null = this.bridge.currentUserId();
    if (accountId === null) return this.failure('account_unauthorized');
    try {
      const action: SnapshotQueueCancelAction = {
        operation: 'cancel', directory: this.queueDirectory(stateRoot), account_id: accountId
      };
      const reply: SnapshotQueueReply =
        JSON.parse(client.snapshotQueue(JSON.stringify(action))) as SnapshotQueueReply;
      if (!reply.ok || reply.value === undefined) {
        return this.failure(reply.error ?? 'snapshot_unavailable');
      }
      this.clearSnapshotPreview();
      return this.success({ request: this.publicRequest(reply.value.request) });
    } catch {
      return this.failure('snapshot_unavailable');
    }
  }
}
