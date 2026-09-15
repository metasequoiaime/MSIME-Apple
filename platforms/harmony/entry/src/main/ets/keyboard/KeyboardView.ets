import {
  KeyboardSession, KeyboardPreferences, KeyboardState, CandidateEntry, EmojiPage, EmojiRow
} from './KeyboardSession';
import { KeyboardScheme, SchemeDefinition } from './KeyboardScheme';
import { KeyboardSkin } from './KeyboardSkin';
import { EnglishLetterCaseState, LetterCaseMode } from './EnglishLetterCaseState';
import { LetterKeyFacePolicy } from './LetterKeyFacePolicy';
import { ShuangpinKeyHintPolicy } from './ShuangpinKeyHintPolicy';
import { ReturnKeyAction } from './ReturnKeyAction';
import { InputDiagnosticPolicy } from './InputDiagnosticPolicy';
import { LocalInputMode, LocalInputModeDefinition } from './LocalInputMode';
import { CandidateWrapPolicy } from './CandidateWrapPolicy';
import { QuickPunctuationPolicy, PunctuationEntry } from './QuickPunctuationPolicy';
import {
  JapaneseNineKeyLayout, JapaneseKey, VariantGroup, DIRECTION_CENTRE
} from './JapaneseNineKeyLayout';
import { JapaneseNineKeyActions } from './JapaneseNineKeyActions';
import { JapaneseVariantPolicy } from './JapaneseVariantPolicy';
import { CandidateManagementAction, ManagementAction } from './CandidateManagementAction';
import { KeyboardMetrics } from './KeyboardMetrics';
import { KeyboardGeometry } from './KeyboardGeometry';
import { NineKeyLayout, NineKey } from './NineKeyLayout';
import { SpaceCursorMovement } from './SpaceCursorMovement';
import { EmojiCatalogModel, EmojiCategory, EmojiItem, EMOJI_PAGE_SIZE } from './EmojiCatalogModel';
import { InputMethodListDialog } from '@ohos.inputMethodList';
import { KeyboardLog, describeError } from './KeyboardLog';
import {
  ClipboardHistoryStore, ClipboardHistoryItem, ClipboardHistoryError
} from './ClipboardHistoryStore';

/**
 * The 26-key touch keyboard, laid out to the same metrics as the iOS extension in
 * platforms/ios/KeyboardExtension/Sources/KeyboardViewController.swift, which is the reference
 * implementation for how this keyboard is meant to look and behave.
 *
 * Keys are drawn as Text in a bordered container rather than with Button. Button carries a default
 * horizontal padding, and ten keys to a row do not leave room for it: the glyph loses its right-hand
 * third instead of shrinking. The iOS code zeroes the same insets for the same reason.
 */

/**
 * One parameter, passed by reference.
 *
 * A @Builder that takes its arguments by value is rendered once and never again, so a key built that
 * way keeps the face it was created with: Shift would not change the letters, and the return key
 * would still read 换行 while candidates were on screen. Passing a single object through $$ is what
 * makes ArkUI re-render the subtree when the state behind it moves.
 */
interface KeyOptions {
  face: string;
  /** The double-pinyin unit under the letter, or empty when the key does not stand for one. */
  hint?: string;
  size: number;
  emphasized: boolean;
  width: number;
  action: () => void;
}

const LETTER_ROWS: string[][] = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm']
];

// The same three rows the iOS keyboard offers behind its 123 key.
const SYMBOL_ROWS: string[][] = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  [',', '.', '?', '!', ';', ':', '\'', '"', '@', '/'],
  ['(', ')', '[', ']', '<', '>', '\\', '-', '_', '=']
];

/**
 * What these keys send while composing Chinese, taken from the Engine's punctuation contract.
 *
 * The keys are labelled with the ASCII that produces them, because nothing else on the keyboard says
 * that a backslash is how one types a 、 — which is the question people actually ask. Showing what
 * the key will produce answers it without spending a second key on it. Paired marks show their
 * opening half; the Engine alternates on its own.
 */
// The two narrow columns either side of the nine-key grid, as a share of the keyboard's width. The
// iOS layout ties both to the same fraction so the grid stays square-ish across phone widths.
const NINE_KEY_COLUMN_PERCENT: number = 14;

// Long enough that a deliberate tap never repeats, short enough that a hold does not feel stuck.
const BACKSPACE_DELAY_MILLIS: number = 400;
const BACKSPACE_REPEAT_MILLIS: number = 60;
// How far the finger travels for one cursor step. Roughly a key width, which is what a step feels
// like it should cost.
const CURSOR_STEP_VP: number = 12;
const KEY_HINT_FONT_SIZE: number = 10;
// Roughly a third of a key. Shorter than this is a tap on the centre kana, not a flick.
const FLICK_THRESHOLD_VP: number = 16;
// The Engine's own numbering for Japanese, which the ported policies are written against.
const JAPANESE_SCHEME: number = 3;

// A category runs to a few hundred entries; this is the ceiling that keeps a catalog which never
// reports itself complete from spinning here forever.
const EMOJI_MAX_PAGES: number = 16;
const EMOJI_COLUMNS: number = 8;

// Said plainly rather than as an error, because nothing is broken: the platform reserves clipboard
// reads for system applications and this is not one.
const CLIPBOARD_NOT_PERMITTED: string =
  '系统未授予读取剪贴板的权限，第三方输入法无法保存剪贴板历史。';

const CHINESE_SYMBOL_FACES: Map<string, string> = new Map<string, string>([
  [',', '，'], ['.', '。'], ['?', '？'], ['!', '！'], [';', '；'], [':', '：'],
  ['\'', '‘'], ['"', '“'], ['\\', '、'], ['(', '（'], [')', '）'],
  ['[', '【'], [']', '】'], ['<', '《'], ['>', '》']
]);

