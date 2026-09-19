/**
 * Shared preference gates for the two optional annotations a candidate can carry.
 *
 * Both arrive in the prepared host document, and the two differ in what an absent value means, which
 * is the whole reason this is a policy rather than a pair of reads at the call site. `wubi_code_hint`
 * is an optional field the shared store omits entirely when it has never been set, and the shared
 * `Preferences::wubi_code_hint_enabled` reads that absence as on; `candidate_english_gloss` is always
 * serialised and defaults to off, so anything that is not literally true leaves the gloss hidden.
 */
export class CandidateAnnotationPreferencePolicy {
  /** Absent or malformed means on, matching the shared accessor rather than the JSON default. */
  static wubiCodeHint(value: unknown): boolean {
    return value !== false;
  }

  /** Offline glosses are off unless the document says otherwise. */
  static englishGloss(value: unknown): boolean {
    return value === true;
  }
}
