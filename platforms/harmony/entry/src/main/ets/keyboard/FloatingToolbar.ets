import { KeyboardSession } from './KeyboardSession';
import { ToolbarState, ToolbarButton, FloatingToolbarLayout } from './FloatingToolbarLayout';
import { KeyboardSkin } from './skin/KeyboardSkin';
import { ToolbarSkin, ToolbarSkinPolicy } from './ToolbarSkinPolicy';

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

@Entry
@Component
struct FloatingToolbar {
  @State state: ToolbarState = FloatingToolbarLayout.idleState();
  @State buttons: ToolbarButton[] = [];
  @State hoveredButton: ToolbarButton | undefined = undefined;
  @State fontSize: number = 24;
  @State scale: number = 1;
  // The same skin the keyboard wears, so a bar floating beside it does not look like another app's.
  @State skin: KeyboardSkin = KeyboardSkin.from('forest', false);
  @State toolbarSkin: ToolbarSkin = ToolbarSkinPolicy.base(KeyboardSkin.from('forest', false));

  aboutToAppear(): void {
    KeyboardSession.shared.onToolbar = (state: ToolbarState, buttons: ToolbarButton[],
                                        fontSize: number, scale: number, skin: KeyboardSkin,
                                        toolbarSkin: ToolbarSkin): void => {
      this.state = state;
      this.buttons = buttons;
      this.fontSize = fontSize;
      this.scale = scale;
      this.skin = skin;
      this.toolbarSkin = toolbarSkin;
    };
  }

  aboutToDisappear(): void {
    KeyboardSession.shared.onToolbar = undefined;
  }

  build() {
    const scale: number = FloatingToolbarLayout.scale(this.scale);
    const buttonWidth: number = FloatingToolbarLayout.buttonWidthVp(scale);
    const buttonGap: number = FloatingToolbarLayout.buttonGapVp(scale);
    const edgeInset: number = FloatingToolbarLayout.edgeInsetVp(scale);
    const toolbarHeight: number = FloatingToolbarLayout.heightVp(scale);
    const cornerRadius: number = this.toolbarSkin.cornerRadiusVp * scale;
    const handleWidth: number = 2.5 * scale;
    const handleHeight: number = 14 * scale;
    const dividerWidth: number = 1.2 * scale;
    const dividerHeight: number = Math.max(1, toolbarHeight - 2 * scale);
    // The colour goes on a container that fills the panel rather than on the row of buttons: a panel
    // is transparent where nothing is drawn, and a row only covers the buttons it holds.
    Column() {
      Row({ space: buttonGap }) {
        Column()
          .width(handleWidth)
          .height(handleHeight)
          .backgroundColor(this.toolbarSkin.dragHandleColor)
          .borderRadius(2 * scale)
        Column()
          .width(dividerWidth)
          .height(dividerHeight)
          .backgroundColor(this.toolbarSkin.dividerColor)
        ForEach(this.buttons, (button: ToolbarButton) => {
          Text(FloatingToolbarLayout.face(button, this.state))
            .fontSize((button === ToolbarButton.SETTINGS ? this.fontSize - 2 : this.fontSize) * scale)
          .fontColor(button === ToolbarButton.SETTINGS
            ? this.toolbarSkin.settingsColor : this.toolbarSkin.buttonColor)
          .fontFamily(button === ToolbarButton.INPUT_MODE && this.state.english
            ? this.toolbarSkin.englishFontFamily : this.toolbarSkin.fontFamily)
          .textAlign(TextAlign.Center)
          .width(buttonWidth)
          .height(toolbarHeight - edgeInset)
          .borderRadius(6 * scale)
          .backgroundColor(this.hoveredButton === button
            ? this.toolbarSkin.buttonHoverColor : '#00000000')
          .onHover((isHover: boolean): void => {
            this.hoveredButton = isHover ? button : undefined;
          })
          .onClick(() => KeyboardSession.shared.runToolbarButton(button))
      }, (button: ToolbarButton) => `${button}:${FloatingToolbarLayout.face(button, this.state)}`)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.toolbarSkin.backgroundColor)
    .borderRadius(cornerRadius)
    // A bar with nothing behind it needs its own edge: it floats over whatever the desktop happens
    // to be, and on a pale one a pale surface with no border is a row of letters in mid-air.
    .borderWidth(1)
    .borderColor(this.toolbarSkin.borderColor)
    .shadow({ radius: 12, color: '#33000000', offsetY: 2 })
  }
}
