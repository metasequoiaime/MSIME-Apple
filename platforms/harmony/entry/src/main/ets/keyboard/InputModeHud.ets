import { KeyboardSession } from './KeyboardSession';

/**
 * The badge that says which mode a switch landed in, ported from
 * platforms/macos/src/InputModeHUDPanel.mm.
 *
 * A capsule rather than a square, because the logo and the character sit side by side the way the
 * badge on a toolbar carries them. It appears under the caret, close enough to be read without
 * looking away from what is being typed, and it goes again on its own: it never takes focus and
 * never takes a click. The host owns the window and the timing; this is only its face.
 */

/** The Metasequoia forest green and the ink that reads on it, from the shared iOS theme. */
const FOREST_LIGHT: string = '#185C48';
const FOREST_DARK: string = '#61B491';
// White reads 7.9:1 on the light green and 2.5:1 on the dark one, so the dark shade takes ink.
const ON_FOREST_LIGHT: string = '#FFFFFF';
const ON_FOREST_DARK: string = '#14231D';

const CORNER_RADIUS_VP: number = 16;
const LOGO_SIDE_VP: number = 30;
const CONTENT_SPACING_VP: number = 6;
const MODE_FONT_SIZE: number = 26;

@Entry
@Component
struct InputModeHud {
  @State english: boolean = false;
  @State dark: boolean = false;

  aboutToAppear(): void {
    KeyboardSession.shared.onModeBadge = (english: boolean, dark: boolean): void => {
      this.english = english;
      this.dark = dark;
    };
  }

  aboutToDisappear(): void {
    KeyboardSession.shared.onModeBadge = undefined;
  }

  private ink(): string {
    return this.dark ? ON_FOREST_DARK : ON_FOREST_LIGHT;
  }

  build() {
    Row({ space: CONTENT_SPACING_VP }) {
      Image($r('app.media.keyboard_brand'))
        .width(LOGO_SIDE_VP)
        .height(LOGO_SIDE_VP)
        .fillColor(this.ink())
      // 中 or 英: the state being switched to, not the pair being switched between.
      Text(this.english ? '英' : '中')
        .fontSize(MODE_FONT_SIZE)
        .fontColor(this.ink())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.dark ? FOREST_DARK : FOREST_LIGHT)
    .borderRadius(CORNER_RADIUS_VP)
  }
}