@Entry
@Component
struct KeyboardView {
  @State candidates: CandidateEntry[] = [];
  @State editing: string = '';
  @State spellings: string[] = [];
  @State engineScheme: number = 0;
  @State shuangpinProfile: string = 'xiaohe';
  @State localMode: string = 'none';
  @State diagnostic: string = '';
  @State punctuation: boolean = false;
  @State managing: number = -1;
  @State variants: boolean = false;
  @State english: boolean = false;
  @State symbols: boolean = false;
  @State nineKey: boolean = false;
  /** Scheme 3 is Japanese, which has its own grid rather than a pinyin one. */
  @State japanese: boolean = false;
  @State emoji: boolean = false;
  @State emojiGroup: string = EmojiCatalogModel.categories()[0].group;
  @State emojiItems: string[] = [];
  @State picker: string = '';
  @State clipboard: boolean = false;
  @State clips: ClipboardHistoryItem[] = [];
  @State clipboardNotice: string = '';
  @State confirmingClear: boolean = false;
  @State expanded: string[] = [];
  @State availableWidth: number = 0;
  @State caseMode: LetterCaseMode = LetterCaseMode.LOWERCASE;
  @State skin: KeyboardSkin = KeyboardSkin.from('forest', false);
  @State scheme: SchemeDefinition = KeyboardScheme.QUANPIN;

