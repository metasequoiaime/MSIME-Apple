import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { AccountCloudBridge, AccountSessionStore, AccountTransport } from './AccountCloudBridge';

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

class HarmonyTransport implements AccountTransport {
  async request(method: string, path: string, token?: string,
    body?: Record<string, unknown>): Promise<{ status: number; body: string }> {
    if (!path.startsWith('/v1/') || path.includes('\\')) throw new Error('account_invalid');
    const request = http.createHttp();
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (token !== undefined) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const options: http.HttpRequestOptions = {
      method: this.method(method),
      header: headers,
      connectTimeout: 30000,
      readTimeout: 30000,
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
      case 'PATCH': return http.RequestMethod.PATCH;
      case 'DELETE': return http.RequestMethod.DELETE;
      default: return http.RequestMethod.GET;
    }
  }
}

/** Account and cloud clipboard state stays in the host; WebView receives only bounded DTOs. */
export class HarmonyAccountCloudBridge {
  private readonly bridge: AccountCloudBridge;

  constructor(context: common.UIAbilityContext) {
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
}
