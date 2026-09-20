import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import client from 'libmsimeclient.so';
import { AccountCloudBridge, AccountSessionStore, AccountTransport, AccountTransportResponse } from './AccountCloudBridge';
import { KeyboardSession } from '../keyboard/KeyboardSession';
import { utf8Length } from '../keyboard/Utf8';

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

interface SnapshotRequest {
  id: string;
  cloudRevision: number;
  expectedLocalVersion: string;
  fileSha256: string;
  status: string;
}

interface SnapshotLine {
  type?: string;
  revision?: number;
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

interface SnapshotPrepareRequest {
  options: Object;
  staging_root: string;
  expected_version: string;
  records: number;
}

interface HttpHeaders {
  Accept: string;
  Authorization?: string;
  'Content-Type': string;
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
      return { status: response.responseCode, body: typeof response.result === 'string' ? response.result : '' };
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
  bytes: number;
  records: number;
  entries: number;
  overlays: number;
  positions: number;
  selections: number;
}

/** Account and cloud clipboard state stays in the host; WebView receives only bounded DTOs. */
export class HarmonyAccountCloudBridge {
  private readonly bridge: AccountCloudBridge;
  private readonly context: common.UIAbilityContext;
  private snapshotFile: string = '';
  private snapshotToken: string = '';
  private snapshotHandle: number = 0;
  private snapshotExpectedVersion: string = '';
  private snapshotMetadata: SnapshotMetadata | undefined = undefined;
  private snapshotEngineRecords: number = 0;

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

