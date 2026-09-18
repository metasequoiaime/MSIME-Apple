/** The dictionary operations that need the Engine's exclusive maintenance window. */
const MUTATING_OPERATIONS: string[] = ['edit', 'import', 'retry', 'dismiss_failure'];

export interface DictionaryMaintenanceDecision {
  maintenance: boolean;
  allowed: boolean;
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
    const maintenance: boolean = MUTATING_OPERATIONS.indexOf(operation) >= 0;
    return {
      maintenance,
      allowed: !maintenance || !composing,
      error: maintenance && composing ? 'dictionary maintenance busy' : ''
    };
  }
}
