/**
 * Reading and writing the preference document without an Engine session.
 *
 * The keyboard changes preferences through its live session, which also pushes them into the Engine
 * it is already holding. The settings page has no session and needs none: it edits the document on
 * disk, and the keyboard picks the change up when it next starts. Both go through the same store, so
 * the revision check that keeps two writers from overwriting each other applies to both.
 *
 * Every value is whatever the shared schema says it is; nothing is interpreted here beyond the few
 * fields the page shows, so an unknown key written by a newer build survives a save from this one.
 */
import client from 'libmsimeclient.so';
import { KeyboardLog } from './KeyboardLog';

interface Snapshot {
  revision: number;
  preferences: Record<string, Object>;
}

interface LoadResponse {
  ok: boolean;
  value: Snapshot;
  error: string;
}

interface SaveResponse {
  ok: boolean;
  error: string;
}

export class PreferenceStore {
  private readonly directory: string;
  private snapshot: Snapshot | undefined = undefined;

  constructor(directory: string) {
    this.directory = directory;
  }

  /** The document as it is on disk, or undefined if it could not be read. */
  load(): Record<string, Object> | undefined {
    try {
      const response: LoadResponse =
        JSON.parse(client.loadPreferences(this.directory)) as LoadResponse;
      if (!response.ok) {
        KeyboardLog.error(`preferences unreadable: ${response.error}`);
        return undefined;
      }
      this.snapshot = response.value;
      return response.value.preferences;
    } catch (error) {
      KeyboardLog.error(`preferences unreadable: ${error}`);
      return undefined;
    }
  }

  /**
   * Write one value back.
   *
   * Re-reads before writing rather than trusting what was loaded when the page opened: the keyboard
   * is a second writer, and the revision the store compares against has to be the one on disk now or
   * the save is refused. Refusal is the correct outcome for a genuine conflict, but not for a page
   * that has merely been open for a while.
   */
  save(key: string, value: Object): boolean {
    const current: Record<string, Object> | undefined = this.load();
    if (current === undefined || this.snapshot === undefined) {
      return false;
    }
    const expected: number = this.snapshot.revision;
    current[key] = value;
    const document: string = JSON.stringify({
      revision: expected + 1, preferences: current
    } as Snapshot);
    try {
      const response: SaveResponse =
        JSON.parse(client.savePreferences(this.directory, expected, document)) as SaveResponse;
      if (!response.ok) {
        KeyboardLog.error(`preferences refused: ${response.error}`);
        return false;
      }
      return true;
    } catch (error) {
      KeyboardLog.error(`preferences unwritable: ${error}`);
      return false;
    }
  }
}
