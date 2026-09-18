import { KeyboardSession } from './KeyboardSession';
import { ToolbarState, ToolbarButton, FloatingToolbarLayout } from './FloatingToolbarLayout';
import { KeyboardSkin } from './skin/KeyboardSkin';

/**
 * The bar that says what mode the keyboard is in and lets it be changed, ported from
 * platforms/macos/src/FloatingToolbarPanel.mm.
 *
 * A desktop has no keyboard on screen to carry this, so without it the only evidence of the mode is
 * the badge that flashes when it changes. Each button shows the state it is in rather than the one
 * it would switch to — 中 while composing Chinese, not 英 — which is the rule the Apple toolbar
 * follows and the opposite of what a button normally does.
 *
 * The gear is never hidden. Hiding the toolbar and opening the settings are both behind it, so
 * turning off the last of the others still has to leave a way back out.
 */

const TOOLBAR_HEIGHT_VP: number = 44;
const BUTTON_WIDTH_VP: number = 42;
const BUTTON_GAP_VP: number = 10.5;
const EDGE_INSET_VP: number = 10;
const CORNER_RADIUS_VP: number = 10;

@Entry
@Component
struct FloatingToolbar {
  @State state: ToolbarState = FloatingToolbarLayout.idleState();
  @State buttons: ToolbarButton[] = [];
  @State fontSize: number = 20;
  // The same skin the keyboard wears, so a bar floating beside it does not look like another app's.
  @State skin: KeyboardSkin = KeyboardSkin.from('forest', false);

  aboutToAppear(): void {
    KeyboardSession.shared.onToolbar = (state: ToolbarState, buttons: ToolbarButton[],
                                        fontSize: number, skin: KeyboardSkin): void => {
      this.state = state;
      this.buttons = buttons;
      this.fontSize = fontSize;
      this.skin = skin;
    };
  }

  aboutToDisappear(): void {
    KeyboardSession.shared.onToolbar = undefined;
  }

  build() {
    // The colour goes on a container that fills the panel rather than on the row of buttons: a panel
    // is transparent where nothing is drawn, and a row only covers the buttons it holds.
    Column() {
      Row({ space: BUTTON_GAP_VP }) {
      ForEach(this.buttons, (button: ToolbarButton) => {
        Text(FloatingToolbarLayout.face(button, this.state))
          .fontSize(button === ToolbarButton.SETTINGS ? this.fontSize - 2 : this.fontSize)
          .fontColor(button === ToolbarButton.SETTINGS
            ? this.skin.keyForeground : this.skin.accent)
          .textAlign(TextAlign.Center)
          .width(BUTTON_WIDTH_VP)
          .height(TOOLBAR_HEIGHT_VP - EDGE_INSET_VP)
          .onClick(() => KeyboardSession.shared.runToolbarButton(button))
      }, (button: ToolbarButton) => `${button}:${FloatingToolbarLayout.face(button, this.state)}`)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(CORNER_RADIUS_VP)
    // A bar with nothing behind it needs its own edge: it floats over whatever the desktop happens
    // to be, and on a pale one a pale surface with no border is a row of letters in mid-air.
    .borderWidth(1)
    .borderColor(this.skin.borderColor)
    .shadow({ radius: 12, color: '#33000000', offsetY: 2 })
  }
}
