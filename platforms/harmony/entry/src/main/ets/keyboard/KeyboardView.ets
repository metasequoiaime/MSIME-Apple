import {
  KeyboardSession, KeyboardPreferences, KeyboardState, CandidateEntry, EmojiPage, EmojiRow
} from './KeyboardSession';
import { KeyboardScheme, SchemeDefinition } from './KeyboardScheme';
import { KeyboardSkin } from './skin/KeyboardSkin';
import { EnglishLetterCaseState, LetterCaseMode } from './input/EnglishLetterCaseState';
import { LetterKeyFacePolicy } from './input/LetterKeyFacePolicy';
import { ShuangpinKeyHintPolicy } from './input/ShuangpinKeyHintPolicy';
import { ReturnKeyAction } from './input/ReturnKeyAction';
import { InputDiagnosticPolicy } from './input/InputDiagnosticPolicy';
import { LocalInputMode, LocalInputModeDefinition } from './input/LocalInputMode';
import { CandidateWrapPolicy } from './candidate/CandidateWrapPolicy';
import { KeyboardFeedback, FeedbackSettings, HapticStrength } from './KeyboardFeedback';
import { QuickPunctuationPolicy, PunctuationEntry } from './input/QuickPunctuationPolicy';
import {
  JapaneseNineKeyLayout, JapaneseKey, VariantGroup, DIRECTION_CENTRE
} from './input/JapaneseNineKeyLayout';
import { JapaneseNineKeyActions } from './input/JapaneseNineKeyActions';
import { JapaneseVariantPolicy } from './input/JapaneseVariantPolicy';
import { CandidateManagementAction, ManagementAction } from './candidate/CandidateManagementAction';
import { CandidateSkinPolicy } from './candidate/CandidateSkinPolicy';
import { CandidateWheelPolicy } from './candidate/CandidateWheelPolicy';
import { KeyboardMetrics } from './KeyboardMetrics';
import { KeyboardGeometry } from './KeyboardGeometry';
import { NineKeyLayout, NineKey } from './input/NineKeyLayout';
import { SpaceCursorMovement } from './input/SpaceCursorMovement';
import {
  EmojiCatalogModel, EmojiCategory, EmojiItem, EmojiSymbolGroup, EMOJI_PAGE_SIZE
} from './emoji/EmojiCatalogModel';
import { KeyboardLog, describeError } from './KeyboardLog';
import { KeyboardFormFactor } from './KeyboardFormFactor';
import { DesktopSurface } from './DesktopSurface';
import {
  ClipboardHistoryStore, ClipboardHistoryItem, ClipboardHistoryError
} from './clipboard/ClipboardHistoryStore';
import componentSnapshot from '@ohos.arkui.componentSnapshot';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import {
  HandwritingPoint, HandwritingStroke, HandwritingStrokePolicy,
  HANDWRITING_CANVAS_SIZE, HANDWRITING_MAX_POINTS, HANDWRITING_MAX_STROKES
} from './input/HandwritingStrokePolicy';
import { HarmonyVoiceRecognizer } from './input/HarmonyVoiceRecognizer';
import { VoiceRecognitionPolicy } from './input/VoiceRecognitionPolicy';
import { ReplyKeyboardPolicy, ReplyStyle } from './ReplyKeyboardPolicy';
import { CommunityReplyTemplate } from './CommunityReplyLibraryPolicy';

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
// 22 inside a touch target the row's height gives it, which is the proportion the iOS bar uses.
const SHORTCUT_ICON_VP: number = 22;
const BRAND_PILL_RADIUS_VP: number = 11;
// The surfaces that cover the key rows. Only one is ever showing.
const SURFACE_NONE: string = '';
const SURFACE_SCHEME: string = 'scheme';
const SURFACE_SKIN: string = 'skin';
const SURFACE_EMOJI: string = 'emoji';
const SURFACE_CLIPBOARD: string = 'clipboard';
const SURFACE_TOOLS: string = 'tools';
const SURFACE_MODES: string = 'modes';
const SURFACE_GEOMETRY: string = 'geometry';
const SURFACE_EXPANDED: string = 'expanded';
const SURFACE_VARIANTS: string = 'variants';
const SURFACE_VOICE: string = 'voice';
const SURFACE_REPLY: string = 'reply';

const TOOL_ICON_VP: number = 18;
// Third, which is where iOS puts the English card.
const ENGLISH_CARD_POSITION: number = 2;
// English has no entry in KeyboardScheme to take its name from, being a mode rather than a scheme.
const ENGLISH_TITLES: string[] = ['英文 26 键', '英文 9 键'];
const HANDWRITING_CANVAS_ID: string = 'msime-harmony-handwriting-canvas';
const SCHEME_BADGE_VP: number = 26;
const SCHEME_GLYPH_SIZE: number = 15;
const SCHEME_BADGE_TEXT_SIZE: number = 9;
// Enough tint to mark the card without drowning the glyph sitting on it.
const SELECTED_CARD_ALPHA: number = 0.14;

// The skin preview is a keyboard reduced to its shape: four rows of blank caps, the last one ending
// in the action key, which is the only place a skin's accent shows among its keys.
const PREVIEW_ROWS: number[] = [0, 1, 2, 3];
const PREVIEW_KEY_VP: number = 7;
const PREVIEW_ACTION_WEIGHT: number = 3;

function previewKeys(row: number): number[] {
  if (row === PREVIEW_ROWS.length - 1) {
    return [2, 1, 5, PREVIEW_ACTION_WEIGHT];
  }
  const counts: number[] = [10, 9, 9];
  const cells: number[] = [];
  for (let index: number = 0; index < counts[row]; index++) {
    cells.push(1);
  }
  return cells;
}
// The strip and the nine-key sidebar sit over the keyboard rather than among the keys, so their
// background is translucent. These are the fractions the iOS keyboard uses.
const STRIP_BACKGROUND_ALPHA: number = 0.82;
const SIDEBAR_BACKGROUND_ALPHA: number = 0.5;
// Roughly a third of a key. Shorter than this is a tap on the centre kana, not a flick.
const FLICK_THRESHOLD_VP: number = 16;
// The Engine's own numbering for Japanese, which the ported policies are written against.
const JAPANESE_SCHEME: number = 3;

