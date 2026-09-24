import { KeyboardFormFactorPolicy } from "../KeyboardFormFactorPolicy";

/** The settings capabilities that exist only with HarmonyOS's desktop input surface. */
export interface SettingsFormFactorProjection {
  mobileSettings: boolean;
  panelWindows: boolean;
  floatingToolbar: boolean;
  floatingToolbarAppearance: boolean;
  floatingToolbarComponents: boolean;
  /** The pad and voice buttons exist only on the 2in1 toolbar, so only there is switching them off an outcome. */
  floatingToolbarHandwriting: boolean;
  floatingToolbarVoice: boolean;
  /** Mode-switch chords, number-row selection and the voice hotkeys are routed on every device once a keyboard is attached, so their switches are offered on every device too: hiding them on a phone left behaviour the owner could not turn off. */
  modeSwitchShortcuts: boolean;
  panelShortcuts: boolean;
  numberRowSelection: boolean;
  voiceHotkeys: boolean;
  /** A phone draws its candidates as one horizontal strip whatever the preference says; only the 2in1 candidate window can be a vertical list. */
  fixedCandidateLayout: "horizontal" | null;
  candidateFollowCursor: boolean;
  inputModeHud: boolean;
}

/** Keep the shared settings page aligned with the keyboard's actual device form factor. */
export class SettingsFormFactorCapabilities {
  static resolve(deviceType: string | null | undefined): SettingsFormFactorProjection {
    const desktop: boolean = KeyboardFormFactorPolicy.isDesktop(deviceType);
    return {
      mobileSettings: !desktop,
      panelWindows: desktop,
      floatingToolbar: desktop,
      floatingToolbarAppearance: desktop,
      floatingToolbarComponents: desktop,
      floatingToolbarHandwriting: desktop,
      floatingToolbarVoice: desktop,
      modeSwitchShortcuts: true,
      panelShortcuts: desktop,
      numberRowSelection: true,
      voiceHotkeys: true,
      fixedCandidateLayout: desktop ? null : "horizontal",
      candidateFollowCursor: desktop,
      inputModeHud: desktop,
    };
  }
}
