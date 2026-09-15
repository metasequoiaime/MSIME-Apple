import inputMethodEngine from '@ohos.inputMethodEngine';
import client from 'libmsimeclient.so';

// Shapes of the JSON the shared C ABI answers with. Only the fields this minimal surface reads are
// declared; the responses carry considerably more.
interface Candidate {
  text: string;
  highlighted: boolean;
}

interface EngineView {
  candidates: Candidate[];
  editing_text: string;
  generation: number;
}

interface EngineValue {
  commit: string | null;
  view: EngineView;
}

interface CreateValue {
  session: number;
}

interface Response {
  ok: boolean;
  value: EngineValue;
  error: string;
}

interface CreateResponse {
  ok: boolean;
  value: CreateValue;
  error: string;
}

// ArkTS rejects untyped object literals, so the options document the host sends gets a shape too.
interface SessionPreferences {
  default_ime_mode: string;
  scheme: string;
  candidate_page_size: number;
  learning: boolean;
  chinese_punctuation: boolean;
}

interface SessionOptions {
  api_version: number;
  resources: string;
  user_data: string;
  cache: string;
  dictionaries: string;
  preferences: SessionPreferences;
}

/**
 * Owns the native session for the lifetime of the extension ability and turns key presses into
 * committed text. The ability creates it; the panel's UI reads state back through onChanged.
 *
 * Deliberately thin: the Engine decides what a key means, this only forwards and applies the result.
 */
export class KeyboardSession {
  static readonly shared: KeyboardSession = new KeyboardSession();

  private handle: number = 0;
  private inputClient: inputMethodEngine.InputClient | undefined = undefined;
  private generation: number = 0;

  onChanged: ((candidates: string[], editing: string) => void) | undefined = undefined;

  /** True once the native ABI matches and a session exists. */
  start(resources: string, userData: string, cache: string, dictionaries: string): boolean {
    if (client.abiVersion() !== 2) {
      return false;
    }
    const preferences: SessionPreferences = {
      default_ime_mode: 'chinese',
      scheme: 'quanpin',
      candidate_page_size: 5,
      learning: true,
      chinese_punctuation: true
    };
    const options: SessionOptions = {
      api_version: 1,
      resources: resources,
      user_data: userData,
      cache: cache,
      dictionaries: dictionaries,
      preferences: preferences
    };
    try {
      const created: CreateResponse =
        JSON.parse(client.create(JSON.stringify(options))) as CreateResponse;
      if (!created.ok) {
        return false;
      }
      this.handle = created.value.session;
      return true;
    } catch (error) {
      // A response that will not parse means the ABI moved underneath us. Refusing to start is
      // better than driving a session whose replies we cannot read.
      return false;
    }
  }

  /** The framework hands over a fresh client on every inputStart. */
  attach(inputClient: inputMethodEngine.InputClient): void {
    this.inputClient = inputClient;
    if (this.handle !== 0) {
      this.apply(client.focus(this.handle, true));
    }
  }

  detach(): void {
    if (this.handle !== 0) {
      this.apply(client.focus(this.handle, false));
    }
    this.inputClient = undefined;
  }

  stop(): void {
    if (this.handle !== 0) {
      client.destroy(this.handle);
      this.handle = 0;
    }
  }

  press(ascii: number, shift: boolean): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.character(this.handle, ascii, shift));
  }

  /** Commit the highlighted candidate. 1 is SelectHighlighted in the shared command table. */
  commitHighlighted(): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.command(this.handle, 1));
  }

  /** 0 is Backspace in the shared command table. */
  backspace(): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.command(this.handle, 0));
  }

  choose(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.select(this.handle, this.generation, index));
  }

  private apply(raw: string): void {
    let response: Response;
    try {
      response = JSON.parse(raw) as Response;
    } catch (error) {
      return;
    }
    if (!response.ok) {
      return;
    }
    const value: EngineValue = response.value;
    const commit: string | null = value.commit;
    if (commit !== null && commit.length > 0 && this.inputClient !== undefined) {
      this.inputClient.insertText(commit);
    }
    const view: EngineView = value.view;
    this.generation = view.generation;
    const texts: string[] = [];
    for (const candidate of view.candidates) {
      texts.push(candidate.text);
    }
    if (this.onChanged !== undefined) {
      this.onChanged(texts, view.editing_text);
    }
  }
}
