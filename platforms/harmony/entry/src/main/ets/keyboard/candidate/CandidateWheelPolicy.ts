/**
 * Maps ArkUI vertical axis events to candidate-page actions.
 *
 * ArkUI reports the angular change for one wheel action rather than the
 * Windows WHEEL_DELTA constant. A non-zero sign therefore represents one
 * page request; the host keeps the preference gate and calls the engine's
 * existing page commands.
 */
export class CandidateWheelPolicy {
  static previousPage(delta: number): boolean {
    return delta > 0;
  }

  static nextPage(delta: number): boolean {
    return delta < 0;
  }
}