  request(action: string): Promise<string> {
    return this.bridge.handle(action);
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
        return this.enqueue(String(action.token ?? ''), resources, stateRoot);
      case 'snapshot_cancel':
        return this.cancel();
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

  private localVersion(resources: string, stateRoot: string): string | null {
    const options = this.options(resources, stateRoot);
    if (options === null) return null;
    try {
      const reply: SnapshotReply = JSON.parse(client.snapshotVersion(JSON.stringify(options))) as SnapshotReply;
      const version: string | undefined = reply.value?.version;
      return reply.ok && typeof version === 'string' && /^[0-9a-f]{64}$/.test(version) ? version : null;
    } catch {
      return null;
    }
  }

  private async status(resources: string, stateRoot: string): Promise<string> {
    const version = this.localVersion(resources, stateRoot);
    if (version === null) return this.failure('snapshot_unavailable');
    const applied = this.tryActivate(resources, stateRoot);
    const request: SnapshotRequest | null = this.snapshotHandle === 0 ? null : {
      id: this.snapshotToken, cloudRevision: this.snapshotMetadata?.cloudRevision ?? 0,
      expectedLocalVersion: this.snapshotExpectedVersion, fileSha256: '',
      status: applied ? 'applied' : 'queued'
    };
    if (applied) {
      this.snapshotHandle = 0;
      this.snapshotToken = '';
      this.snapshotMetadata = undefined;
      this.snapshotEngineRecords = 0;
      try { if (this.snapshotFile.length > 0 && fs.accessSync(this.snapshotFile)) fs.unlinkSync(this.snapshotFile); } catch { /* best effort cleanup */ }
      this.snapshotFile = '';
    }
    return this.success({ localVersion: version, request: request });
  }

  private async exportSnapshot(resources: string, stateRoot: string): Promise<string> {
    const result = await this.downloadSnapshot(stateRoot);
    return result === null ? this.failure('snapshot_unavailable') : this.success({ saved: true, snapshot: result });
  }

  private async preview(resources: string, stateRoot: string): Promise<string> {
    const result = await this.downloadSnapshot(stateRoot);
    const version = this.localVersion(resources, stateRoot);
    if (result === null || version === null) return this.failure('snapshot_unavailable');
    this.snapshotExpectedVersion = version;
    this.snapshotToken = `${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
    return this.success({ previewToken: this.snapshotToken, snapshot: result });
  }

  private async downloadSnapshot(stateRoot: string): Promise<SnapshotMetadata | null> {
    const response = await this.bridge.rawAuthenticated('GET', '/v1/users/me/dictionary/snapshot');
    if (response.status < 200 || response.status >= 300 || response.body.length === 0) return null;
    if (utf8Length(response.body) > 512 * 1024 * 1024) return null;
    try {
      const directory = `${stateRoot}/cloud-snapshot`;
      if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
      this.snapshotFile = `${directory}/snapshot.ndjson`;
      const handle = fs.openSync(this.snapshotFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { fs.writeSync(handle.fd, response.body); } finally { fs.closeSync(handle); }
      let revision = 0;
      let records = 0;
      let engineRecords = 0;
      let entries = 0;
      let overlays = 0;
      let positions = 0;
      let selections = 0;
      for (const line of response.body.split('\n')) {
        if (!line) continue;
        const value: SnapshotLine = JSON.parse(line) as SnapshotLine;
        if (value.type === 'header' && typeof value.revision === 'number') revision = value.revision;
        if (value.type === 'header' || value.type === 'entry' || value.type === 'overlay' || value.type === 'position' || value.type === 'selection') records++;
        if (value.type === 'entry') { entries++; }
        if (value.type === 'overlay') { engineRecords++; overlays++; }
        if (value.type === 'position') { engineRecords++; positions++; }
        if (value.type === 'selection') { engineRecords++; selections++; }
      }
      this.snapshotMetadata = { cloudRevision: revision, sha256: '', bytes: response.body.length,
        records: records, entries: entries, overlays: overlays, positions: positions, selections: selections };
      this.snapshotEngineRecords = engineRecords;
      if (engineRecords === 0 || revision < 0) {
        try { if (fs.accessSync(this.snapshotFile)) fs.unlinkSync(this.snapshotFile); } catch { /* best effort cleanup */ }
        this.snapshotFile = '';
        this.snapshotMetadata = undefined;
        this.snapshotEngineRecords = 0;
        return null;
      }
      return this.snapshotMetadata;
    } catch {
      return null;
    }
  }

  private enqueue(token: string, resources: string, stateRoot: string): string {
    if (token.length === 0 || token !== this.snapshotToken || this.snapshotFile.length === 0
      || this.snapshotMetadata === undefined || this.snapshotExpectedVersion.length !== 64) {
      return this.failure('snapshot_invalid');
    }
    const options: Object | null = this.options(resources, stateRoot);
    if (options === null) return this.failure('snapshot_unavailable');
    try {
      const staging = `${this.context.cacheDir}/msime-snapshot-staging`;
      if (!fs.accessSync(staging)) fs.mkdirSync(staging, true);
      const request: SnapshotPrepareRequest = {
        options: options, staging_root: staging, expected_version: this.snapshotExpectedVersion,
        records: this.snapshotEngineRecords
      };
      const reply: SnapshotReply = JSON.parse(client.snapshotPrepare(JSON.stringify(request), this.snapshotFile)) as SnapshotReply;
      const handle: number | undefined = reply.value?.handle;
      if (!reply.ok || typeof handle !== 'number' || handle <= 0) return this.failure('snapshot_unavailable');
      this.snapshotHandle = handle;
      return this.success({ request: { id: token, cloudRevision: this.snapshotMetadata.cloudRevision,
        expectedLocalVersion: this.snapshotExpectedVersion, fileSha256: '', status: 'queued' } });
    } catch {
      return this.failure('snapshot_unavailable');
    }
  }

  private tryActivate(resources: string, stateRoot: string): boolean {
    if (this.snapshotHandle === 0) return false;
    const result = KeyboardSession.shared.snapshotActivate(this.snapshotHandle, this.snapshotExpectedVersion);
    try {
      const reply: SnapshotReply = JSON.parse(result) as SnapshotReply;
      return reply.ok;
    } catch {
      return false;
    }
  }

  private cancel(): string {
    if (this.snapshotHandle !== 0) {
      try { client.snapshotDiscard(this.snapshotHandle); } catch { /* best effort cleanup */ }
    }
    try {
      if (this.snapshotFile.length > 0 && fs.accessSync(this.snapshotFile)) fs.unlinkSync(this.snapshotFile);
    } catch { /* best effort cleanup */ }
    this.snapshotHandle = 0;
    this.snapshotToken = '';
    this.snapshotFile = '';
    this.snapshotMetadata = undefined;
    this.snapshotEngineRecords = 0;
    return this.success({ request: null });
  }
}
