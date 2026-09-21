/** The dictionary operations that need the Engine's exclusive maintenance window. */
const MUTATING_OPERATIONS: string[] = ["edit", "import", "retry", "dismiss_failure"];

/**
 * The operations that go to the queue instead of the Engine.
 *
 * Importing a file is the one request whose timing the user chooses freely: they are as likely to
 * do it with the keyboard up as with it down, and "dictionary maintenance busy" is not an answer
 * to "add these words". The queued route writes a file the keyboard drains the next time it starts
 * a session, which is the one moment no session is open.
 *
 * Only this one. An edit made in the settings window is a single word the user is watching for in
 * the list beside it, and sending that through a queue would show the list unchanged until the
 * keyboard next started — which looks exactly like the edit having been lost.
 */
const QUEUED_OPERATIONS: string[] = ["import_personal"];

export interface DictionaryMaintenanceDecision {
  maintenance: boolean;
  allowed: boolean;
  /** The request goes to the personal-dictionary queue rather than to the Engine. */
  queued: boolean;
  error: string;
}

/**
 * Keeps the session-level safety rule independent from NAPI and ArkUI.
 *
 * Reads can share a live Engine session. Mutations may recreate an idle session, but must be
 * rejected while the user is composing so dictionary management never discards in-progress input.
 */
export class DictionaryMaintenancePolicy {
  static decide(operation: string, composing: boolean): DictionaryMaintenanceDecision {
    const queued: boolean = QUEUED_OPERATIONS.indexOf(operation) >= 0;
    // A queued request touches its own file and never the Engine, so it neither needs the
    // maintenance window nor has any reason to be refused mid-composition.
    const maintenance: boolean = !queued && MUTATING_OPERATIONS.indexOf(operation) >= 0;
    return {
      maintenance,
      queued,
      allowed: !maintenance || !composing,
      error: maintenance && composing ? "dictionary maintenance busy" : "",
    };
  }
}
