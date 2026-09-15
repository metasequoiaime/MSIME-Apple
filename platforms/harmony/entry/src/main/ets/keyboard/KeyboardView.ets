import { KeyboardSession } from './KeyboardSession';

// The minimum surface that proves the whole stack: a candidate bar fed by the Engine and enough keys
// to reach it. The skins, nine-key layout, handwriting canvas and toolbar all land on top of this.
const ROWS: string[][] = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm']
];

@Entry
@Component
struct KeyboardView {
  @State candidates: string[] = [];
  @State editing: string = '';

  aboutToAppear(): void {
    KeyboardSession.shared.onChanged = (candidates: string[], editing: string): void => {
      this.candidates = candidates;
      this.editing = editing;
    };
  }

  aboutToDisappear(): void {
    KeyboardSession.shared.onChanged = undefined;
  }

  @Builder
  candidateBar() {
    Row() {
      if (this.candidates.length === 0) {
        Text(this.editing)
          .fontSize(16)
          .fontColor('#666666')
          .layoutWeight(1)
          .padding({ left: 12 })
      } else {
        Scroll() {
          Row() {
            ForEach(this.candidates, (candidate: string, index: number) => {
              Text(candidate)
                .fontSize(20)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => KeyboardSession.shared.choose(index))
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height(44)
    .backgroundColor('#f2f2f2')
  }

  build() {
    Column() {
      this.candidateBar()
      ForEach(ROWS, (row: string[]) => {
        Row() {
          ForEach(row, (key: string) => {
            Button(key)
              .fontSize(18)
              .layoutWeight(1)
              .margin(2)
              .onClick(() => KeyboardSession.shared.press(key.charCodeAt(0), false))
          })
        }
        .width('100%')
        .height(46)
        .justifyContent(FlexAlign.Center)
      })
      Row() {
        Button('⌫')
          .fontSize(16)
          .layoutWeight(1)
          .margin(2)
          .onClick(() => KeyboardSession.shared.backspace())
        Button(' ')
          .layoutWeight(3)
          .margin(2)
          .onClick(() => KeyboardSession.shared.press(0x20, false))
        Button('↵')
          .fontSize(16)
          .layoutWeight(1)
          .margin(2)
          .onClick(() => KeyboardSession.shared.commitHighlighted())
      }
      .width('100%')
      .height(46)
    }
    .width('100%')
    .backgroundColor('#ffffff')
  }
}
