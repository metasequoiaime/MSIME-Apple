/** Small, host-neutral pieces of the Windows candidate presentation contract. */
export class CandidatePresentationPolicy {
  static badge(source: number): string {
    if (source === 2) return ' ☁️';
    if (source === 3) return ' 🤖';
    return '';
  }
}
