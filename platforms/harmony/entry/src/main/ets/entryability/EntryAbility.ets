import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import window from '@ohos.window';
import { KeyboardLog, describeError } from '../keyboard/KeyboardLog';

/**
 * The application the keyboard belongs to.
 *
 * An input method extension has no window of its own beyond its panel, and on a 2in1 that panel is a
 * candidate window with no room for the surfaces a phone reaches from its key faces. Everything that
 * is a setting rather than a keystroke lives here instead: one window, one page, and the preference
 * document the keyboard reads when it next starts.
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launch: AbilityConstant.LaunchParam): void {
    KeyboardLog.info('app created');
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Settings', (error: Error): void => {
      if (error) {
        KeyboardLog.error(`settings page would not load: ${describeError(error)}`);
      }
    });
  }
}