  private readonly letterCase: EnglishLetterCaseState = new EnglishLetterCaseState();
  private settings: KeyboardPreferences = KeyboardSession.shared.preferences();
  private readonly cursorDrag: SpaceCursorMovement = new SpaceCursorMovement();
  // A held Delete repeats, and letting go has to stop it, so the timer outlives the callback.
  private backspaceTimer: number = -1;
  private dragged: boolean = false;
  private diagnosticTimer: number = -1;
  private pendingRemoval: number = -1;
  private flickX: number = 0;
  private flickY: number = 0;
  // The system's own keyboard chooser. It is a dialog rather than something drawn here because the
  // list of installed input methods is the system's to show, not ours to reproduce.
  private readonly switcher: CustomDialogController = new CustomDialogController({
    builder: InputMethodListDialog({}),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    this.english = KeyboardSession.shared.isEnglish();
    this.settings = KeyboardSession.shared.preferences();
    this.skin = KeyboardSkin.from(this.settings.skinId, this.settings.dark);
    this.scheme = this.resolveScheme(this.settings.layout);
    this.nineKey = this.scheme.touchKeyboardLayout === 'nine_key';
    this.japanese = this.scheme.engineScheme === 'japanese' && this.nineKey;
    KeyboardSession.shared.setNineKey(this.nineKey);
    KeyboardSession.shared.onEditorChanged = (): void => {
      // A URI or password field opens in Latin whatever the user last chose, so the face has to
      // follow or it would claim a language the Engine is not composing in.
      this.english = KeyboardSession.shared.isEnglish();
    };
    KeyboardSession.shared.onChanged = (state: KeyboardState): void => {
      this.candidates = state.candidates;
      this.editing = state.editing;
      this.spellings = state.spellings;
      this.engineScheme = state.scheme;
      this.japanese = state.scheme === JAPANESE_SCHEME && !state.english
        && this.scheme.touchKeyboardLayout === 'nine_key';
      this.shuangpinProfile = state.shuangpinProfile;
      this.localMode = state.localMode;
      this.diagnostic = state.diagnostic;
      if (state.diagnostic.length > 0) {
        // Transient by design: it describes what just happened, and leaving it up would have it
        // still describing that long after the next thing.
        this.clearDiagnosticLater();
      }
      this.english = state.english;
      if (state.candidates.length === 0) {
        // The list belonged to a composition that no longer exists; keeping it on screen would offer
        // choices for something the user has already finished or abandoned.
        this.expanded = [];
      }
    };
  }

  aboutToDisappear(): void {
    KeyboardSession.shared.onChanged = undefined;
    KeyboardSession.shared.onEditorChanged = undefined;
    this.stopBackspace();
  }

  /**
   * Holding Delete keeps deleting, which is the difference between removing a word and tapping
   * eleven times. The first repeat waits longer than the rest so a normal tap never becomes two.
   */
  private startBackspace(): void {
    this.stopBackspace();
    KeyboardSession.shared.backspace();
    this.backspaceTimer = setTimeout((): void => {
      this.backspaceTimer = setInterval((): void => {
        KeyboardSession.shared.backspace();
      }, BACKSPACE_REPEAT_MILLIS);
    }, BACKSPACE_DELAY_MILLIS);
  }

  private clearDiagnosticLater(): void {
    if (this.diagnosticTimer !== -1) {
      clearTimeout(this.diagnosticTimer);
    }
    this.diagnosticTimer = setTimeout((): void => {
      this.diagnostic = '';
      this.diagnosticTimer = -1;
    }, InputDiagnosticPolicy.DISMISS_DELAY_MILLIS);
  }

  private stopBackspace(): void {
    if (this.backspaceTimer !== -1) {
      clearTimeout(this.backspaceTimer);
      clearInterval(this.backspaceTimer);
      this.backspaceTimer = -1;
    }
  }

  /**
   * 拼音键面用大写,切到英文才回小写。Every Chinese keyboard draws its 26 keys in caps, and the case
   * there is only a typeface: the key still feeds a lowercase letter to the Engine. Shift belongs to
   * English, where the case decides what actually lands in the document.
   *
   * 本地模式除外 —— 那里敲进去的就是字面的小写字母,键面写大写就是在骗人。
   */
  private letterFace(letter: string): string {
    return LetterKeyFacePolicy.face(letter, !this.english, this.localMode !== 'none',
      this.caseMode !== LetterCaseMode.LOWERCASE);
  }

  /** The double-pinyin unit a key stands for, printed along its bottom edge while it means one. */
  private letterHint(letter: string): string {
    return ShuangpinKeyHintPolicy.hint(this.shuangpinProfile, letter, this.english,
      this.engineScheme, this.localMode);
  }

  private tapLetter(letter: string): void {
    // Shift means two different things depending on what is open. Over a pinyin composition an
    // uppercase letter is helpcode for the Engine, which is why the Engine is told the key was
    // shifted; with nothing composing it is only a capital, and in Chinese mode not even that.
    const held: boolean = this.caseMode !== LetterCaseMode.LOWERCASE;
    const shifted: boolean = KeyboardSession.shared.entersHelpcode(held)
      || (this.english && held);
    KeyboardSession.shared.press(letter.charCodeAt(0), shifted);
    // A one-shot Shift is spent by the letter that follows it; Caps Lock is not.
    if (this.caseMode === LetterCaseMode.SHIFTED) {
      this.letterCase.reset();
      this.caseMode = this.letterCase.mode();
    }
  }

  @Builder
  keyFace($$: KeyOptions) {
    Column() {
      Text($$.face)
        .fontSize($$.size)
        .maxLines(1)
        .fontColor($$.emphasized ? this.skin.actionForeground : this.skin.keyForeground)
        .fontFamily(this.skin.monospaced ? 'monospace' : undefined)
        .textAlign(TextAlign.Center)
        .width('100%')
      if ($$.hint !== undefined && $$.hint.length > 0) {
        // Along the bottom edge, which is why the letter above it is not centred in the whole key.
        Text($$.hint)
          .fontSize(KEY_HINT_FONT_SIZE)
          .maxLines(1)
          .fontColor(this.skin.accent)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }

  /** A key that shares the row's spare width equally with its siblings. */
  @Builder
  flexibleKey($$: KeyOptions) {
    Column() {
      this.keyFace($$)
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor($$.emphasized ? this.skin.actionBackground : this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(this.skin.borderWidth)
    .borderColor(this.skin.borderColor)
    .onClick($$.action)
  }

  /** A key whose width is fixed, so Shift and Delete stay the same size whatever the row holds. */
  @Builder
  fixedKey($$: KeyOptions) {
    Column() {
      this.keyFace($$)
    }
    .width($$.width)
    .height('100%')
    .backgroundColor($$.emphasized ? this.skin.actionBackground : this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(this.skin.borderWidth)
    .borderColor(this.skin.borderColor)
    .onClick($$.action)
  }

  /**
   * Loads one group of the catalog, a page at a time until the Engine says it is complete.
   *
   * The whole group is gathered before it is shown rather than paged in the panel: a category is a
   * few hundred entries at most, and a grid that grows while a finger is on it is worse than a
   * short wait. validatePage is the ported check that a page which advances nowhere while claiming
   * to be incomplete does not loop this forever.
   */
  private loadEmoji(group: string): void {
    this.emojiGroup = group;
    const collected: string[] = [];
    let offset: number = 0;
    for (let page: number = 0; page < EMOJI_MAX_PAGES; page++) {
      const result: EmojiPage | null =
        KeyboardSession.shared.emojiPage(group, offset, EMOJI_PAGE_SIZE);
      if (result === null) {
        break;
      }
      // Each row is checked as it is read and the page as a whole before it is trusted; a row the
      // catalog cannot honour is not worth showing, and a bad page would loop this forever.
      const items: EmojiItem[] = [];
      try {
        for (const row of result.items) {
          items.push(EmojiCatalogModel.item(row.text, row.annotation, row.group));
        }
        EmojiCatalogModel.validatePage(items, offset, EMOJI_PAGE_SIZE, result.next_offset,
          result.complete);
      } catch (error) {
        break;
      }
      for (const item of items) {
        collected.push(item.text);
      }
      offset = result.next_offset;
      if (result.complete) {
        break;
      }
    }
    this.emojiItems = collected;
  }

  private selectScheme(candidate: SchemeDefinition): void {
    // The composition belongs to the scheme that was current when it was typed; carrying it into a
    // different one would reinterpret letters that were never meant that way.
    KeyboardSession.shared.cancel();
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('scheme', candidate.engineScheme);
    changes.set('touch_keyboard_layout', candidate.touchKeyboardLayout);
    if (candidate.shuangpinProfile !== null) {
      changes.set('shuangpin_profile', candidate.shuangpinProfile);
    }
    if (!KeyboardSession.shared.changePreferences(changes)) {
      return;
    }
    KeyboardSession.shared.useScheme(candidate.engineScheme);
    this.scheme = candidate;
    this.nineKey = candidate.touchKeyboardLayout === 'nine_key';
    // The kana grid belongs to the scheme, not to what the Engine last reported: the Engine only
    // says so once something has been typed, and the face has to change before that.
    this.japanese = candidate.engineScheme === 'japanese' && candidate.touchKeyboardLayout
      === 'nine_key';
    this.variants = false;
    KeyboardSession.shared.setNineKey(this.nineKey);
    this.picker = '';
  }

  private selectSkin(choice: KeyboardSkin): void {
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('touch_keyboard_skin', choice.id);
    if (!KeyboardSession.shared.changePreferences(changes)) {
      return;
    }
    this.skin = choice;
    this.picker = '';
  }

  /**
   * The scheme is what the candidate strip names, and the grid is part of its identity: quanpin on
   * nine keys is a different scheme from quanpin on twenty-six, so switching the face has to switch
   * the scheme with it or the strip goes on claiming a layout that is no longer on screen.
   */
  /**
   * The schemes this host can actually deliver.
   *
   * Handwriting needs a platform recognizer to be injected, as Android injects one, and HarmonyOS
   * has no equivalent — the engine is built without it here. The thoughtful reply surface is not
   * implemented on this host either. Offering a scheme that cannot compose would be worse than not
   * offering it: the keyboard would simply stop responding to keys with no explanation.
   *
   * Filtered here rather than in KeyboardScheme, whose declaration order is the fixed order every
   * host's pickers render in.
   */
  private offeredSchemes(): SchemeDefinition[] {
    return KeyboardScheme.SCHEMES.filter((candidate: SchemeDefinition): boolean =>
      candidate.id !== 'HANDWRITING' && candidate.id !== 'THOUGHTFUL_REPLY');
  }

  private resolveScheme(layout: string): SchemeDefinition {
    return KeyboardScheme.fromPreferences(this.settings.scheme, this.settings.shuangpinProfile,
      layout);
  }

  /** A symbol wears the face of what it will insert, which in Chinese is not the ASCII on the cap. */
  private symbolFace(symbol: string): string {
    const chinese: string | undefined = CHINESE_SYMBOL_FACES.get(symbol);
    return !this.english && chinese !== undefined ? chinese : symbol;
  }

  private symbolKey(symbol: string): KeyOptions {
    return {
      face: this.symbolFace(symbol),
      size: KeyboardMetrics.KEY_FONT_SIZE,
      emphasized: false,
      width: 0,
      action: () => KeyboardSession.shared.press(symbol.charCodeAt(0), false)
    };
  }

  /**
   * What a key's appearance depends on, folded into its ForEach identity.
   *
   * ForEach with no key generator identifies an item by its own value, and a letter is always the
   * same letter, so its subtree is never rebuilt: the faces stayed lowercase after switching to
   * Chinese and the shuangpin hints never appeared, while the return key beside them updated fine
   * because it is not inside a ForEach at all.
   */
  /** Tenths of a vp in the store, whole vp on screen. */
  private keySpacing(): number {
    return this.settings.keySpacingTenths / 10;
  }

  private rowSpacing(): number {
    return this.settings.rowSpacingTenths / 10;
  }

  /** The adjustment is spread across the key rows so none of them keeps a stray pixel. */
  private rowHeight(index: number): number {
    return KeyboardGeometry.adjustedRowHeight(KeyboardMetrics.ROW_HEIGHT_VP,
      this.settings.heightAdjustment, KeyboardMetrics.KEY_ROWS, index);
  }

  /**
   * What the strip calls the keyboard when nothing is being composed.
   *
   * A local mode takes the name, because while one is running the keys do something other than what
   * the scheme says and the user is owed that.
   */
  private title(): string {
    const mode: LocalInputModeDefinition | null =
      LocalInputMode.fromPreferenceKey(this.localMode);
    return mode === null ? this.scheme.title : mode.title;
  }

  private faceKey(): string {
    return `${this.english}:${this.caseMode}:${this.localMode}:${this.shuangpinProfile}:`
      + `${this.engineScheme}:${this.skin.key()}`;
  }

  /**
   * Which candidates share a row, decided by the ported wrap policy rather than by Flex.
   *
   * Width is estimated rather than measured: ArkUI reports text extent only after layout and the
   * wrap decision has to precede it. A CJK candidate is about one font size per character, which is
   * close enough to keep a row from overflowing.
   */
  private expandedRows(): number[][] {
    const widths: number[] = [];
    for (const candidate of this.expanded) {
      widths.push(candidate.length * KeyboardMetrics.CANDIDATE_FONT_SIZE
        + KeyboardMetrics.CANDIDATE_PADDING_VP * 2);
    }
    const assignment: number[] = CandidateWrapPolicy.rows(this.availableWidth, 0, widths);
    const rows: number[][] = [];
    for (let index: number = 0; index < assignment.length; index++) {
      while (rows.length <= assignment[index]) {
        rows.push([]);
      }
      rows[assignment[index]].push(index);
    }
    return rows;
  }

  private letterKey(letter: string): KeyOptions {
    return {
      face: this.letterFace(letter),
      hint: this.letterHint(letter),
      size: KeyboardMetrics.KEY_FONT_SIZE,
      emphasized: false,
      width: 0,
      action: () => this.tapLetter(letter)
    };
  }

  /**
   * The composition gets a line of its own. Sharing the candidate row costs it width on the one row
   * where width is worth most, which is the reasoning the iOS implementation records.
   */
  @Builder
  candidateStrip() {
    Column() {
      Row() {
        Text(this.diagnostic.length > 0
          ? this.diagnostic
          : (this.editing.length > 0 ? this.editing : this.title()))
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.editing.length > 0 || this.diagnostic.length > 0
            ? this.skin.accent : this.skin.keyForeground)
          .opacity(this.editing.length > 0 || this.diagnostic.length > 0 ? 1 : 0.55)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          // The strip names the scheme, so it is also where one changes it. Only when it is not
          // busy showing a composition, which is what the name gives way to.
          .onClick(() => {
            if (this.editing.length === 0) {
              this.picker = this.picker === 'scheme' ? '' : 'scheme';
            }
          })
        // The strip's right-hand end is the toolbar. These belong here rather than on the action
        // row: seven fixed-width keys left the space bar too narrow for its own label.
        Text('📋')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            if (this.clipboard) {
              this.clipboard = false;
            } else {
              this.openClipboard();
            }
          })
        Text('😀')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.emoji = !this.emoji;
            if (this.emoji && this.emojiItems.length === 0) {
              this.loadEmoji(this.emojiGroup);
            }
          })
        Text(this.nineKey ? '26' : '九')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            // Switching the face abandons whatever was being spelled: the taps on one grid do not
            // mean the same thing on the other, so carrying them across would compose nonsense.
            KeyboardSession.shared.cancel();
            this.nineKey = !this.nineKey;
            KeyboardSession.shared.setNineKey(this.nineKey);
            this.scheme = this.resolveScheme(this.nineKey ? 'nine_key' : 'twenty_six_key');
          })
        Text(this.english ? 'En' : this.scheme.glyph)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .padding({ left: 8 })
          .onClick(() => {
            this.picker = this.picker === 'skin' ? '' : 'skin';
          })
      }
      .width('100%')
      .height(KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP, right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Row() {
        Scroll() {
          Row() {
            ForEach(this.candidates, (candidate: CandidateEntry, index: number) => {
              Row() {
                Text(candidate.text)
                  .fontSize(KeyboardMetrics.CANDIDATE_FONT_SIZE)
                  .fontColor(index === 0 ? this.skin.accent : this.skin.keyForeground)
                // The untyped tail of a Wubi code, and any suffix the Engine derived. Both are
                // printed beside the candidate and neither is part of what gets committed.
                if (candidate.hint.length > 0) {
                  Text(candidate.hint)
                    .fontSize(KEY_HINT_FONT_SIZE)
                    .fontColor(this.skin.keyForeground)
                    .opacity(0.5)
                    .padding({ left: 2 })
                }
                if (candidate.annotation.length > 0) {
                  Text(candidate.annotation)
                    .fontSize(KEY_HINT_FONT_SIZE)
                    .fontColor(this.skin.accent)
                    .opacity(0.7)
                    .padding({ left: 4 })
                }
              }
              .alignItems(VerticalAlign.Center)
              .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                right: KeyboardMetrics.CANDIDATE_PADDING_VP })
              .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP)
              .onClick(() => KeyboardSession.shared.choose(index))
              .gesture(LongPressGesture().onAction(() => {
                this.punctuation = false;
                this.managing = index;
              }))
            }, (candidate: CandidateEntry, index: number) => `${index}:${candidate.text}`)
          }
          .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP)
        .align(Alignment.Start)
        if (this.candidates.length > 0) {
          Text('∨')
            .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
            .fontColor(this.skin.accent)
            .padding({ left: 10, right: 12 })
            .onClick(() => {
              this.expanded = KeyboardSession.shared.allCandidates();
            })
        }
      }
      .width('100%')
      .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP)
    }
    .width('100%')
    .backgroundColor(this.skin.keyBackground)
    .opacity(0.82)
    .borderRadius(KeyboardMetrics.STRIP_CORNER_VP)
    .onAreaChange((_old: Area, now: Area): void => {
      this.availableWidth = Number(now.width);
    })
  }

  /**
   * The nine-key face: punctuation down the left, the 3x3 grid, and delete/重输/0 down the right.
   *
   * The two narrow columns are a fraction of the width rather than a fixed size, which is how the
   * iOS layout keeps the grid itself square-ish across phone widths.
   */
  @Builder
  nineKeyFace() {
    Row({ space: this.keySpacing() }) {
      Column() {
        // One column, two jobs, exactly as the iOS sidebar does it: the readings the digits could
        // stand for while something is being spelled, and the common punctuation when nothing is.
        if (this.spellings.length > 0) {
          Scroll() {
            Column() {
              ForEach(this.spellings, (spelling: string, index: number) => {
                Text(spelling)
                  .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
                  .fontColor(this.skin.accent)
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
                  .onClick(() => KeyboardSession.shared.chooseSpelling(index))
              })
            }
            .width('100%')
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
        } else {
          ForEach(NineKeyLayout.punctuation(), (symbol: string) => {
            Column() {
              Text(symbol)
                .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
                .fontColor(this.skin.keyForeground)
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .onClick(() => KeyboardSession.shared.press(symbol.charCodeAt(0), false))
          })
        }
      }
      .width(`${NINE_KEY_COLUMN_PERCENT}%`)
      .height('100%')
      .backgroundColor(this.skin.keyBackground)
      .opacity(0.5)
      .borderRadius(KeyboardMetrics.KEY_CORNER_VP)

      Column({ space: this.rowSpacing() }) {
        ForEach(NineKeyLayout.rows(), (row: NineKey[]) => {
          Row({ space: this.keySpacing() }) {
            ForEach(row, (key: NineKey) => {
              this.flexibleKey({
                face: key.label,
                size: KeyboardMetrics.SMALL_KEY_FONT_SIZE,
                emphasized: false,
                width: 0,
                action: () => KeyboardSession.shared.press(key.input.charCodeAt(0), false)
              });
            })
          }
          .layoutWeight(1)
          .width('100%')
        })
      }
      .layoutWeight(1)
      .height('100%')

      Column({ space: this.rowSpacing() }) {
        Column() {
          this.deleteKey('100%')
        }
        .layoutWeight(1)
        .width('100%')
        this.nineKeyControl('重输', () => KeyboardSession.shared.cancel());
        this.nineKeyControl('0', () => KeyboardSession.shared.press(0x30, false));
      }
      .width(`${NINE_KEY_COLUMN_PERCENT}%`)
      .height('100%')
    }
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 + KeyboardMetrics.ROW_SPACING_VP * 2)
  }

  /**
   * Delete is the one key that cares about the whole gesture rather than the tap, so it is built
   * separately: the press starts the repeat and any end of the touch stops it, including one that
   * ends with the finger somewhere else.
   */
  @Builder
  deleteKey(width: Length) {
    Column() {
      Text('⌫')
        .fontSize(KeyboardMetrics.KEY_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width(width)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(this.skin.borderWidth)
    .borderColor(this.skin.borderColor)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.startBackspace();
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.stopBackspace();
      }
    })
  }

  /**
   * Space, which also moves the cursor when the finger slides along it.
   *
   * The accumulator is the ported SpaceCursorMovement: it carries the leftover distance between
   * events so a slow drag still moves, and abandons the gesture outright on an implausible jump
   * rather than clamping it, because a jump that large means the gesture was already lost. A drag
   * that moved the cursor must not also type a space, which is what dragged tracks.
   */
  @Builder
  spaceKey() {
    Column() {
      Text(this.japanese
        ? JapaneseNineKeyActions.spaceTitle(this.editing.length > 0)
        : (this.english ? 'space' : '空格'))
        .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(this.skin.borderWidth)
    .borderColor(this.skin.borderColor)
    .onTouch((event: TouchEvent): void => {
      const position: number = event.touches[0].windowX;
      if (event.type === TouchType.Down) {
        this.cursorDrag.begin(position, this);
        this.dragged = false;
      } else if (event.type === TouchType.Move) {
        const steps: number = this.cursorDrag.advance(position, this, CURSOR_STEP_VP);
        for (let step: number = 0; step < Math.abs(steps); step++) {
          if (steps < 0) {
            KeyboardSession.shared.moveLeft();
          } else {
            KeyboardSession.shared.moveRight();
          }
          this.dragged = true;
        }
      } else {
        this.cursorDrag.cancel();
        if (!this.dragged && event.type === TouchType.Up) {
          KeyboardSession.shared.press(0x20, false);
        }
      }
    })
  }

  private openClipboard(): void {
    this.clipboard = true;
    this.clips = KeyboardSession.shared.clipboardHistory();
    this.clipboardNotice = '';
    this.confirmingClear = false;
  }

  /**
   * Saves whatever the system clipboard holds now.
   *
   * Nothing is captured in the background. An input method that quietly recorded every copy would be
   * collecting the user's text without being asked, so this happens only when the button is pressed.
   */
  private captureClipboard(): void {
    KeyboardSession.shared.canReadClipboard().then((allowed: boolean): void => {
      if (!allowed) {
        this.clipboardNotice = CLIPBOARD_NOT_PERMITTED;
        return;
      }
      this.storeClipboardText();
    });
  }

  private storeClipboardText(): void {
    KeyboardSession.shared.systemClipboardText().then((text: string): void => {
      try {
        const updated: ClipboardHistoryItem[] =
          ClipboardHistoryStore.add(this.clips, text, Date.now());
        if (KeyboardSession.shared.saveClipboardHistory(updated)) {
          this.clips = updated;
          this.clipboardNotice = '';
        }
      } catch (error) {
        this.clipboardNotice = error instanceof ClipboardHistoryError
          ? error.failure : describeError(error);
      }
    });
  }

  private sendKana(key: JapaneseKey, direction: number): void {
    const stroke: string = key.strokes[direction];
    if (stroke.length === 0) {
      // A label with no stroke is punctuation or a mark: it goes in as it stands.
      KeyboardSession.shared.insert(key.kana[direction]);
      return;
    }
    for (const character of stroke) {
      KeyboardSession.shared.press(character.charCodeAt(0), false);
    }
  }

  private manageCandidate(action: ManagementAction, index: number): void {
    if (action.confirmationRequired && this.pendingRemoval !== index) {
      // Deleting a dictionary entry is not undoable from here, so the first press only arms it.
      this.pendingRemoval = index;
      this.diagnostic = '再次选择“删除词条…”以确认';
      this.clearDiagnosticLater();
      return;
    }
    this.pendingRemoval = -1;
    this.managing = -1;
    switch (action.id) {
      case 'PROMOTE':
        KeyboardSession.shared.promoteCandidate(index);
        break;
      case 'FIX_FIRST':
        KeyboardSession.shared.fixCandidateFirst(index);
        break;
      case 'CLEAR_POSITION':
        KeyboardSession.shared.clearCandidatePosition(index);
        break;
      default:
        KeyboardSession.shared.removeCandidate(index);
        break;
    }
    this.diagnostic = action.announcement;
    this.clearDiagnosticLater();
  }

  private updateClips(updated: ClipboardHistoryItem[]): void {
    if (KeyboardSession.shared.saveClipboardHistory(updated)) {
      this.clips = updated;
    }
  }

  /**
   * The scheme and skin pickers, which take over the key rows rather than floating above them.
   *
   * An extension panel is a fixed rectangle with nothing to overlay, so a popup would either be
   * clipped at the panel edge or force the panel to grow and shove the editor up the screen. Taking
   * the space that is already there costs nothing and needs no resize.
   */
  @Builder
  pickerFace() {
    Column() {
      Row() {
        Text(this.picker === 'scheme' ? '输入方案' : '键盘皮肤')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .layoutWeight(1)
        Text('完成')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => {
            this.picker = '';
          })
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Scroll() {
        Column({ space: KeyboardMetrics.KEY_SPACING_VP }) {
          if (this.picker === 'scheme') {
            ForEach(this.offeredSchemes(), (candidate: SchemeDefinition) => {
              this.pickerRow(candidate.title, candidate.badge,
                candidate.preferenceId === this.scheme.preferenceId,
                () => this.selectScheme(candidate));
            })
          } else {
            ForEach(KeyboardSkin.builtIns(this.settings.dark), (choice: KeyboardSkin) => {
              this.pickerRow(choice.title, choice.description, choice.id === this.skin.id,
                () => this.selectSkin(choice));
            })
          }
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 + KeyboardMetrics.ROW_SPACING_VP * 2)
  }

  @Builder
  pickerRow(title: string, detail: string, selected: boolean, action: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(selected ? this.skin.accent : this.skin.keyForeground)
          .width('100%')
        Text(detail)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .opacity(0.55)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (selected) {
        Text('✓').fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE).fontColor(this.skin.accent)
      }
    }
    .width('100%')
    .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
      right: KeyboardMetrics.CANDIDATE_PADDING_VP, top: 4, bottom: 4 })
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .onClick(action)
  }

  /**
   * The Japanese kana grid, where each key carries five kana and a flick picks between them.
   *
   * The stroke sent to the Engine is the romanisation, not the kana on the key: the Engine composes
   * from romaji, and the label is what the typist is looking for. An empty stroke marks a label that
   * commits directly rather than composing.
   */
  @Builder
  japaneseFace() {
    Column({ space: this.rowSpacing() }) {
      ForEach([0, 1, 2], (row: number) => {
        Row({ space: this.keySpacing() }) {
          ForEach([0, 1, 2], (column: number) => {
            this.kanaKey(JapaneseNineKeyLayout.keys()[row * 3 + column]);
          }, (column: number) => `${row}:${column}:${this.faceKey()}`)
        }
        .layoutWeight(1)
        .width('100%')
      }, (row: number) => `${row}:${this.faceKey()}`)

      // The last row is two kana keys and the variant key, which is where the layout puts it: there
      // are eleven kana keys, not twelve, and the twelfth cell is what 小゛゜ occupies.
      Row({ space: this.keySpacing() }) {
        this.variantKey();
        this.kanaKey(JapaneseNineKeyLayout.keys()[9]);
        this.kanaKey(JapaneseNineKeyLayout.keys()[10]);
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 + KeyboardMetrics.ROW_SPACING_VP * 2)
  }

  /** 小假名、浊音、半浊音. Only means anything once kana have been composed, so it says so. */
  @Builder
  variantKey() {
    Column() {
      Text('小゛゜')
        .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
        .fontColor(JapaneseVariantPolicy.enabled(this.japanese, this.symbols,
          this.editing.length > 0) ? this.skin.keyForeground : this.skin.keyForeground)
        .opacity(JapaneseVariantPolicy.enabled(this.japanese, this.symbols,
          this.editing.length > 0) ? 1 : 0.35)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(this.skin.borderWidth)
    .borderColor(this.skin.borderColor)
    .onClick(() => {
      if (JapaneseVariantPolicy.enabled(this.japanese, this.symbols, this.editing.length > 0)) {
        this.variants = true;
      }
    })
  }

  /**
   * One kana key. The flick is read from the touch that ends it rather than from a gesture
   * recogniser, because the direction is the whole meaning of the movement and the ported
   * JapaneseNineKeyLayout.direction already decides it: the larger axis wins, so a diagonal never
   * falls between two directions.
   */
  @Builder
  kanaKey($$: JapaneseKey) {
    Column() {
      Text($$.kana[DIRECTION_CENTRE])
        .fontSize(KeyboardMetrics.KEY_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(this.skin.borderWidth)
    .borderColor(this.skin.borderColor)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.flickX = event.touches[0].windowX;
        this.flickY = event.touches[0].windowY;
      } else if (event.type === TouchType.Up) {
        const direction: number = JapaneseNineKeyLayout.direction(
          event.touches[0].windowX - this.flickX, event.touches[0].windowY - this.flickY,
          FLICK_THRESHOLD_VP);
        this.sendKana($$, direction);
      }
    })
  }

  /** The post-kana variants: small kana, voiced and semi-voiced forms, grouped as the Engine has them. */
  @Builder
  variantFace() {
    Scroll() {
      Column({ space: KeyboardMetrics.KEY_SPACING_VP }) {
        ForEach(JapaneseNineKeyLayout.variants(), (group: VariantGroup) => {
          Column() {
            Text(group.title)
              .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
              .fontColor(this.skin.keyForeground)
              .opacity(0.55)
              .width('100%')
              .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(group.kana, (kana: string, index: number) => {
                Text(kana)
                  .fontSize(KeyboardMetrics.CANDIDATE_FONT_SIZE)
                  .fontColor(this.skin.keyForeground)
                  .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                    right: KeyboardMetrics.CANDIDATE_PADDING_VP })
                  .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
                  .onClick(() => {
                    for (const character of group.strokes[index]) {
                      KeyboardSession.shared.press(character.charCodeAt(0), false);
                    }
                    this.variants = false;
                  })
              })
            }
            .width('100%')
          }
          .width('100%')
        })
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 + KeyboardMetrics.ROW_SPACING_VP * 2)
  }

  /**
   * What a long press offers, drawn in the panel rather than as a popup menu.
   *
   * bindContextMenu is the obvious way to write this and does not show inside an input method panel,
   * so these follow the same pattern as the pickers: a strip that takes the space above the keys,
   * which is a surface this window certainly owns.
   */
  @Builder
  overlayStrip(title: string) {
    Row() {
      Text(title)
        .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .opacity(0.55)
        .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP })
      if (this.punctuation) {
        ForEach(QuickPunctuationPolicy.entries(this.english, this.engineScheme, this.localMode),
          (item: PunctuationEntry) => {
            Text(item.face)
              .fontSize(KeyboardMetrics.CANDIDATE_FONT_SIZE)
              .fontColor(this.skin.keyForeground)
              .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                right: KeyboardMetrics.CANDIDATE_PADDING_VP })
              .onClick(() => {
                // The face is what the Engine will print; the key is what it is told.
                KeyboardSession.shared.press(item.input.charCodeAt(0), false);
                this.punctuation = false;
              })
          }, (item: PunctuationEntry) => item.face + this.faceKey())
      } else {
        ForEach(CandidateManagementAction.ACTIONS, (item: ManagementAction) => {
          Text(item.title)
            .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
            .fontColor(this.skin.accent)
            .padding({ left: 10, right: 10 })
            .onClick(() => this.manageCandidate(item, this.managing))
        })
      }
      Blank()
      Text('×')
        .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .padding({ right: KeyboardMetrics.CANDIDATE_PADDING_VP })
        .onClick(() => {
          this.punctuation = false;
          this.managing = -1;
        })
    }
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP)
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
  }

  /** Every candidate at once, which is the alternative to paging past the ninth one by hand. */
  @Builder
  expandedFace() {
    Column() {
      Row() {
        Text(this.editing)
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.accent)
          .maxLines(1)
          .layoutWeight(1)
        Text('收起')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => {
            this.expanded = [];
          })
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Scroll() {
        Column() {
          ForEach(this.expandedRows(), (row: number[]) => {
            Row() {
              ForEach(row, (index: number) => {
                Text(this.expanded[index])
                  .fontSize(KeyboardMetrics.CANDIDATE_FONT_SIZE)
                  .fontColor(this.skin.keyForeground)
                  .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                    right: KeyboardMetrics.CANDIDATE_PADDING_VP })
                  .height(KeyboardMetrics.ROW_HEIGHT_VP)
                  .onClick(() => {
                    KeyboardSession.shared.chooseAny(index);
                    this.expanded = [];
                  })
              }, (index: number) => `${index}:${this.expanded[index]}`)
              Blank()
            }
            .width('100%')
          }, (row: number[]) => row.join(','))
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 + KeyboardMetrics.ROW_SPACING_VP * 2)
  }

  /** The clipboard history: capture, pin, insert, and a clear that asks once before it happens. */
  @Builder
  clipboardFace() {
    Column() {
      Row() {
        Text('剪贴板历史')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .layoutWeight(1)
        Text('保存当前')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .padding({ right: 12 })
          .onClick(() => this.captureClipboard())
        Text(this.confirmingClear ? '确认清空' : '清空')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .padding({ right: 12 })
          .onClick(() => {
            // Clearing takes every pinned entry with it, which is exactly what a pin was meant to
            // prevent, so it is worth one confirmation.
            if (!this.confirmingClear) {
              this.confirmingClear = true;
              this.clipboardNotice = '再次点按将删除全部历史，包括已固定的。';
              return;
            }
            this.updateClips([]);
            this.confirmingClear = false;
            this.clipboardNotice = '';
          })
        Text('返回')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => {
            this.clipboard = false;
          })
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      if (this.clipboardNotice.length > 0) {
        Text(this.clipboardNotice)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .opacity(0.7)
          .maxLines(2)
          .width('100%')
          .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
            right: KeyboardMetrics.CANDIDATE_PADDING_VP })
      }

      Scroll() {
        Column({ space: KeyboardMetrics.KEY_SPACING_VP }) {
          ForEach(this.clips, (entry: ClipboardHistoryItem) => {
            Row() {
              Text(entry.text)
                .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
                .fontColor(this.skin.keyForeground)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .onClick(() => KeyboardSession.shared.insert(entry.text))
              Text(entry.pinned ? '已固定' : '固定')
                .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
                .fontColor(entry.pinned ? this.skin.accent : this.skin.keyForeground)
                .opacity(entry.pinned ? 1 : 0.55)
                .padding({ left: 8, right: 8 })
                .onClick(() => this.updateClips(
                  ClipboardHistoryStore.togglePin(this.clips, entry.text)))
              Text('删除')
                .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
                .fontColor(this.skin.keyForeground)
                .opacity(0.55)
                .onClick(() => this.updateClips(
                  ClipboardHistoryStore.remove(this.clips, entry.text)))
            }
            .width('100%')
            .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
              right: KeyboardMetrics.CANDIDATE_PADDING_VP, top: 6, bottom: 6 })
            .backgroundColor(this.skin.keyBackground)
            .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
          })
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 + KeyboardMetrics.ROW_SPACING_VP * 2)
  }

  /** The emoji grid, with the Unicode categories down the top and the group's entries below. */
  @Builder
  emojiFace() {
    Column() {
      Scroll() {
        Row({ space: this.keySpacing() }) {
          ForEach(EmojiCatalogModel.categories(), (category: EmojiCategory) => {
            Text(category.title)
              .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
              .fontColor(category.group === this.emojiGroup
                ? this.skin.accent : this.skin.keyForeground)
              .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                right: KeyboardMetrics.CANDIDATE_PADDING_VP })
              .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
              .onClick(() => this.loadEmoji(category.group))
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .align(Alignment.Start)

      Grid() {
        ForEach(this.emojiItems, (item: string) => {
          GridItem() {
            Text(item)
              .fontSize(KeyboardMetrics.CANDIDATE_FONT_SIZE + 4)
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .onClick(() => KeyboardSession.shared.insert(item))
        })
      }
      .columnsTemplate('1fr '.repeat(EMOJI_COLUMNS).trim())
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 + KeyboardMetrics.ROW_SPACING_VP * 2)
  }

  @Builder
  nineKeyControl(face: string, action: () => void) {
    Column() {
      Text(face)
        .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(this.skin.borderWidth)
    .borderColor(this.skin.borderColor)
    .onClick(action)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.keyboard()
      if (this.punctuation || this.managing >= 0) {
        Column() {
          this.overlayStrip(this.punctuation ? '常用标点' : '候选词管理')
        }
        .width('100%')
        .padding({
          left: KeyboardMetrics.ROOT_HORIZONTAL_PADDING_VP,
          right: KeyboardMetrics.ROOT_HORIZONTAL_PADDING_VP,
          top: KeyboardMetrics.ROOT_VERTICAL_PADDING_VP + KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP
            + KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP + KeyboardMetrics.ROW_SPACING_VP
        })
      }
    }
    .width('100%')
    .backgroundColor(this.skin.background)
  }

  @Builder
  keyboard() {
    Column({ space: this.rowSpacing() }) {
      this.candidateStrip()

      if (this.expanded.length > 0) {
        this.expandedFace()
      } else if (this.clipboard) {
        this.clipboardFace()
      } else if (this.picker.length > 0) {
        this.pickerFace()
      } else if (this.emoji) {
        this.emojiFace()
      } else if (this.japanese && this.variants && !this.symbols) {
        this.variantFace()
      } else if (this.japanese && !this.symbols) {
        this.japaneseFace()
      } else if (this.nineKey && !this.symbols) {
        this.nineKeyFace()
      } else {
        Row({ space: this.keySpacing() }) {
          ForEach(this.symbols ? SYMBOL_ROWS[0] : LETTER_ROWS[0], (key: string) => {
            this.flexibleKey(this.symbols ? this.symbolKey(key) : this.letterKey(key));
          }, (key: string) => key + this.faceKey())
        }
        .width('100%')
        .height(this.rowHeight(0))

        Row({ space: this.keySpacing() }) {
          ForEach(this.symbols ? SYMBOL_ROWS[1] : LETTER_ROWS[1], (key: string) => {
            this.flexibleKey(this.symbols ? this.symbolKey(key) : this.letterKey(key));
          }, (key: string) => key + this.faceKey())
          if (!this.symbols) {
            // Microsoft shuangpin spells ing with a semicolon, so the key has to be reachable from the
            // letter rows rather than buried behind the symbol layout.
            this.flexibleKey(this.letterKey(';'));
          }
        }
        .width('100%')
        .height(this.rowHeight(1))

        Row({ space: this.keySpacing() }) {
          if (!this.symbols) {
            this.fixedKey({
              face: this.caseMode === LetterCaseMode.CAPS_LOCK ? '⇪' : '⇧',
              size: KeyboardMetrics.KEY_FONT_SIZE,
              emphasized: this.caseMode !== LetterCaseMode.LOWERCASE,
              width: KeyboardMetrics.MODIFIER_WIDTH_VP,
              action: () => {
                this.letterCase.toggle(Date.now());
                this.caseMode = this.letterCase.mode();
              }
            });
          }
          ForEach(this.symbols ? SYMBOL_ROWS[2] : LETTER_ROWS[2], (key: string) => {
            this.flexibleKey(this.symbols ? this.symbolKey(key) : this.letterKey(key));
          }, (key: string) => key + this.faceKey())
          this.deleteKey(KeyboardMetrics.MODIFIER_WIDTH_VP);
        }
        .width('100%')
        .height(this.rowHeight(2))
      }

      Row({ space: this.keySpacing() }) {
        this.fixedKey({
          face: this.symbols ? '返回' : '123',
          size: KeyboardMetrics.SMALL_KEY_FONT_SIZE,
          emphasized: false,
          width: KeyboardMetrics.LAYOUT_TOGGLE_WIDTH_VP,
          action: () => {
            this.symbols = !this.symbols;
          }
        });
        this.fixedKey({
          face: '🌐',
          size: KeyboardMetrics.SMALL_KEY_FONT_SIZE,
          emphasized: false,
          width: KeyboardMetrics.LANGUAGE_WIDTH_VP,
          action: () => {
            try {
              this.switcher.open();
            } catch (error) {
              KeyboardLog.error(`keyboard chooser unavailable: ${describeError(error)}`);
            }
          }
        });
        Column() {
          this.fixedKey({
            face: '，',
            size: KeyboardMetrics.KEY_FONT_SIZE,
            emphasized: false,
            width: KeyboardMetrics.MODIFIER_WIDTH_VP,
            action: () => KeyboardSession.shared.press(0x2c, false)
          });
        }
        .width(KeyboardMetrics.MODIFIER_WIDTH_VP)
        .height('100%')
        .gesture(LongPressGesture().onAction(() => {
          this.managing = -1;
          this.punctuation = true;
        }))
        this.spaceKey();
        this.fixedKey({
          face: '中/英',
          size: KeyboardMetrics.LANGUAGE_FONT_SIZE,
          emphasized: false,
          width: KeyboardMetrics.LANGUAGE_WIDTH_VP,
          action: () => {
            this.english = KeyboardSession.shared.toggleLanguage();
            this.letterCase.reset();
            this.caseMode = this.letterCase.mode();
          }
        });
        this.fixedKey({
          // A composition takes Return before any editor action does: the user is choosing a
          // candidate, not submitting the field. Otherwise the key says what the field asked for,
          // so it reads 搜索 in a search box rather than 换行 in a box that has no lines.
          face: this.japanese
            ? JapaneseNineKeyActions.returnTitle(this.editing.length > 0)
            : (this.candidates.length > 0
              ? '选定' : ReturnKeyAction.title(KeyboardSession.shared.returnAction(), false)),
          size: KeyboardMetrics.SMALL_KEY_FONT_SIZE,
          emphasized: true,
          width: KeyboardMetrics.RETURN_WIDTH_VP,
          action: () => {
            if (this.candidates.length > 0) {
              KeyboardSession.shared.commitHighlighted();
            } else {
              KeyboardSession.shared.submit();
            }
          }
        });
      }
      .width('100%')
      .height(this.rowHeight(3))
    }
    .width('100%')
    .padding({
      left: KeyboardMetrics.ROOT_HORIZONTAL_PADDING_VP,
      right: KeyboardMetrics.ROOT_HORIZONTAL_PADDING_VP,
      top: KeyboardMetrics.ROOT_VERTICAL_PADDING_VP,
      bottom: KeyboardMetrics.ROOT_VERTICAL_PADDING_VP
    })
  }
}
