import InputMethodExtensionAbility from '@ohos.InputMethodExtensionAbility';
import inputMethodEngine from '@ohos.inputMethodEngine';
import Want from '@ohos.app.ability.Want';
import { KeyboardSession } from '../keyboard/KeyboardSession';

const engine: inputMethodEngine.InputMethodAbility = inputMethodEngine.getInputMethodAbility();

/**
 * The HarmonyOS input method host. The system starts it when an editor takes focus, so the panel is
 * created here rather than by opening a window of our own.
 *
 * A phone keeps the soft keyboard in FLG_FIXED. A 2in1 host switches the same panel to FLAG_CANDIDATE
 * with changeFlag, which is why this host is shared across both form factors instead of duplicated.
 */
export default class KeyboardExtensionAbility extends InputMethodExtensionAbility {
  private panel: inputMethodEngine.Panel | undefined = undefined;

  // off('inputStop') requires the same callback reference that on() received, unlike off('inputStart')
  // where it is optional. Holding both as fields keeps unsubscribing honest.
  private readonly started: (kbController: inputMethodEngine.KeyboardController,
                             inputClient: inputMethodEngine.InputClient) => void =
    (kbController: inputMethodEngine.KeyboardController,
     inputClient: inputMethodEngine.InputClient): void => {
      KeyboardSession.shared.attach(inputClient);
      if (this.panel !== undefined) {
        this.panel.show();
      }
    };

  private readonly stopped: () => void = (): void => {
    KeyboardSession.shared.detach();
    if (this.panel !== undefined) {
      this.panel.hide();
    }
  };

  async onCreate(want: Want): Promise<void> {
    const files: string = this.context.filesDir;
    const resources: string = `${this.context.resourceDir}/engine`;
    if (!KeyboardSession.shared.start(resources, `${files}/user`, this.context.cacheDir,
        `${files}/dictionaries`)) {
      // Without a session there is nothing to show. Leaving the panel uncreated keeps the framework
      // from presenting an inert keyboard.
      return;
    }
    const info: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: inputMethodEngine.PanelFlag.FLG_FIXED
    };
    try {
      this.panel = await engine.createPanel(this.context, info);
      await this.panel.setUiContent('ets/keyboard/KeyboardView');
    } catch (error) {
      // The framework allows exactly one soft keyboard panel. If it refused, the session has nothing
      // to draw into, so tear it back down rather than leaving it attached to no surface.
      KeyboardSession.shared.stop();
      this.panel = undefined;
      return;
    }
    engine.on('inputStart', this.started);
    engine.on('inputStop', this.stopped);
  }

  onDestroy(): void {
    engine.off('inputStart', this.started);
    engine.off('inputStop', this.stopped);
    KeyboardSession.shared.stop();
    if (this.panel !== undefined) {
      engine.destroyPanel(this.panel);
      this.panel = undefined;
    }
  }
}