// A category runs to a few hundred entries; this is the ceiling that keeps a catalog which never
// reports itself complete from spinning here forever.
const EMOJI_MAX_PAGES: number = 16;
const EMOJI_COLUMNS: number = 8;
const EMOJI_PANEL: string = 'emoji';
const KAOMOJI_PANEL: string = 'kaomoji';
const SYMBOLS_PANEL: string = 'symbols';

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
  @State feedback: FeedbackSettings = KeyboardFeedback.DEFAULTS;
  @State traditional: boolean = false;
  @State english: boolean = false;
  /** Which surface the toolbar asked this window to carry, on a machine with no key faces. */
  @State desktop: DesktopSurface = DesktopSurface.NONE;
  @State symbols: boolean = false;
  @State nineKey: boolean = false;
  /** Scheme 3 is Japanese, which has its own grid rather than a pinyin one. */
  @State japanese: boolean = false;
  @State emojiGroup: string = EmojiCatalogModel.categories()[0].group;
  @State emojiItems: string[] = [];
  @State emojiRecents: string[] = [];
  @State emojiShowingRecents: boolean = false;
  @State emojiPanel: string = EMOJI_PANEL;
  @State emojiUnicodeGroup: string = EmojiCatalogModel.categories()[0].group;
  @State emojiKaomojiGroups: string[] = [];
  @State emojiSymbolGroups: EmojiSymbolGroup[] = [];
  @State emojiSymbolParent: string = '';
  /**
   * Which surface is covering the keys, if any.
   *
   * One field rather than a flag per panel. With a flag each, the render chain picked whichever came
   * first and the rest stayed set behind it: opening the skin picker and then tapping emoji set the
   * emoji flag, the chain still matched the picker, and the tap read as doing nothing while the two
   * were open at once. A single value cannot be in two states.
   */
  @State surface: string = SURFACE_NONE;
  @State clipboardEnabled: boolean = KeyboardSession.shared.clipboardHistoryAllowed();
  @State clips: ClipboardHistoryItem[] = [];
  @State clipboardNotice: string = '';
  @State confirmingClear: boolean = false;
  @State expanded: string[] = [];
  @State availableWidth: number = 0;
  @State caseMode: LetterCaseMode = LetterCaseMode.LOWERCASE;
  @State skin: KeyboardSkin = KeyboardSkin.from('forest', false);
  @State candidateSkin: KeyboardSkin = KeyboardSkin.from('forest', false);
  @State scheme: SchemeDefinition = KeyboardScheme.QUANPIN;
  @State handwritingStrokes: HandwritingStroke[] = [];
  @State handwritingRedo: HandwritingStroke[] = [];
  @State handwritingCandidates: string[] = [];
  @State handwritingNotice: string = '';
  @State handwritingBusy: boolean = false;
  @State voiceText: string = '';
  @State voiceNotice: string = '';
  @State voiceBusy: boolean = false;
  @State voiceFinishing: boolean = false;
  @State voiceEnabled: boolean = KeyboardSession.shared.voiceInputEnabled();
  @State replySource: string = '';
  @State replyStyle: string = '高情商';
  @State replyResults: string[] = [];
  @State replyNotice: string = '';
  @State replyBusy: boolean = false;
  @State replyTemplates: CommunityReplyTemplate[] = [];
  @State replyTemplateMenu: boolean = false;
  @State hoveredCandidate: number = -1;

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
  private handwritingCurrent: HandwritingPoint[] = [];
  private handwritingRevision: number = 0;
  private handwritingContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private readonly voiceRecognizer: HarmonyVoiceRecognizer = new HarmonyVoiceRecognizer();
  private voiceGeneration: number = 0;
  private replyGeneration: number = 0;

  aboutToAppear(): void {
    this.english = KeyboardSession.shared.isEnglish();
    this.clipboardEnabled = KeyboardSession.shared.clipboardHistoryAllowed();
    KeyboardSession.shared.onClipboardHistoryChanged = (enabled: boolean): void => {
      this.clipboardEnabled = enabled;
      if (!enabled) {
        this.clips = [];
        this.confirmingClear = false;
        this.clipboardNotice = '剪贴板历史已关闭，历史记录已清空';
        if (this.surface === SURFACE_CLIPBOARD) {
          this.show(SURFACE_NONE);
        }
      }
    };
    this.voiceEnabled = KeyboardSession.shared.voiceInputEnabled();
    KeyboardSession.shared.onVoiceInputChanged = (enabled: boolean): void => {
      this.voiceEnabled = enabled;
      if (!enabled) {
        this.cancelVoice();
        if (this.surface === SURFACE_VOICE) {
          this.show(SURFACE_NONE);
        }
      }
    };
    KeyboardSession.shared.onSurfaceChanged = (surface: DesktopSurface): void => {
      this.desktop = surface;
      if (surface === DesktopSurface.EMOJI && this.emojiItems.length === 0) {
        this.loadEmoji(this.emojiGroup);
      }
    };
    this.settings = KeyboardSession.shared.preferences();
    this.feedback = KeyboardSession.shared.feedback();
    this.traditional = KeyboardSession.shared.usesTraditional();
    this.skin = KeyboardSkin.from(this.settings.skinId, this.settings.dark);
    this.candidateSkin = KeyboardSkin.from(
      CandidateSkinPolicy.harmonySkin(this.settings.candidateSkinId, this.settings.candidateSkinBase),
      this.settings.candidateDark);
    this.scheme = this.settings.thoughtfulReply ? KeyboardScheme.THOUGHTFUL_REPLY
      : this.resolveScheme(this.settings.layout);
    this.nineKey = this.scheme.touchKeyboardLayout === 'nine_key';
    this.japanese = this.scheme.engineScheme === 'japanese' && this.nineKey;
    KeyboardSession.shared.setNineKey(this.nineKey);
    KeyboardSession.shared.onEditorChanged = (): void => {
      // A URI or password field opens in Latin whatever the user last chose, so the face has to
      // follow or it would claim a language the Engine is not composing in.
      this.english = KeyboardSession.shared.isEnglish();
    };
    KeyboardSession.shared.onReplyContextChanged = (): void => {
      this.replyResults = [];
      this.replyBusy = false;
      if (this.surface === SURFACE_REPLY) {
        this.replyNotice = '输入位置已变化，请重新选择回复方式';
      }
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
        this.show(SURFACE_NONE);
      }
    };
  }

  aboutToDisappear(): void {
    KeyboardSession.shared.onChanged = undefined;
    KeyboardSession.shared.onClipboardHistoryChanged = undefined;
    KeyboardSession.shared.onVoiceInputChanged = undefined;
    KeyboardSession.shared.onEditorChanged = undefined;
    this.stopBackspace();
    this.voiceRecognizer.shutdown();
    KeyboardSession.shared.voiceCancel();
    this.voiceGeneration = 0;
    this.voiceBusy = false;
    this.voiceFinishing = false;
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
    this.emojiPanel = EMOJI_PANEL;
    this.emojiUnicodeGroup = group;
    this.loadEmojiCatalog(EMOJI_PANEL, group);
  }

  private loadEmojiCatalog(category: string, group: string, parent: string = ''): void {
    this.emojiGroup = group;
    this.emojiShowingRecents = false;
    const collected: string[] = [];
    let offset: number = 0;
    for (let page: number = 0; page < EMOJI_MAX_PAGES; page++) {
      const result: EmojiPage | null =
        KeyboardSession.shared.emojiCatalogPage(category, group, offset, EMOJI_PAGE_SIZE, parent);
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

  private showEmojiPanel(panel: string): void {
    this.emojiPanel = panel;
    if (panel === EMOJI_PANEL) {
      this.emojiRecents = KeyboardSession.shared.emojiRecents();
      if (this.emojiRecents.length > 0) {
        this.showEmojiRecents();
      } else {
        this.loadEmoji(this.emojiUnicodeGroup);
      }
      return;
    }
    if (panel === KAOMOJI_PANEL) {
      this.emojiKaomojiGroups = KeyboardSession.shared.emojiGroups(KAOMOJI_PANEL);
      const group: string = this.emojiKaomojiGroups[0] ?? '';
      this.loadEmojiCatalog(KAOMOJI_PANEL, group);
      return;
    }
    this.emojiSymbolGroups = KeyboardSession.shared.emojiSymbolGroups();
    this.emojiSymbolParent = this.emojiSymbolGroups[0]?.parent ?? '';
    this.loadEmojiCatalog(SYMBOLS_PANEL, '', this.emojiSymbolParent);
  }

  private showEmojiRecents(): void {
    this.emojiShowingRecents = true;
    this.emojiRecents = KeyboardSession.shared.emojiRecents();
    this.emojiItems = this.emojiRecents.slice();
  }

  private selectEmoji(text: string): void {
    KeyboardSession.shared.insert(text);
    this.emojiRecents = KeyboardSession.shared.recordEmojiRecent(text);
    if (this.emojiShowingRecents) {
      this.emojiItems = this.emojiRecents.slice();
    }
  }

  private clearEmojiRecents(): void {
    if (KeyboardSession.shared.clearEmojiRecents()) {
      this.emojiRecents = [];
      if (this.emojiShowingRecents) {
        this.emojiItems = [];
      }
    }
  }

  private openEmojiSurface(): void {
    this.toggle(SURFACE_EMOJI);
    if (this.surface === SURFACE_EMOJI) {
      this.showEmojiPanel(this.emojiPanel);
    }
  }

  private selectScheme(candidate: SchemeDefinition): void {
    // The composition belongs to the scheme that was current when it was typed; carrying it into a
    // different one would reinterpret letters that were never meant that way.
    KeyboardSession.shared.cancel();
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('scheme', candidate.engineScheme);
    changes.set('touch_keyboard_layout', candidate.touchKeyboardLayout);
    changes.set('touch_keyboard_schemes', { enabled: [
      'quanpin', 'nine_key', 'xiaohe', 'ziranma', 'microsoft', 'shoudao', 'wubi',
      'japanese_nine_key', 'japanese', 'handwriting', 'thoughtful_reply'
    ], selected: candidate.preferenceId });
    if (candidate.shuangpinProfile !== null) {
      changes.set('shuangpin_profile', candidate.shuangpinProfile);
    }
    if (!KeyboardSession.shared.changePreferences(changes)) {
      return;
    }
    KeyboardSession.shared.useScheme(candidate.engineScheme, candidate.shuangpinProfile);
    if (this.english) {
      // Picking a Chinese scheme is a request to compose Chinese with it.
      this.english = KeyboardSession.shared.toggleLanguage();
    }
    this.scheme = candidate;
    this.nineKey = candidate.touchKeyboardLayout === 'nine_key';
    // The kana grid belongs to the scheme, not to what the Engine last reported: the Engine only
    // says so once something has been typed, and the face has to change before that.
    this.japanese = candidate.engineScheme === 'japanese' && candidate.touchKeyboardLayout
      === 'nine_key';
    KeyboardSession.shared.setNineKey(this.nineKey);
    this.show(candidate === KeyboardScheme.THOUGHTFUL_REPLY ? SURFACE_REPLY : SURFACE_NONE);
  }

  /**
   * Switch to English on the grid the card names.
   *
   * The twenty-six key card leaves the scheme alone, because English there is only a text mode over
   * whichever scheme the typist will come back to. The nine-key card cannot: the Engine reads the
   * grid's digits as letters only under quanpin, that being the only scheme whose syllables the grid
   * knows, so picking it moves the scheme underneath as well and says so on the card.
   */
  private selectEnglish(nineKey: boolean): void {
    KeyboardSession.shared.cancel();
    if (nineKey) {
      const changes: Map<string, Object> = new Map<string, Object>();
      changes.set('scheme', KeyboardScheme.QUANPIN_NINE_KEY.engineScheme);
      changes.set('touch_keyboard_layout', KeyboardScheme.QUANPIN_NINE_KEY.touchKeyboardLayout);
      if (!KeyboardSession.shared.changePreferences(changes)) {
        return;
      }
      KeyboardSession.shared.useScheme(KeyboardScheme.QUANPIN_NINE_KEY.engineScheme);
      this.scheme = KeyboardScheme.QUANPIN_NINE_KEY;
      this.japanese = false;
    } else if (this.nineKey) {
      // Leaving the grid for the letters is the same request the 26/九 key makes, and the scheme has
      // to follow the face or the candidate strip goes on naming a layout that is off screen.
      const changes: Map<string, Object> = new Map<string, Object>();
      changes.set('touch_keyboard_layout', KeyboardScheme.QUANPIN.touchKeyboardLayout);
      if (!KeyboardSession.shared.changePreferences(changes)) {
        return;
      }
      this.scheme = this.resolveScheme(KeyboardScheme.QUANPIN.touchKeyboardLayout);
      this.japanese = false;
    }
    this.nineKey = nineKey;
    KeyboardSession.shared.setNineKey(nineKey);
    if (!this.english) {
      this.english = KeyboardSession.shared.toggleLanguage();
      this.letterCase.reset();
      this.caseMode = this.letterCase.mode();
    }
    this.show(SURFACE_NONE);
  }

  private selectSkin(choice: KeyboardSkin): void {
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('touch_keyboard_skin', choice.id);
    if (!KeyboardSession.shared.changePreferences(changes)) {
      return;
    }
    this.skin = choice;
    this.show(SURFACE_NONE);
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
      // A grid is a way of getting twenty-six letters out of nine keys, which is a problem only a
      // touch screen has. On a machine with a physical keyboard every letter already has a key.
      && !(KeyboardFormFactor.isDesktop() && candidate.touchKeyboardLayout === 'nine_key'));
  }

  private schemeAvailable(candidate: SchemeDefinition): boolean {
    return true;
  }

  /** The scheme the keyboard is on, which the nine-key toggle can move without the picker. */
  /**
   * How tall a surface is: everything the key rows and the action row occupy, plus the gaps between
   * them. A surface covers the whole keyboard, the way iOS covers it, rather than sitting above an
   * action row that stays put and clips the surface's last line.
   */
  private surfaceHeight(): number {
    let total: number = this.rowSpacing() * (KeyboardMetrics.KEY_ROWS - 1);
    for (let row: number = 0; row < KeyboardMetrics.KEY_ROWS; row++) {
      total += this.rowHeight(row);
    }
    return total;
  }

  private isPicker(): boolean {
    return this.surface === SURFACE_SCHEME || this.surface === SURFACE_SKIN;
  }

  private isTools(): boolean {
    return this.surface === SURFACE_TOOLS || this.surface === SURFACE_MODES;
  }

  /** Shows one surface, which closes whatever was showing. */
  private show(surface: string): void {
    if (surface !== SURFACE_REPLY) {
      this.replyGeneration += 1;
      this.replyBusy = false;
    }
    this.surface = surface;
    if (surface === SURFACE_REPLY) {
      this.replyTemplates = KeyboardSession.shared.communityReplyTemplates();
      this.replyTemplateMenu = false;
    }
    if (surface !== SURFACE_EXPANDED) {
      this.expanded = [];
    }
  }

  /** Tapping the icon of the surface already open closes it. */
  private toggle(surface: string): void {
    this.show(this.surface === surface ? SURFACE_NONE : surface);
  }

  private isCurrentScheme(candidate: SchemeDefinition): boolean {
    // Not while English is running: the scheme is still set underneath, but what the keyboard is
    // composing is English, and two cards showing as current would say otherwise.
    return !this.english && candidate.preferenceId === this.scheme.preferenceId;
  }

  /**
   * What a grid key says, which for one of them depends on what the digits are spelling.
   *
   * The apostrophe separates one syllable from the next, so its cap reads 分词 while the grid is
   * spelling pinyin. In English it is a letter of the words themselves — don't, it's — and what it
   * sends never changes, only what to call it.
   */
  private nineKeyFaceOf(key: NineKey): string {
    return this.english && key.input === '\'' ? '\'' : key.label;
  }

  /** Which of the two English cards is current is the grid, English itself being common to both. */
  private isCurrentEnglish(nineKey: boolean): boolean {
    return this.english && this.nineKey === nineKey;
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
      action: () => KeyboardSession.shared.punctuation(symbol.charCodeAt(0))
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
   * the scheme says and the user is owed that. English takes it for the same reason: the scheme is
   * still set underneath, but naming it would say the keyboard is spelling syllables when the same
   * keys are spelling words.
   */
  private title(): string {
    const mode: LocalInputModeDefinition | null =
      LocalInputMode.fromPreferenceKey(this.localMode);
    if (mode !== null) {
      return mode.title;
    }
    return this.english ? ENGLISH_TITLES[this.nineKey ? 1 : 0] : this.scheme.title;
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
      widths.push(candidate.length * this.settings.candidateFontSize
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
   * ArkUI accepts a CSS-style family list, so the shared primary family and
   * fallback order can travel through one Text modifier. Keeping this at the
   * view boundary also means malformed legacy entries cannot create an empty
   * family declaration.
   */
  private candidateFontFamily(): string {
    const families: string[] = [this.settings.candidateFontFamily];
    for (const fallback of this.settings.candidateFallbackFonts) {
      if (fallback.length > 0 && !families.includes(fallback)) {
        families.push(fallback);
      }
    }
    return families.join(', ');
  }

  private candidateTextColor(): string {
    return this.settings.candidateTextColor ?? this.candidatePalette().keyForeground;
  }

  private candidateAccentColor(): string {
    return this.settings.candidateAccentColor ?? this.candidatePalette().accent;
  }

  private candidateNumberColor(): string {
    return this.settings.candidateNumberColor ?? this.candidateTextColor();
  }

  private candidateHoverColor(): string {
    return this.settings.candidateHoverColor ?? this.settings.candidateSelectedColor
      ?? '#00000000';
  }

  private candidateBorderColor(): string {
    return this.settings.candidateBorderColor ?? this.candidatePalette().borderColor;
  }

  private candidatePalette(): KeyboardSkin {
    return KeyboardFormFactor.isDesktop() ? this.candidateSkin : this.skin;
  }

  /**
   * The composition gets a line of its own. Sharing the candidate row costs it width on the one row
   * where width is worth most, which is the reasoning the iOS implementation records.
   */
  @Builder
  candidateStrip() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
      // The composition line, reserved whether or not anything is being composed so that nothing
      // below it shifts when one starts. Idle it names the keyboard, the way the iOS strip does;
      // composing it shows the spelling; and a diagnostic takes it over while it lasts.
      Row() {
        // The pill names the keyboard while it sits there idle, which a candidate window never does:
        // it is only ever on screen mid-composition, so the line always has a spelling to show.
        if (this.editing.length === 0 && this.diagnostic.length === 0
            && !KeyboardFormFactor.isDesktop()) {
          Text(this.title())
            .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
            .fontColor(this.skin.accent)
            .maxLines(1)
            .padding({ left: 10, right: 10, top: 2, bottom: 2 })
            .borderWidth(1)
            .borderColor(this.skin.borderColor)
            .borderRadius(BRAND_PILL_RADIUS_VP)
            // The strip names the scheme, so it is also where one changes it.
            .onClick(() => {
              this.toggle(SURFACE_SCHEME);
            })
        } else if (this.diagnostic.length > 0 || !KeyboardFormFactor.isDesktop()
            || this.settings.candidateShowPreedit) {
          Text(this.diagnostic.length > 0 ? this.diagnostic : this.editing)
            .fontSize(this.settings.candidatePreeditFontSize)
            .fontColor(this.candidateAccentColor())
            .fontFamily(this.candidateFontFamily())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Blank()
        }
        Blank()
      }
      .width('100%')
      .height(KeyboardFormFactor.isDesktop() && !this.settings.candidateShowPreedit
        ? 0 : KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      // The shortcut bar stands in for the candidates rather than sitting beside them: one row, two
      // jobs, which is how iOS arranges it and why the composition line above stays reserved. A
      // candidate window has no idle state to fill, and the surfaces those icons open are reached
      // from the app on a machine that has room for it.
      if (this.candidates.length > 0) {
        this.candidateRow()
      } else if (!KeyboardFormFactor.isDesktop()) {
        this.shortcutBar()
      }
    }
      .width('100%')
      .margin({ top: this.settings.candidateDecorationTopVp })
      .backgroundColor(this.settings.candidateSurfaceColor
        ?? this.candidatePalette().translucentKeyBackground(STRIP_BACKGROUND_ALPHA))
      .borderRadius(KeyboardMetrics.STRIP_CORNER_VP)
      .borderWidth(this.settings.candidateBorderColor === null ? 0 : 1)
      .borderColor(this.candidateBorderColor())
      .onAreaChange((_old: Area, now: Area): void => {
        this.availableWidth = Number(now.width);
      })
      if (this.settings.candidateDecorationImage !== null
          && this.settings.candidateDecorationWidthVp > 0) {
        Image(this.settings.candidateDecorationImage)
          .width(this.settings.candidateDecorationWidthVp)
          .height(Math.max(this.settings.candidateDecorationTopVp,
            this.settings.candidateDecorationWidthVp
              / Math.max(0.05, this.settings.candidateDecorationAspectRatio)))
          .objectFit(ImageFit.Contain)
      }
    }
    .width('100%')
  }

  @Builder
  candidateRow() {
    if (KeyboardFormFactor.isDesktop() && this.settings.candidateLayout === 'vertical') {
      Column() {
        ForEach(this.candidates, (candidate: CandidateEntry, index: number) => {
          this.candidateCell(candidate, index)
        }, (candidate: CandidateEntry, index: number) =>
          `${index}:${candidate.text}:${candidate.highlighted}`)
      }
      .width('100%')
      .onAxisEvent((event?: AxisEvent): void => {
        if (!this.settings.navigation.mouseWheel || event === undefined) {
          return;
        }
        const delta: number = event.getVerticalAxisValue();
        if (CandidateWheelPolicy.previousPage(delta)) {
          KeyboardSession.shared.previousPage();
        } else if (CandidateWheelPolicy.nextPage(delta)) {
          KeyboardSession.shared.nextPage();
        }
      })
    } else {
      Row() {
      Scroll() {
        Row() {
          ForEach(this.candidates, (candidate: CandidateEntry, index: number) => {
            this.candidateCell(candidate, index)
          }, (candidate: CandidateEntry, index: number) =>
            `${index}:${candidate.text}:${candidate.highlighted}`)
        }
        .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP)
      .align(Alignment.Start)
      Text('\u2228')
        .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
        .fontColor(this.candidatePalette().accent)
        .padding({ left: 10, right: 12 })
        .onClick(() => {
          this.expanded = KeyboardSession.shared.allCandidates();
        })
      }
      .onAxisEvent((event?: AxisEvent): void => {
        if (!KeyboardFormFactor.isDesktop() || !this.settings.navigation.mouseWheel
            || event === undefined) {
          return;
        }
        const delta: number = event.getVerticalAxisValue();
        if (CandidateWheelPolicy.previousPage(delta)) {
          KeyboardSession.shared.previousPage();
        } else if (CandidateWheelPolicy.nextPage(delta)) {
          KeyboardSession.shared.nextPage();
        }
      })
    }
    .width('100%')
    .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP
      * (KeyboardFormFactor.isDesktop() && this.settings.candidateLayout === 'vertical'
        ? Math.max(1, Math.min(9, this.candidates.length)) : 1))
  }

  @Builder
  candidateCell(candidate: CandidateEntry, index: number) {
    const selected: boolean = candidate.highlighted;
    const detailColor: string = CandidateSkinPolicy.rowDetailColor(selected,
      this.candidateTextColor(), this.candidateAccentColor());
    Row() {
      if (selected && (this.settings.candidateSelectedBar
        ?? CandidateSkinPolicy.showSelectedBar(this.settings.candidateSkinId))) {
        Blank().width(3).height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP * 0.55)
          .backgroundColor(this.candidatePalette().accent).borderRadius(2)
      }
      Text(`${index + 1}`).fontSize(Math.max(KEY_HINT_FONT_SIZE, this.settings.candidateFontSize - 8))
        .fontColor(this.candidateNumberColor()).padding({ right: 4 })
      Text(candidate.text).fontSize(this.settings.candidateFontSize)
        .fontColor(selected || candidate.fixedPosition ? this.candidateAccentColor()
          : this.candidateTextColor())
      if (candidate.badge.length > 0) {
        Text(candidate.badge).fontSize(Math.max(KEY_HINT_FONT_SIZE, this.settings.candidateFontSize - 8))
          .fontColor(this.candidateAccentColor()).opacity(0.8).padding({ left: 2 })
      }
      if (candidate.hint.length > 0) {
        Text(candidate.hint).fontSize(Math.max(KEY_HINT_FONT_SIZE, this.settings.candidateFontSize - 8))
          .fontColor(detailColor).opacity(0.5).padding({ left: 2 })
      }
      if (candidate.annotation.length > 0) {
        Text(candidate.annotation).fontSize(Math.max(KEY_HINT_FONT_SIZE, this.settings.candidateFontSize - 8))
          .fontColor(detailColor).opacity(0.7).padding({ left: 4 })
      }
    }.alignItems(VerticalAlign.Center)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP, right: KeyboardMetrics.CANDIDATE_PADDING_VP })
      .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP).width('100%')
      .backgroundColor(index === this.hoveredCandidate ? this.candidateHoverColor()
        : selected ? (this.settings.candidateSelectedColor ?? '#00000000') : '#00000000')
      .borderWidth(this.settings.candidateBorderColor === null ? 0 : 1)
      .borderColor(this.candidateBorderColor()).onClick(() => KeyboardSession.shared.choose(index))
      .onHover((isHover: boolean): void => { this.hoveredCandidate = isHover ? index : -1; })
      .gesture(LongPressGesture().onAction(() => { this.punctuation = false; this.managing = index; }))
  }

  /**
   * The tools, as icons rather than as text glyphs standing in for them.
   *
   * The brand mark is the entry to everything with no key of its own, which on this host is the
   * clipboard. The rest are the surfaces iOS puts here, in the order it puts them.
   */
  @Builder
  shortcutBar() {
    Row() {
      this.shortcutIcon($r('app.media.keyboard_brand'), this.isTools(), () => {
        this.toggle(SURFACE_TOOLS);
      });
      this.shortcutIcon($r('app.media.tool_emoji'), this.surface === SURFACE_EMOJI, () => {
        this.openEmojiSurface();
      });
      if (this.settings.voiceShortcut && this.voiceEnabled) {
        this.shortcutText('🎙', this.surface === SURFACE_VOICE, () => {
          this.show(SURFACE_VOICE);
          if (!this.voiceBusy && this.voiceText.length === 0) {
            this.startVoice();
          }
        });
      }
      this.shortcutIcon($r('app.media.tool_skin'), this.surface === SURFACE_SKIN, () => {
        this.toggle(SURFACE_SKIN);
      });
      this.shortcutIcon($r('app.media.tool_scheme'), this.surface === SURFACE_SCHEME, () => {
        this.toggle(SURFACE_SCHEME);
      });
      this.shortcutIcon($r('app.media.tool_settings'), this.surface === SURFACE_GEOMETRY, () => {
        this.toggle(SURFACE_GEOMETRY);
      });
      this.shortcutIcon($r('app.media.tool_dismiss'), false, () => {
        KeyboardSession.shared.dismiss();
      });
    }
    .width('100%')
    .height(KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP)
    .justifyContent(FlexAlign.SpaceAround)
  }

  @Builder
  shortcutIcon(source: Resource, active: boolean, action: () => void) {
    Column() {
      Image(source)
        .width(SHORTCUT_ICON_VP)
        .height(SHORTCUT_ICON_VP)
        // Every tool is drawn in the skin's accent, which is what iOS gives the whole bar; only the
        // opacity says which one is open. Tinting an idle icon with the key foreground made the bar
        // read as black-on-green against an interface that is otherwise entirely accent.
        .fillColor(this.skin.accent)
        .opacity(active ? 1 : 0.7)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(action)
  }

  @Builder
  shortcutText(face: string, active: boolean, action: () => void) {
    Column() {
      Text(face)
        .fontSize(SHORTCUT_ICON_VP - 2)
        .fontColor(this.skin.accent)
        .textAlign(TextAlign.Center)
        .opacity(active ? 1 : 0.7)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(action)
  }

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
              Text(this.symbolFace(symbol))
                .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
                .fontColor(this.skin.keyForeground)
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .onClick(() => KeyboardSession.shared.punctuation(symbol.charCodeAt(0)))
          }, (symbol: string) => symbol + this.faceKey())
        }
      }
      .width(`${NINE_KEY_COLUMN_PERCENT}%`)
      .height('100%')
      .backgroundColor(this.skin.translucentKeyBackground(SIDEBAR_BACKGROUND_ALPHA))
      .borderRadius(KeyboardMetrics.KEY_CORNER_VP)

      Column({ space: this.rowSpacing() }) {
        ForEach(NineKeyLayout.rows(), (row: NineKey[]) => {
          Row({ space: this.keySpacing() }) {
            ForEach(row, (key: NineKey) => {
              this.flexibleKey({
                face: this.nineKeyFaceOf(key),
                size: KeyboardMetrics.SMALL_KEY_FONT_SIZE,
                emphasized: false,
                width: 0,
                action: () => KeyboardSession.shared.press(key.input.charCodeAt(0), false)
              });
            }, (key: NineKey) => key.input + this.faceKey())
          }
          .layoutWeight(1)
          .width('100%')
        }, (row: NineKey[]) => row[0].input + this.faceKey())
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
    .height(this.surfaceHeight())
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
    if (!this.clipboardEnabled) {
      this.clipboardNotice = '剪贴板历史已在设置中关闭';
      this.show(SURFACE_NONE);
      return;
    }
    this.show(SURFACE_CLIPBOARD);
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
    if (!this.clipboardEnabled) {
      this.clipboardNotice = '剪贴板历史已在设置中关闭';
      return;
    }
    KeyboardSession.shared.canReadClipboard().then((allowed: boolean): void => {
      if (!allowed) {
        this.clipboardNotice = CLIPBOARD_NOT_PERMITTED;
        return;
      }
      this.storeClipboardText();
    });
  }

  private loadReplySource(): void {
    const generation: number = ++this.replyGeneration;
    KeyboardSession.shared.systemClipboardText().then((text: string): void => {
      if (generation !== this.replyGeneration) return;
      this.replySource = text;
      this.replyResults = [];
      this.replyNotice = text.trim().length === 0 ? '剪贴板里没有文字' : '选择风格生成回复';
    });
  }

  private generateReply(style: string, extraPrompt: string = ''): void {
    if (this.replyBusy) return;
    this.replyStyle = style;
    const generation: number = ++this.replyGeneration;
    this.replyBusy = true;
    this.replyResults = [];
    this.replyNotice = '正在生成…';
    KeyboardSession.shared.thoughtfulReplies(this.replySource, style, extraPrompt).then((results: string[]): void => {
      if (generation !== this.replyGeneration) return;
      this.replyBusy = false;
      this.replyResults = results;
      this.replyNotice = results.length === 0 ? '生成失败，请检查 AI 设置或重试' : '点选回复插入输入框';
    });
  }

  @Builder
  replyFace() {
    Column({ space: this.rowSpacing() }) {
      Row() {
        Text('高情商回复').fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground).layoutWeight(1)
        if (this.replyTemplates.length > 0) {
          Text(this.replyTemplateMenu ? '风格' : '模板').fontColor(this.skin.accent)
            .onClick(() => this.replyTemplateMenu = !this.replyTemplateMenu)
        }
        Text('完成').fontColor(this.skin.accent).onClick(() => this.show(SURFACE_NONE))
      }.width('100%').height(28)
      Row({ space: this.keySpacing() }) {
        Text(this.replySource.length === 0 ? '点击读取剪贴板中的对方文字' : this.replySource)
          .fontSize(14).fontColor(this.skin.keyForeground).maxLines(2).layoutWeight(1)
        Button('粘贴').enabled(!this.replyBusy).onClick(() => this.loadReplySource())
      }.width('100%').padding(8).backgroundColor(this.skin.keyBackground)
      if (this.replyResults.length === 0 && this.replyTemplateMenu) {
        Scroll() {
          Column({ space: this.keySpacing() }) {
            ForEach(this.replyTemplates, (template: CommunityReplyTemplate) => {
              Button(template.name).enabled(!this.replyBusy)
                .onClick(() => {
                  this.replyTemplateMenu = false;
                  this.generateReply('自定义模板', template.prompt);
                })
                .width('100%').height(44).backgroundColor(this.skin.keyBackground)
                .fontColor(this.skin.keyForeground)
            }, (template: CommunityReplyTemplate) => template.id)
          }.width('100%')
        }.layoutWeight(1)
      } else if (this.replyResults.length === 0) {
        Grid() {
          ForEach(ReplyKeyboardPolicy.STYLES, (style: ReplyStyle) => {
            GridItem() {
              Button(style.title).enabled(!this.replyBusy)
                .onClick(() => this.generateReply(style.id))
                .width('100%').height(42).backgroundColor(this.skin.keyBackground)
                .fontColor(this.skin.keyForeground)
            }
          }, (style: ReplyStyle) => style.id)
        }.columnsTemplate('1fr 1fr 1fr').width('100%').layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: this.keySpacing() }) {
            ForEach(this.replyResults, (reply: string) => {
              Button(reply).width('100%').height(48).fontColor(this.skin.keyForeground)
                .backgroundColor(this.skin.keyBackground)
                .onClick(() => {
                  if (KeyboardSession.shared.insertReply(reply)) {
                    this.replyResults = [];
                    this.replyNotice = '已插入，请确认发送';
                  } else {
                    this.replyNotice = '输入位置已变化，请重新生成';
                  }
                })
            }, (reply: string) => reply)
          }.width('100%')
        }.layoutWeight(1)
      }
      Text(this.replyNotice).fontSize(12).fontColor(this.skin.keyForeground).opacity(0.72)
    }.width('100%').height(this.surfaceHeight())
  }

  private storeClipboardText(): void {
    if (!this.clipboardEnabled) {
      this.clipboardNotice = '剪贴板历史已在设置中关闭';
      return;
    }
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
    if (action.available === false) {
      return;
    }
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
        if (action.id.startsWith('FIX_') && action.position !== undefined) {
          KeyboardSession.shared.fixCandidatePosition(index, action.position);
        } else {
          KeyboardSession.shared.removeCandidate(index);
        }
        break;
    }
    this.diagnostic = action.announcement;
    this.clearDiagnosticLater();
  }

  /** All three at once: they are one decision about how the keyboard is laid out. */
  private applyGeometry(keySpacing: number, rowSpacing: number, height: number): void {
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('touch_key_spacing_tenths', KeyboardGeometry.keySpacing(keySpacing));
    changes.set('touch_row_spacing_tenths', KeyboardGeometry.rowSpacing(rowSpacing));
    changes.set('touch_keyboard_height_adjustment', KeyboardGeometry.heightAdjustment(height));
    if (!KeyboardSession.shared.changePreferences(changes)) {
      return;
    }
    this.settings = KeyboardSession.shared.preferences();
  }

  private setFeedback(settings: FeedbackSettings): void {
    if (KeyboardSession.shared.saveFeedback(settings)) {
      this.feedback = settings;
    }
  }

  private toggleTraditional(): void {
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('traditional_chinese_output', !this.traditional);
    if (KeyboardSession.shared.changePreferences(changes)) {
      this.traditional = !this.traditional;
    }
  }

  private updateClips(updated: ClipboardHistoryItem[]): void {
    if (!this.clipboardEnabled) {
      this.clips = [];
      this.clipboardNotice = '剪贴板历史已在设置中关闭';
      this.show(SURFACE_NONE);
      return;
    }
    if (KeyboardSession.shared.saveClipboardHistory(updated)) {
      this.clips = updated;
    }
  }

  private redrawHandwriting(): void {
    const context: CanvasRenderingContext2D = this.handwritingContext;
    context.clearRect(0, 0, HANDWRITING_CANVAS_SIZE, HANDWRITING_CANVAS_SIZE);
    context.strokeStyle = this.skin.keyForeground;
    context.lineWidth = 4;
    context.lineCap = 'round';
    context.lineJoin = 'round';
    for (const stroke of this.handwritingStrokes) {
      if (stroke.points.length === 0) {
        continue;
      }
      context.beginPath();
      context.moveTo(stroke.points[0].x, stroke.points[0].y);
      for (const point of stroke.points.slice(1)) {
        context.lineTo(point.x, point.y);
      }
      context.stroke();
    }
    if (this.handwritingCurrent.length > 0) {
      context.beginPath();
      context.moveTo(this.handwritingCurrent[0].x, this.handwritingCurrent[0].y);
      for (const point of this.handwritingCurrent.slice(1)) {
        context.lineTo(point.x, point.y);
      }
      context.stroke();
    }
  }

  private handwritingPoint(event: TouchEvent): HandwritingPoint {
    const touch = event.touches[0];
    return HandwritingStrokePolicy.point(touch.x, touch.y);
  }

  private handwritingTouch(event: TouchEvent): void {
    if (event.touches.length === 0 || this.handwritingBusy) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.handwritingCurrent = [this.handwritingPoint(event)];
      this.redrawHandwriting();
      return;
    }
    if (event.type === TouchType.Move) {
      if (this.handwritingCurrent.length > 0
        && this.handwritingCurrent.length < HANDWRITING_MAX_POINTS) {
        this.handwritingCurrent.push(this.handwritingPoint(event));
        this.redrawHandwriting();
      }
      return;
    }
    if (event.type === TouchType.Up) {
      if (this.handwritingCurrent.length > 0) {
        this.handwritingCurrent.push(this.handwritingPoint(event));
        if (this.handwritingStrokes.length < HANDWRITING_MAX_STROKES) {
          this.handwritingStrokes = [...this.handwritingStrokes,
            { points: this.handwritingCurrent.slice() }];
          this.handwritingRedo = [];
          this.handwritingNotice = '';
        } else {
          this.handwritingNotice = '笔画过多，请先清除或撤销后再识别';
        }
      }
      this.handwritingCurrent = [];
      this.redrawHandwriting();
      if (HandwritingStrokePolicy.canRecognize(this.handwritingStrokes)) {
        this.recognizeHandwriting();
      }
    }
  }

  private clearHandwriting(): void {
    this.handwritingRevision++;
    this.handwritingStrokes = [];
    this.handwritingRedo = [];
    this.handwritingCandidates = [];
    this.handwritingCurrent = [];
    this.handwritingNotice = '';
    this.redrawHandwriting();
  }

  private undoHandwriting(): void {
    if (this.handwritingStrokes.length === 0 || this.handwritingBusy) {
      return;
    }
    this.handwritingRevision++;
    const removed: HandwritingStroke | undefined =
      this.handwritingStrokes[this.handwritingStrokes.length - 1];
    if (removed === undefined) {
      return;
    }
    this.handwritingStrokes = this.handwritingStrokes.slice(0, -1);
    this.handwritingRedo = [...this.handwritingRedo, removed];
    this.handwritingCandidates = [];
    this.handwritingNotice = '';
    this.redrawHandwriting();
  }

  private redoHandwriting(): void {
    if (this.handwritingRedo.length === 0 || this.handwritingBusy
      || this.handwritingStrokes.length >= HANDWRITING_MAX_STROKES) {
      return;
    }
    this.handwritingRevision++;
    const restored: HandwritingStroke | undefined = this.handwritingRedo[
      this.handwritingRedo.length - 1];
    if (restored === undefined) {
      return;
    }
    this.handwritingRedo = this.handwritingRedo.slice(0, -1);
    this.handwritingStrokes = [...this.handwritingStrokes, restored];
    this.handwritingCandidates = [];
    this.handwritingNotice = '';
    this.redrawHandwriting();
    this.recognizeHandwriting();
  }

  private recognizeHandwriting(): void {
    if (this.handwritingBusy || !HandwritingStrokePolicy.canRecognize(this.handwritingStrokes)) {
      return;
    }
    const revision: number = ++this.handwritingRevision;
    this.handwritingBusy = true;
    this.handwritingNotice = '正在识别…';
    componentSnapshot.get(HANDWRITING_CANVAS_ID, (error: Error, pixelMap: image.PixelMap): void => {
      if (error) {
        this.handwritingBusy = false;
        this.handwritingNotice = '无法读取手写画布';
        return;
      }
      textRecognition.init().then((ready: boolean): Promise<textRecognition.TextRecognitionResult> => {
        if (!ready) {
          throw new Error('text recognition unavailable');
        }
        return textRecognition.recognizeText({ pixelMap: pixelMap });
      }).then((result: textRecognition.TextRecognitionResult): void => {
        if (revision !== this.handwritingRevision) {
          return;
        }
        this.handwritingCandidates = HandwritingStrokePolicy.candidates(result.value);
        this.handwritingNotice = this.handwritingCandidates.length > 0
          ? '' : '没有识别到文字，请重写';
      }).catch((reason: Error): void => {
        if (revision === this.handwritingRevision) {
          KeyboardLog.error(`handwriting recognition unavailable: ${describeError(reason)}`);
          this.handwritingCandidates = [];
          this.handwritingNotice = '手写识别服务不可用';
        }
      }).finally((): void => {
        void textRecognition.release();
        void pixelMap.release();
        if (revision === this.handwritingRevision) {
          this.handwritingBusy = false;
        }
      });
    });
  }

  private chooseHandwriting(candidate: string): void {
    if (this.handwritingBusy || candidate.length === 0) {
      return;
    }
    KeyboardSession.shared.insertWithSource(candidate, 'handwriting');
    this.clearHandwriting();
  }

  private startVoice(): void {
    if (this.voiceBusy) {
      return;
    }
    if (!KeyboardSession.shared.voiceInputEnabled()) {
      this.voiceEnabled = false;
      this.voiceNotice = '语音输入已在设置中关闭';
      return;
    }
    this.voiceGeneration = KeyboardSession.shared.voiceStart();
    if (this.voiceGeneration === 0) {
      this.voiceNotice = '语音会话不可用';
      return;
    }
    this.voiceText = '';
    this.voiceNotice = '正在聆听…';
    this.voiceBusy = true;
    this.voiceFinishing = false;
    const voiceConfiguration = KeyboardSession.shared.voiceInputConfiguration();
    this.voiceRecognizer.start(voiceConfiguration.language || 'zh-CN', voiceConfiguration,
      (text: string, final: boolean): void => {
      if (text.length > 0) {
        this.voiceText = VoiceRecognitionPolicy.result(text);
      }
      if (final && this.voiceGeneration > 0) {
        const accepted: string | null = KeyboardSession.shared.voiceApply(
          this.voiceGeneration, this.voiceText);
        this.voiceGeneration = 0;
        if (accepted !== null) {
          this.voiceText = accepted;
        }
        this.voiceFinishing = false;
        this.voiceBusy = false;
        this.voiceNotice = accepted !== null ? '识别完成，可提交结果。' :
          (this.voiceText.length > 0 ? '已忽略过期的语音结果。' : '没有识别到语音。');
      }
      }, (message: string): void => {
      KeyboardSession.shared.voiceCancel();
      this.voiceGeneration = 0;
      this.voiceBusy = false;
      this.voiceFinishing = false;
      this.voiceNotice = message;
      }).catch((error: Object): void => {
      KeyboardSession.shared.voiceCancel();
      this.voiceGeneration = 0;
      this.voiceBusy = false;
      this.voiceFinishing = false;
      this.voiceNotice = error instanceof Error ? error.message : '语音识别不可用';
    });
  }

  private stopVoice(): void {
    if (!this.voiceBusy || this.voiceFinishing) {
      return;
    }
    this.voiceFinishing = true;
    this.voiceNotice = '正在完成识别…';
    try {
      this.voiceRecognizer.stop();
    } catch (error) {
      this.voiceBusy = false;
      this.voiceFinishing = false;
      this.voiceNotice = '无法结束语音识别';
    }
  }

  private cancelVoice(): void {
    try {
      this.voiceRecognizer.cancel();
    } catch (error) {
      // Cancellation is best effort; the visible state still has to become idle.
    }
    this.voiceBusy = false;
    this.voiceFinishing = false;
    this.voiceText = '';
    this.voiceNotice = '已取消语音识别';
    KeyboardSession.shared.voiceCancel();
    this.voiceGeneration = 0;
  }

  private submitVoice(): void {
    const text: string = VoiceRecognitionPolicy.result(this.voiceText);
    if (text.length === 0 || this.voiceBusy) {
      return;
    }
    KeyboardSession.shared.insertWithSource(text, 'voice');
    this.voiceText = '';
    this.voiceNotice = '已提交';
  }

  private voiceDescription(): string {
    const config = KeyboardSession.shared.voiceInputConfiguration();
    return config.asr_provider === 'doubao' && config.asr_token.trim().length > 0
      ? '使用豆包实时语音识别；原始音频只在本次识别期间发送。'
      : '使用 HarmonyOS 系统语音识别；输入法不会保存原始音频。';
  }

  @Builder
  voiceFace() {
    Column({ space: KeyboardMetrics.KEY_SPACING_VP }) {
      Row() {
        Text('语音输入')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .layoutWeight(1)
        Text('返回')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => this.show(SURFACE_NONE))
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Text(this.voiceNotice.length > 0 ? this.voiceNotice : this.voiceDescription())
        .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .opacity(0.72)
        .maxLines(2)
        .width('100%')
        .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
          right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      TextArea({ text: this.voiceText, placeholder: '识别结果会显示在这里' })
        .width('100%')
        .height(this.surfaceHeight() * 0.35)
        .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
        .fontColor(this.skin.keyForeground)
        .backgroundColor(this.skin.keyBackground)
        .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
        .onChange((value: string): void => {
          this.voiceText = VoiceRecognitionPolicy.result(value);
        })

      Row({ space: KeyboardMetrics.KEY_SPACING_VP }) {
        Text(this.voiceFinishing ? '正在完成…' : this.voiceBusy ? '停止录音' : '开始录音')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.actionForeground)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 10 })
          .backgroundColor(this.skin.actionBackground)
          .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
          .onClick(() => this.voiceBusy ? this.stopVoice() : this.startVoice())
        Text('取消')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(this.skin.keyBackground)
          .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
          .onClick(() => this.cancelVoice())
        Text('提交')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(this.skin.keyBackground)
          .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
          .opacity(this.voiceText.length > 0 && !this.voiceBusy ? 1 : 0.4)
          .onClick(() => this.submitVoice())
      }
      .width('100%')
    }
    .width('100%')
    .height(this.surfaceHeight())
  }

  @Builder
  handwritingFace() {
    Column({ space: KeyboardMetrics.KEY_SPACING_VP }) {
      Row() {
        Text('手写输入')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .layoutWeight(1)
        Text('撤销')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => this.undoHandwriting())
        Text('重做')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .padding({ left: 12 })
          .onClick(() => this.redoHandwriting())
        Text('清除')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .padding({ left: 12 })
          .onClick(() => this.clearHandwriting())
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Canvas(this.handwritingContext)
        .id(HANDWRITING_CANVAS_ID)
        .width('100%')
        .height(this.surfaceHeight() * 0.58)
        .backgroundColor(this.skin.keyBackground)
        .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
        .borderWidth(this.skin.borderWidth)
        .borderColor(this.skin.borderColor)
        .onReady(() => this.redrawHandwriting())
        .onTouch((event: TouchEvent): void => this.handwritingTouch(event))

      if (this.handwritingCandidates.length > 0) {
        Row({ space: KeyboardMetrics.KEY_SPACING_VP }) {
          ForEach(this.handwritingCandidates, (candidate: string) => {
            Text(candidate)
              .fontSize(KeyboardMetrics.KEY_FONT_SIZE)
              .fontColor(this.skin.keyForeground)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor(this.skin.keyBackground)
              .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
              .onClick(() => this.chooseHandwriting(candidate));
          }, (candidate: string): string => candidate)
        }
        .width('100%')
      }
      if (this.handwritingNotice.length > 0) {
        Text(this.handwritingNotice)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .opacity(0.72)
          .maxLines(1)
      }
    }
    .width('100%')
    .height(this.surfaceHeight())
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
        Text(this.surface === SURFACE_SCHEME ? '输入方案' : '选择皮肤')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .layoutWeight(1)
        Text('完成')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => {
            this.show(SURFACE_NONE);
          })
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Scroll() {
        if (this.surface === SURFACE_SCHEME) {
          // Four to a row, each a glyph badge over its name, which is the arrangement iOS uses and
          // the reason SchemeDefinition carries a glyph and a badge at all.
          Grid() {
            ForEach(this.offeredSchemes(), (candidate: SchemeDefinition, index: number) => {
              // English sits third, where iOS puts it, its two grids side by side the way the two
              // quanpin grids are: a platform text mode rather than a second persisted Engine
              // scheme, so neither card has an entry in KeyboardScheme to come from.
              if (index === ENGLISH_CARD_POSITION) {
                GridItem() {
                  this.englishCard(false);
                }
                GridItem() {
                  this.englishCard(true);
                }
              }
              GridItem() {
                this.schemeCard(candidate);
              }
            }, (candidate: SchemeDefinition) =>
              `${candidate.id}:${this.scheme.id}:${this.english}:${this.nineKey}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .width('100%')
        } else {
          // Two to a row, each a miniature of the keyboard in that skin: the colours are the whole
          // choice, so a name beside a swatch says less than showing the thing.
          Grid() {
            ForEach(KeyboardSkin.builtIns(this.settings.dark), (choice: KeyboardSkin) => {
              GridItem() {
                this.skinCard(choice);
              }
            }, (choice: KeyboardSkin) => choice.key() + this.skin.id)
          }
          .columnsTemplate('1fr 1fr')
          .width('100%')
        }
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(this.surfaceHeight())
  }

  /**
   * The English modes, drawn as scheme cards because that is where a typist looks for them.
   *
   * English is a platform text mode rather than a second persisted Engine scheme, so neither card
   * has an entry in KeyboardScheme to come from; what distinguishes them is only the grid the
   * letters arrive on. The Engine spells words from the same digits the grid sends for syllables.
   */
  @Builder
  englishCard(nineKey: boolean) {
    Column() {
      Row() {
        Text('EN')
          .fontSize(SCHEME_GLYPH_SIZE - 1)
          .fontColor(this.isCurrentEnglish(nineKey) ? this.skin.accent : this.skin.keyForeground)
          .textAlign(TextAlign.Center)
          .width(SCHEME_BADGE_VP)
          .height(SCHEME_BADGE_VP)
          .borderWidth(1.4)
          .borderColor(this.isCurrentEnglish(nineKey) ? this.skin.accent : this.skin.keyForeground)
          .borderRadius(5)
        Text(nineKey ? '9' : '26')
          .fontSize(SCHEME_BADGE_TEXT_SIZE)
          .fontColor(this.isCurrentEnglish(nineKey) ? this.skin.accent : this.skin.keyForeground)
          .padding({ left: 1 })
      }
      .alignItems(VerticalAlign.Bottom)
      .height(SCHEME_BADGE_VP)

      Text(ENGLISH_TITLES[nineKey ? 1 : 0])
        .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
        .fontColor(this.isCurrentEnglish(nineKey) ? this.skin.accent : this.skin.keyForeground)
        .maxLines(1)
        .margin({ top: 2 })
    }
    .width('100%')
    .padding(5)
    .backgroundColor(this.isCurrentEnglish(nineKey)
      ? this.skin.tintedAccent(SELECTED_CARD_ALPHA) : Color.Transparent)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .onClick(() => this.selectEnglish(nineKey))
  }

  /** The scheme's glyph in a bordered badge, its badge text tucked into the corner, name beneath. */
  @Builder
  schemeCard(candidate: SchemeDefinition) {
    Column() {
      // Bottom-aligned rather than offset: the badge's baseline sits on the frame's lower edge, to
      // the right of it. Nudging it into place with an offset put it a line lower than the frame and
      // reading as part of the title underneath.
      Row() {
        Text(candidate.glyph)
          .fontSize(SCHEME_GLYPH_SIZE)
          .fontColor(this.isCurrentScheme(candidate) ? this.skin.accent : this.skin.keyForeground)
          .textAlign(TextAlign.Center)
          .width(SCHEME_BADGE_VP)
          .height(SCHEME_BADGE_VP)
          .borderWidth(1.4)
          .borderColor(this.isCurrentScheme(candidate)
            ? this.skin.accent : this.skin.keyForeground)
          .borderRadius(5)
        Text(candidate.badge)
          .fontSize(SCHEME_BADGE_TEXT_SIZE)
          .fontColor(this.isCurrentScheme(candidate) ? this.skin.accent : this.skin.keyForeground)
          .padding({ left: 1 })
      }
      .alignItems(VerticalAlign.Bottom)
      .height(SCHEME_BADGE_VP)

      Text(candidate.title)
        .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
        .fontColor(this.isCurrentScheme(candidate) ? this.skin.accent : this.skin.keyForeground)
        .maxLines(1)
        .margin({ top: 2 })
    }
    .width('100%')
    .padding(5)
    .backgroundColor(this.isCurrentScheme(candidate)
      ? this.skin.tintedAccent(SELECTED_CARD_ALPHA) : Color.Transparent)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .opacity(this.schemeAvailable(candidate) ? 1 : 0.4)
    .onClick(() => this.selectScheme(candidate))
  }

  /** A miniature keyboard in the skin being offered, drawn from the same values the real one uses. */
  @Builder
  skinCard(choice: KeyboardSkin) {
    Column() {
      Row() {
        Text(choice.title)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(choice.keyForeground)
          .layoutWeight(1)
        if (choice.id === this.skin.id) {
          Text('\u2713').fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE).fontColor(choice.accent)
        }
      }
      .width('100%')
      .padding({ left: 6, right: 6, bottom: 3 })

      ForEach(PREVIEW_ROWS, (row: number) => {
        Row({ space: 2 }) {
          ForEach(previewKeys(row), (cell: number) => {
            Row()
              .layoutWeight(cell)
              .height(PREVIEW_KEY_VP)
              .backgroundColor(row === PREVIEW_ROWS.length - 1 && cell === PREVIEW_ACTION_WEIGHT
                ? choice.actionBackground : choice.keyBackground)
              .borderRadius(2)
          }, (cell: number, index: number) => `${row}:${index}`)
        }
        .width('100%')
        .margin({ bottom: 2 })
      }, (row: number) => `${row}:${choice.key()}`)
    }
    .width('100%')
    .padding(6)
    .margin(3)
    .backgroundColor(choice.background)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .borderWidth(choice.id === this.skin.id ? 1.5 : 0)
    .borderColor(choice.accent)
    .onClick(() => this.selectSkin(choice))
  }

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
    .height(this.surfaceHeight())
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
        this.show(SURFACE_VARIANTS);
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
                    this.show(SURFACE_NONE);
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
    .height(this.surfaceHeight())
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
                KeyboardSession.shared.punctuation(item.input.charCodeAt(0));
                this.punctuation = false;
              })
          }, (item: PunctuationEntry) => item.face + this.faceKey())
      } else {
        const fixedPosition: number = this.managing >= 0 && this.managing < this.candidates.length
          ? this.candidates[this.managing].fixedPosition : 0;
        const source: number = this.managing >= 0 && this.managing < this.candidates.length
          ? this.candidates[this.managing].source : 0;
        const text: string = this.managing >= 0 && this.managing < this.candidates.length
          ? this.candidates[this.managing].text : '';
        const actionable: boolean = CandidateManagementAction.candidateActionsAvailable(
          this.engineScheme, source);
        ForEach(CandidateManagementAction.actionsForFixedPosition(fixedPosition, actionable,
          CandidateManagementAction.hasMultipleCodePoints(text)),
          (item: ManagementAction) => {
          Text(item.title)
            .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
            .fontColor(item.available === false ? this.skin.keyForeground :
              item.checked === true ? this.skin.keyForeground : this.skin.accent)
            .opacity(item.available === false ? 0.35 : 1)
            .padding({ left: 10, right: 10 })
            .onClick(() => this.manageCandidate(item, this.managing))
        }, (item: ManagementAction) => `${item.id}:${item.menuItemId}`)
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
            this.show(SURFACE_NONE);
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
                Row() {
                  Text(`${index + 1}`)
                    .fontSize(Math.max(KEY_HINT_FONT_SIZE, this.settings.candidateFontSize - 8))
                    .fontColor(this.candidateNumberColor())
                    .fontFamily(this.candidateFontFamily())
                    .opacity(0.72)
                    .padding({ right: 4 })
                  Text(this.expanded[index])
                  .fontSize(this.settings.candidateFontSize)
                  .fontColor(this.candidateTextColor())
                  .fontFamily(this.candidateFontFamily())
                }
                  .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                    right: KeyboardMetrics.CANDIDATE_PADDING_VP })
                  .height(KeyboardMetrics.ROW_HEIGHT_VP)
                  .onClick(() => {
                    KeyboardSession.shared.chooseAny(index);
                    this.show(SURFACE_NONE);
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
    .height(this.surfaceHeight())
  }

  /**
   * The three measurements that change how the keyboard is laid out.
   *
   * Every bound comes from KeyboardGeometry rather than being written here, so the slider cannot
   * offer a value the store would refuse. Each change is applied and saved as it is made — there is
   * no confirm step, because the keyboard redraws underneath and shows the result.
   */
  @Builder
  geometryFace() {
    Column() {
      Row() {
        Text('键盘设置')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .layoutWeight(1)
        Text('恢复默认')
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.accent)
          .padding({ right: 12 })
          .onClick(() => this.applyGeometry(KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS,
            KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS,
            KeyboardGeometry.DEFAULT_HEIGHT_ADJUSTMENT_VP))
        Text('完成')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => {
            this.show(SURFACE_NONE);
          })
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Scroll() {
        Column() {
          this.geometrySlider('按键间距',
            KeyboardGeometry.display(this.settings.keySpacingTenths),
            this.settings.keySpacingTenths,
            KeyboardGeometry.MIN_KEY_SPACING_TENTHS, KeyboardGeometry.MAX_KEY_SPACING_TENTHS, 1,
            (value: number) => this.applyGeometry(value, this.settings.rowSpacingTenths,
              this.settings.heightAdjustment));
          this.geometrySlider('行间距',
            KeyboardGeometry.display(this.settings.rowSpacingTenths),
            this.settings.rowSpacingTenths,
            KeyboardGeometry.MIN_ROW_SPACING_TENTHS, KeyboardGeometry.MAX_ROW_SPACING_TENTHS, 1,
            (value: number) => this.applyGeometry(this.settings.keySpacingTenths, value,
              this.settings.heightAdjustment));
          this.geometrySlider('键盘高度',
            KeyboardGeometry.displayHeight(this.settings.heightAdjustment),
            this.settings.heightAdjustment,
            KeyboardGeometry.MIN_HEIGHT_ADJUSTMENT_VP, KeyboardGeometry.MAX_HEIGHT_ADJUSTMENT_VP, 1,
            (value: number) => this.applyGeometry(this.settings.keySpacingTenths,
              this.settings.rowSpacingTenths, value));
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(this.surfaceHeight())
  }

  @Builder
  geometrySlider(title: string, reading: string, value: number, min: number, max: number,
                 step: number, change: (value: number) => void) {
    Column() {
      Row() {
        Text(title)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .layoutWeight(1)
        Text(reading)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .opacity(0.6)
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.OutSet })
        .width('100%')
        .selectedColor(this.skin.accent)
        .trackColor(this.skin.tintedAccent(0.2))
        .blockColor(this.skin.keyBackground)
        .onChange((now: number, mode: SliderChangeMode) => {
          // Written whenever the rounded value actually moves, rather than on a particular change
          // mode. A drag sends many events at the same rounded value, so this is quiet without
          // depending on which mode the platform reports the finger lifting with.
          const wanted: number = Math.round(now);
          if (wanted !== value) {
            change(wanted);
          }
        })
    }
    .width('100%')
    .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
      right: KeyboardMetrics.CANDIDATE_PADDING_VP, top: 4, bottom: 4 })
  }

  /**
   * The tools, two to a row.
   *
   * 表情 and 剪贴板历史 open something; 本地输入 goes one level in rather than putting eight modes on
   * the keyboard's own rows, which is the arrangement iOS settled on. AI 润色 is not offered because
   * this host has no AI surface, and a card that does nothing is worse than one that is absent.
   */
  @Builder
  toolsFace() {
    Column() {
      Row() {
        Text(this.surface === SURFACE_MODES ? '\u2039 返回' : '工具')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => {
            this.show(this.surface === SURFACE_MODES ? SURFACE_TOOLS : SURFACE_NONE);
          })
        Blank()
        Text('完成')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.accent)
          .onClick(() => {
            this.show(SURFACE_NONE);
          })
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)
      .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
        right: KeyboardMetrics.CANDIDATE_PADDING_VP })

      Scroll() {
        Column() {
          if (this.surface === SURFACE_MODES) {
            Grid() {
              ForEach(LocalInputMode.MODES, (mode: LocalInputModeDefinition) => {
                GridItem() {
                  this.toolCard(mode.title, mode.trigger, null, false, true, () => {
                    // The trigger is a capital the Engine reads as the way into that mode.
                    KeyboardSession.shared.press(mode.trigger.charCodeAt(0), true);
                    this.show(SURFACE_NONE);
                  });
                }
              }, (mode: LocalInputModeDefinition) => mode.id)
            }
            .columnsTemplate('1fr 1fr')
            .width('100%')
          } else {
            Grid() {
              GridItem() {
                this.toolCard('表情', null, $r('app.media.tool_emoji'), false, true, () => {
                  this.show(SURFACE_NONE);
                  this.openEmojiSurface();
                });
              }
              if (this.clipboardEnabled) {
                GridItem() {
                  this.toolCard('剪贴板历史', null, $r('app.media.tool_clipboard'), false, true, () => {
                    this.show(SURFACE_NONE);
                    this.openClipboard();
                  });
                }
              }
              GridItem() {
                this.toolCard('本地输入', '123', null, false, true, () => {
                  this.show(SURFACE_MODES);
                });
              }
              GridItem() {
                this.toolCard('语音输入', '🎙', null, this.voiceBusy, this.voiceEnabled, () => {
                  if (!this.voiceEnabled) {
                    return;
                  }
                  this.show(SURFACE_VOICE);
                });
              }
            }
            .columnsTemplate('1fr 1fr')
            .width('100%')

            Text('设置')
              .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
              .fontColor(this.skin.keyForeground)
              .opacity(0.55)
              .width('100%')
              .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP, top: 4, bottom: 2 })

            Grid() {
              GridItem() {
                this.toolCard('繁体输出', null, $r('app.media.tool_traditional'),
                  this.traditional, !this.japanese, () => this.toggleTraditional());
              }
              GridItem() {
                this.toolCard('按键音', null, $r('app.media.tool_sound'),
                  this.feedback.sound, true, () => this.setFeedback({
                    sound: !this.feedback.sound, haptics: this.feedback.haptics,
                    strength: this.feedback.strength
                  }));
              }
              GridItem() {
                this.toolCard('按键振动', null, $r('app.media.tool_vibration'),
                  this.feedback.haptics, true, () => this.setFeedback({
                    sound: this.feedback.sound, haptics: !this.feedback.haptics,
                    strength: this.feedback.strength
                  }));
              }
              GridItem() {
                // One card that shows the level and cycles it: three side by side would push the
                // panel past the keyboard's height, which is the reason iOS does it this way too.
                this.toolCard('振动强度', KeyboardFeedback.title(this.feedback.strength), null,
                  false, this.feedback.haptics, () => this.setFeedback({
                    sound: this.feedback.sound, haptics: this.feedback.haptics,
                    strength: KeyboardFeedback.nextStrength(this.feedback.strength)
                  }));
              }
            }
            .columnsTemplate('1fr 1fr')
            .width('100%')
          }
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(this.surfaceHeight())
  }

  /** One card: an icon or a short label, a title, and a state line for the ones that toggle. */
  @Builder
  toolCard(title: string, label: string | null, icon: Resource | null, on: boolean,
           enabled: boolean, action: () => void) {
    Row() {
      if (icon !== null) {
        Image(icon)
          .width(TOOL_ICON_VP)
          .height(TOOL_ICON_VP)
          .fillColor(this.skin.keyForeground)
          .margin({ right: 8 })
      } else if (label !== null) {
        Text(label)
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .margin({ right: 8 })
      }
      Column() {
        Text(title)
          .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
          .width('100%')
        if (icon !== null && (title === '繁体输出' || title === '按键音' || title === '按键振动')) {
          Text(on ? '已开启' : '已关闭')
            .fontSize(KEY_HINT_FONT_SIZE)
            .fontColor(this.skin.keyForeground)
            .opacity(0.55)
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .margin(3)
    .backgroundColor(on ? this.skin.tintedAccent(SELECTED_CARD_ALPHA) : this.skin.keyBackground)
    .borderRadius(KeyboardMetrics.KEY_CORNER_VP)
    .opacity(enabled ? 1 : 0.4)
    .onClick(() => {
      if (enabled) {
        action();
      }
    })
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
            this.show(SURFACE_NONE);
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
    .height(this.surfaceHeight())
  }

  /** The emoji grid, with the Unicode categories down the top and the group's entries below. */
  @Builder
  emojiFace() {
    Column() {
      // Back, title, delete: the panel covers the keys, so the delete key has to come with it or
      // there is no way to take back a tap without leaving.
      Row() {
        Text('\u2039')
          .fontSize(KeyboardMetrics.KEY_FONT_SIZE)
          .fontColor(this.skin.accent)
          .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP, right: 10 })
          .onClick(() => {
            this.show(SURFACE_NONE);
          })
        Blank()
        Text('表情')
          .fontSize(KeyboardMetrics.SMALL_KEY_FONT_SIZE)
          .fontColor(this.skin.keyForeground)
        if (this.emojiShowingRecents && this.emojiRecents.length > 0) {
          Text('清除最近')
            .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
            .fontColor(this.skin.accent)
            .padding({ left: 8, right: 8 })
            .onClick(() => this.clearEmojiRecents())
        }
        Blank()
        Column() {
          this.deleteKey(KeyboardMetrics.MODIFIER_WIDTH_VP)
        }
        .width(KeyboardMetrics.MODIFIER_WIDTH_VP)
        .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
        .padding({ right: KeyboardMetrics.CANDIDATE_PADDING_VP })
      }
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 4)

      Scroll() {
        Row({ space: KeyboardMetrics.KEY_SPACING_VP }) {
          ForEach([
            { id: EMOJI_PANEL, title: '表情' },
            { id: KAOMOJI_PANEL, title: '颜文字' },
            { id: SYMBOLS_PANEL, title: '符号' }
          ], (panel: { id: string; title: string }) => {
            Text(panel.title)
              .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
              .fontColor(this.emojiPanel === panel.id
                ? this.skin.accent : this.skin.keyForeground)
              .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                right: KeyboardMetrics.CANDIDATE_PADDING_VP })
              .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
              .onClick(() => this.showEmojiPanel(panel.id))
          }, (panel: { id: string; title: string }) => panel.id)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
      .align(Alignment.Start)

      Scroll() {
        Row({ space: KeyboardMetrics.KEY_SPACING_VP }) {
          if (this.emojiPanel === EMOJI_PANEL && this.emojiRecents.length > 0) {
            Text('最近')
              .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
              .fontColor(this.emojiShowingRecents ? this.skin.accent : this.skin.keyForeground)
              .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                right: KeyboardMetrics.CANDIDATE_PADDING_VP })
              .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
              .onClick(() => this.showEmojiRecents())
          }
          if (this.emojiPanel === EMOJI_PANEL) {
            ForEach(EmojiCatalogModel.categories(), (category: EmojiCategory) => {
              Text(category.title)
                .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
                .fontColor(!this.emojiShowingRecents && category.group === this.emojiGroup
                  ? this.skin.accent : this.skin.keyForeground)
                .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                  right: KeyboardMetrics.CANDIDATE_PADDING_VP })
                .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
                .onClick(() => this.loadEmoji(category.group))
            }, (category: EmojiCategory) => `${category.group}:${this.emojiGroup}:${this.emojiShowingRecents}`)
          } else if (this.emojiPanel === KAOMOJI_PANEL) {
            ForEach(this.emojiKaomojiGroups, (group: string) => {
              Text(group)
                .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
                .fontColor(group === this.emojiGroup
                  ? this.skin.accent : this.skin.keyForeground)
                .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                  right: KeyboardMetrics.CANDIDATE_PADDING_VP })
                .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
                .onClick(() => this.loadEmojiCatalog(KAOMOJI_PANEL, group))
            }, (group: string) => `${group}:${this.emojiGroup}`)
          } else {
            ForEach(this.emojiSymbolGroups, (group: EmojiSymbolGroup) => {
              Text(group.title)
                .fontSize(KeyboardMetrics.LANGUAGE_FONT_SIZE)
                .fontColor(group.parent === this.emojiSymbolParent
                  ? this.skin.accent : this.skin.keyForeground)
                .padding({ left: KeyboardMetrics.CANDIDATE_PADDING_VP,
                  right: KeyboardMetrics.CANDIDATE_PADDING_VP })
                .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
                .onClick(() => {
                  this.emojiSymbolParent = group.parent;
                  this.loadEmojiCatalog(SYMBOLS_PANEL, '', group.parent);
                })
            }, (group: EmojiSymbolGroup) => `${group.parent}:${this.emojiSymbolParent}`)
          }
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(KeyboardMetrics.ROW_HEIGHT_VP * 3 / 5)
      .align(Alignment.Start)

      Grid() {
        ForEach(this.emojiItems, (item: string) => {
          GridItem() {
            Text(item)
              .fontSize(KeyboardMetrics.CANDIDATE_FONT_SIZE + 4)
              .textAlign(TextAlign.Center)
              .width('100%')
              .onClick(() => this.selectEmoji(item))
          }
        }, (item: string, index: number) => `${index}:${item}`)
      }
      .columnsTemplate('1fr '.repeat(EMOJI_COLUMNS).trim())
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height(this.surfaceHeight())
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

      // Where the machine has its own keys the strip is the whole panel, unless the toolbar asked
      // for one of the surfaces a phone would have reached from a key face. Drawing a second set of
      // keys under a physical keyboard uninvited would only take the screen away from what is being
      // written; drawing them when they were asked for is the whole point of the button.
      if (!KeyboardFormFactor.isDesktop()) {
        this.keyFaces()
      } else if (this.desktop === DesktopSurface.EMOJI) {
        this.emojiFace()
      } else if (this.desktop === DesktopSurface.SCREEN_KEYBOARD) {
        this.keyFaces()
      } else if (this.desktop === DesktopSurface.VOICE) {
        this.voiceFace()
      }
    }
    .width('100%')
    .padding({
      left: KeyboardMetrics.ROOT_HORIZONTAL_PADDING_VP,
      right: KeyboardMetrics.ROOT_HORIZONTAL_PADDING_VP,
      top: KeyboardMetrics.ROOT_VERTICAL_PADDING_VP,
      bottom: KeyboardMetrics.ROOT_VERTICAL_PADDING_VP
    })
  }

  /**
   * Everything below the strip: whichever surface is open, or the keys themselves.
   *
   * Separate from keyboard() because it is drawn only where the machine has no keys of its own.
   */
  @Builder
  keyFaces() {
      if (this.surface === SURFACE_GEOMETRY) {
        this.geometryFace()
      } else if (this.isTools()) {
        this.toolsFace()
      } else if (this.surface === SURFACE_EXPANDED) {
        this.expandedFace()
      } else if (this.surface === SURFACE_CLIPBOARD) {
        this.clipboardFace()
      } else if (this.surface === SURFACE_REPLY) {
        this.replyFace()
      } else if (this.surface === SURFACE_VOICE) {
        this.voiceFace()
      } else if (this.isPicker()) {
        this.pickerFace()
      } else if (this.surface === SURFACE_EMOJI) {
        this.emojiFace()
      } else if (this.japanese && this.surface === SURFACE_VARIANTS && !this.symbols) {
        this.variantFace()
      } else if (this.japanese && !this.symbols) {
        this.japaneseFace()
      } else if (this.scheme.touchKeyboardLayout === 'handwriting') {
        this.handwritingFace()
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
          Column() {
            this.fixedKey({
              face: '，',
              size: KeyboardMetrics.KEY_FONT_SIZE,
              emphasized: false,
              width: KeyboardMetrics.MODIFIER_WIDTH_VP,
              action: () => KeyboardSession.shared.punctuation(0x2c)
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
            // The face is the mode it is in, not the pair it toggles between: a key labelled 中/英
            // says nothing about which one is running.
            face: this.english ? 'En' : '中',
            size: KeyboardMetrics.SMALL_KEY_FONT_SIZE,
            emphasized: true,
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
  }
}
