/**
 * Deciding whether the packaged Engine resources still match the staged copy.
 *
 * The resources ship inside the HAP and are copied out once, because `prepare_host` wants a real
 * filesystem path and the packaged directory is read-only. The copy then has to be kept honest: the
 * shared verification compares the staged directory against the pinned lock exactly, down to
 * containing no extra file, so a staged copy left over from an older package is not merely stale —
 * it is refused, and the keyboard refuses to start with `existing resource generation has unexpected
 * files`.
 *
 * A marker saying only "staged" cannot express that. It said so after the first copy and went on
 * saying so after the package changed underneath it. The marker now carries which generation was
 * staged, so a package that no longer matches is copied again instead of trusted.
 *
 * The token is the packaged listing — every name and size, in a fixed order. It needs to change
 * whenever the set does and to cost nothing to compute, which rules out hashing a hundred and eighty
 * megabytes on every keyboard start; two artifacts that differ in neither name nor length are not a
 * case this is defending against, and the shared verification checks the digests anyway.
 */
const MAX_TOKEN_LENGTH: number = 4096;

export interface StagedArtifact {
  readonly name: string;
  readonly size: number;
}

export class StagedResourcePolicy {
  /** A stable identity for one packaged resource set, or '' if it cannot be described. */
  static generationToken(artifacts: StagedArtifact[]): string {
    if (artifacts.length === 0) {
      return '';
    }
    const parts: string[] = [];
    for (const artifact of artifacts) {
      if (artifact.name.length === 0 || artifact.name.includes(':')
          || !Number.isFinite(artifact.size) || artifact.size < 0) {
        return '';
      }
      parts.push(`${artifact.name}:${artifact.size}`);
    }
    // Sorted so the filesystem's own ordering, which is not guaranteed, cannot change the token.
    parts.sort();
    const token: string = parts.join('\n');
    return token.length > MAX_TOKEN_LENGTH ? '' : token;
  }

  /**
   * Whether the packaged resources have to be copied out again.
   *
   * An undescribable package is staged rather than skipped: copying twice costs a moment, and
   * skipping when it was needed costs a keyboard that will not start.
   */
  static needsStaging(marker: string | null, token: string): boolean {
    return token.length === 0 || marker === null || marker.trim() !== token;
  }
}
