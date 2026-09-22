/**
 * Which kind of machine the keyboard is running on.
 *
 * The same HAP is declared for phone, tablet and 2in1, and the difference that matters to an input
 * method is whether the user already has keys under their hands. A phone has none, so the panel is a
 * soft keyboard fixed to the bottom of the screen. A 2in1 has a physical keyboard and needs only
 * somewhere to put the candidates, which is what PanelFlag.FLAG_CANDIDATE is for.
 *
 * Read once: a device does not change what it is while the process is alive, and this is consulted
 * on every layout pass.
 */
import deviceInfo from "@ohos.deviceInfo";
import { KeyboardFormFactorPolicy } from "./KeyboardFormFactorPolicy";

const DESKTOP: boolean = KeyboardFormFactorPolicy.isDesktop(deviceInfo.deviceType);

export class KeyboardFormFactor {
  /** A machine whose keys are already under the user's hands, so this one draws none. */
  static isDesktop(): boolean {
    return DESKTOP;
  }

  /** What the device calls itself, for the log line that says which kind of panel was created. */
  static describe(): string {
    return deviceInfo.deviceType;
  }
}
