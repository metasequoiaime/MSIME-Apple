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
  modeSwitchShortcuts: boolean;
  panelShortcuts: boolean;
  numberRowSelection: boolean;
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
      modeSwitchShortcuts: desktop,
      panelShortcuts: desktop,
      numberRowSelection: desktop,
      candidateFollowCursor: desktop,
      inputModeHud: desktop,
    };
  }
}
