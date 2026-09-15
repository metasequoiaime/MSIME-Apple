import inputMethodEngine from '@ohos.inputMethodEngine';
import client from 'libmsimeclient.so';
import { KeyboardLog, describeError } from './KeyboardLog';
import { KeyboardSkin } from './KeyboardSkin';
import { EditorPolicy, EditorTraits } from './EditorPolicy';
import { WubiCodeHintPolicy } from './WubiCodeHintPolicy';
import { KeyboardGeometry } from './KeyboardGeometry';
import { FullWidthInputPolicy } from './FullWidthInputPolicy';
import { ChineseHelpcodePolicy } from './ChineseHelpcodePolicy';
import { ChineseOutputPolicy } from './ChineseOutputPolicy';
import i18n from '@ohos.i18n';
import { InputDiagnosticPolicy } from './InputDiagnosticPolicy';
import { CandidateGlossPolicy, GlossToken } from './CandidateGlossPolicy';
import fs from '@ohos.file.fs';
import pasteboard from '@ohos.pasteboard';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import {
  ClipboardHistoryStore, ClipboardHistoryItem, ClipboardHistoryError, ClipboardFailure,
  MAX_FILE_BYTES
} from './ClipboardHistoryStore';

// Shapes of the JSON the shared C ABI answers with. Only the fields this minimal surface reads are
// declared; the responses carry considerably more.
interface GlossRequestCandidate {
  text: string;
  source: number;
}

interface GlossRequest {
  generation: number;
  user_data: string;
  candidates: GlossRequestCandidate[];
}

interface GlossResponse {
  ok: boolean;
  value: string[];
  error: string;
}

interface Candidate {
  text: string;
  highlighted: boolean;
  /** Which part of the Engine produced it; the gloss lookup treats sources differently. */
  source: number;
  /** The Engine input code that produced this candidate, used for scheme-specific hints. */
  code: string;
  /** An Engine-derived display suffix, never part of what gets committed. */
  annotation: string;
}

/** A candidate as the view draws it: the text, and whatever is printed beside it. */
export interface CandidateEntry {
  readonly text: string;
  readonly hint: string;
  readonly annotation: string;
}

interface EngineView {
  candidates: Candidate[];
  editing_text: string;
  generation: number;
  /** Which spellings the digits typed so far could be, offered while the nine-key grid is up. */
  nine_key_spellings: string[];
  /** 'halfwidth' or 'fullwidth'; what the Engine is committing its own output as. */
  character_width: string;
  /** What has been typed so far, which is the prefix a Wubi code hint is measured against. */
  preedit: string;
  /** True when the answer came from pinyin rather than the scheme's own code. */
  answered_by_pinyin_fallback: boolean;
  /** The Engine's own numbering, which the ported display policies are written against. */
  scheme: number;
  shuangpin_profile: string;
  /** 'none' unless a local utility mode is consuming the keys. */
  local_mode: string;
  dedicated_english: boolean;
}

// The stored preferences, read and written whole. Only the fields the keyboard changes are named;
// the rest travel through untouched as a parsed value, because rewriting a document one does not
// fully understand is how settings get silently dropped.
interface PreferencesSnapshot {
  format_version: number;
  revision: number;
  preferences: Record<string, Object>;
}

interface SnapshotResponse {
  ok: boolean;
  value: PreferencesSnapshot;
  error: string;
}

// The local emoji catalog lives in others.db beside the dictionaries, so the query carries the
// resource directory rather than going through a session.
interface EmojiQuery {
  category: string;
  limit: number;
  offset: number;
  group: string;
  cursor: boolean;
  list_groups: boolean;
}

export interface EmojiRow {
  text: string;
  annotation: string;
  group: string;
}

export interface EmojiPage {
  items: EmojiRow[];
  next_offset: number;
  complete: boolean;
}

interface EmojiResponse {
  ok: boolean;
  value: EmojiPage;
  error: string;
}

interface CandidateSnapshot {
  generation: number;
  candidates: Candidate[];
}

interface SnapshotCandidates {
  ok: boolean;
  value: CandidateSnapshot;
  error: string;
}

/** What the view draws. Grouped so a new field does not change every signature on the way there. */
export interface KeyboardState {
  readonly candidates: CandidateEntry[];
  readonly editing: string;
  readonly spellings: string[];
  readonly scheme: number;
  readonly shuangpinProfile: string;
  readonly localMode: string;
  readonly english: boolean;
  readonly diagnostic: string;
}

interface EngineValue {
  // The Rust side sends Option<String>, but an absent commit reaches ArkTS as undefined rather than
  // the null the JSON names, so both have to be spelled out here. Treating one and not the other
  // threw on every focus, which tore the session down before a single key could be pressed.
  commit: string | null | undefined;
  /** Something the Engine wants the user told, such as a dictionary that could not be opened. */
  diagnostic: string | null | undefined;
  view: EngineView;
}

interface CreateValue {
  session: number;
}

interface Response {
  ok: boolean;
  value: EngineValue;
  error: string;
}

// Not every entry point answers with a transition. setEnglishMode and its siblings return the view on
// its own, with no commit to apply and no wrapper around it, so they are read through their own shape
// rather than pushed through the transition one where the missing fields would throw.
interface ViewResponse {
  ok: boolean;
  value: EngineView;
  error: string;
}

interface CreateResponse {
  ok: boolean;
  value: CreateValue;
  error: string;
}

// ArkTS rejects untyped object literals, so the request prepareHost takes gets a shape too.
interface PrepareRequest {
  resources: string;
  state_root: string;
}

// Only the fields the keyboard acts on are declared. The rest of the document is forwarded to create
// untouched, so naming it here would only invite the two shapes to drift apart.
interface PreparedPreferences {
  default_ime_mode: string;
  scheme: string;
  shuangpin_profile: string;
  touch_keyboard_layout: string;
  touch_keyboard_skin: string;
  // 'follow', 'dark' or 'light' for the keyboard specifically; theme is the global one it falls
  // back to, and only if both defer does the system decide.
  screen_keyboard_theme: string;
  theme: string;
  traditional_chinese_output: boolean;
  candidate_english_gloss: boolean;
  /** Tenths of a vp, which is the unit the shared settings store these in. */
  touch_key_spacing_tenths: number;
  touch_row_spacing_tenths: number;
  /** Added to the total height of the key rows, between -12 and 48 vp. */
  touch_keyboard_height_adjustment: number;
}

/** What the view needs to draw itself, resolved once from the prepared preferences. */
export interface KeyboardPreferences {
  readonly dark: boolean;
  readonly skinId: string;
  readonly keyboardTheme: string;
  readonly globalTheme: string;
  readonly scheme: string;
  readonly shuangpinProfile: string;
  readonly layout: string;
  readonly keySpacingTenths: number;
  readonly rowSpacingTenths: number;
  readonly heightAdjustment: number;
}

interface PreparedOptions {
  preferences: PreparedPreferences;
}

interface PrepareResponse {
  ok: boolean;
  value: PreparedOptions;
  error: string;
}

/**
 * The shared command table from msime_client_command. Spelling the numbers out here keeps the call
 * sites readable and keeps the table in one place instead of scattered behind comments.
 */
enum InputCommand {
  BACKSPACE = 0,
  SELECT_HIGHLIGHTED = 1,
  COMMIT_RAW = 2,
  CANCEL = 3,
  MOVE_LEFT = 4,
  MOVE_RIGHT = 5,
  NEXT_PAGE = 100,
  PREVIOUS_PAGE = 101
}

/**
 * Owns the native session for the lifetime of the extension ability and turns key presses into
 * committed text. The ability creates it; the panel's UI reads state back through onChanged.
 *
 * Deliberately thin: the Engine decides what a key means, this only forwards and applies the result.
 */
export class KeyboardSession {
  static readonly shared: KeyboardSession = new KeyboardSession();

  private handle: number = 0;
  private inputClient: inputMethodEngine.InputClient | undefined = undefined;
  private generation: number = 0;
  // The Engine opens a session in whichever mode the preferences name, and the shared default is
  // English. Remembered here so every focus reasserts it rather than inheriting the previous editor.
  private englishMode: boolean = false;
  // The grid is the Engine's business too: it decides what a 2 means, and it only reads them as
  // nine-key spellings once it has been told the grid is up.
  private nineKeyMode: boolean = false;
  private schemeName: string = 'quanpin';
  private resourceDirectory: string = '';
  private stateDirectory: string = '';
  // What the editor wants its return key to do. Sending this rather than a newline is what makes the
  // key search in a search field and send in a message field, which is the whole point of having it.
  private enterKey: number = inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
  private traits: EditorTraits = {
    text: true, password: false, uri: false, email: false, noSuggestions: false
  };
  private appearance: KeyboardPreferences = {
    dark: false,
    skinId: 'forest',
    keyboardTheme: 'follow',
    globalTheme: 'system',
    scheme: 'quanpin',
    shuangpinProfile: 'xiaohe',
    layout: 'twenty_six_key',
    keySpacingTenths: KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS,
    rowSpacingTenths: KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS,
    heightAdjustment: KeyboardGeometry.DEFAULT_HEIGHT_ADJUSTMENT_VP
  };

  onChanged: ((state: KeyboardState) => void) | undefined = undefined;
  /** The editor's traits arrive after inputStart, so the view is told when they do. */
  onEditorChanged: (() => void) | undefined = undefined;

  /**
   * True once the native ABI matches and a session exists.
   *
   * The options are not written here. prepareHost verifies the staged dictionary against the pinned
   * lock, lays out the derived state under the state root, and returns the document create expects;
   * a hand-written one would drift from the lock the moment the dictionary is republished.
   */
  start(resources: string, stateRoot: string, systemDark: boolean): boolean {
    let abi: number;
    try {
      abi = client.abiVersion();
    } catch (error) {
      KeyboardLog.error(`native module unavailable: ${describeError(error)}`);
      return false;
    }
    if (abi !== 2) {
      KeyboardLog.error(`native ABI is ${abi}, expected 2`);
      return false;
    }
    this.resourceDirectory = resources;
    this.stateDirectory = stateRoot;
    const request: PrepareRequest = { resources: resources, state_root: stateRoot };
    let options: string;
    try {
      const prepared: PrepareResponse =
        JSON.parse(client.prepareHost(JSON.stringify(request))) as PrepareResponse;
      if (!prepared.ok) {
        KeyboardLog.error(`host preparation refused: ${prepared.error}`);
        return false;
      }
      options = JSON.stringify(prepared.value);
      const preferences: PreparedPreferences = prepared.value.preferences;
      this.englishMode = preferences.default_ime_mode === 'english';
      this.appearance = {
        // The keyboard's own theme wins, then the global one, and only if both defer does the
        // system decide. resolveDark is the ported rule every other host already follows.
        dark: KeyboardSkin.resolveDark(preferences.screen_keyboard_theme, preferences.theme,
          systemDark),
        skinId: preferences.touch_keyboard_skin,
        keyboardTheme: preferences.screen_keyboard_theme,
        globalTheme: preferences.theme,
        scheme: preferences.scheme,
        shuangpinProfile: preferences.shuangpin_profile,
        layout: preferences.touch_keyboard_layout,
        // Clamped rather than trusted: the store validates, but an older document or a host that
        // never learned the bounds would otherwise draw a keyboard nobody can hit.
        keySpacingTenths: KeyboardGeometry.keySpacing(preferences.touch_key_spacing_tenths),
        rowSpacingTenths: KeyboardGeometry.rowSpacing(preferences.touch_row_spacing_tenths),
        heightAdjustment:
          KeyboardGeometry.heightAdjustment(preferences.touch_keyboard_height_adjustment)
      };
      this.schemeName = preferences.scheme;
      this.traditional = preferences.traditional_chinese_output;
      this.glosses = preferences.candidate_english_gloss;
      this.nineKeyMode = preferences.touch_keyboard_layout === 'nine_key'
        && preferences.scheme === 'quanpin';
    } catch (error) {
      KeyboardLog.error(`host preparation unreadable: ${describeError(error)}`);
      return false;
    }
    try {
      const created: CreateResponse = JSON.parse(client.create(options)) as CreateResponse;
      if (!created.ok) {
        KeyboardLog.error(`session refused: ${created.error}`);
        return false;
      }
      this.handle = created.value.session;
      KeyboardLog.info(`session ${this.handle} created`);
      return true;
    } catch (error) {
      // A response that will not parse means the ABI moved underneath us. Refusing to start is
      // better than driving a session whose replies we cannot read.
      KeyboardLog.error(`session reply unreadable: ${describeError(error)}`);
      return false;
    }
  }

  /** What the user chose for the keyboard's appearance and scheme. */
  preferences(): KeyboardPreferences {
    return this.appearance;
  }

  /**
   * Turns the platform's inputPattern into the traits EditorPolicy reasons about.
   *
   * The port keeps the platform constants out of EditorPolicy on purpose: they are declared in
   * @ohos.inputMethodEngine without values, so the numbers belong to the runtime and must not be
   * guessed. Translating here is what lets the policy stay plain TypeScript and testable.
   */
  private static traitsFor(pattern: number): EditorTraits {
    const password: boolean = pattern === inputMethodEngine.PATTERN_PASSWORD
      || pattern === inputMethodEngine.PATTERN_PASSWORD_SCREEN_LOCK
      || pattern === inputMethodEngine.PATTERN_PASSWORD_NUMBER
      || pattern === inputMethodEngine.PATTERN_NEW_PASSWORD;
    return {
      text: pattern === inputMethodEngine.PATTERN_TEXT
        || pattern === inputMethodEngine.PATTERN_NULL
        || pattern === inputMethodEngine.PATTERN_EMAIL
        || pattern === inputMethodEngine.PATTERN_URI
        || pattern === inputMethodEngine.PATTERN_USER_NAME,
      password: password,
      uri: pattern === inputMethodEngine.PATTERN_URI,
      email: pattern === inputMethodEngine.PATTERN_EMAIL,
      // A one-time code is typed, not composed, and a user name is not a sentence.
      noSuggestions: pattern === inputMethodEngine.PATTERN_ONE_TIME_CODE
        || pattern === inputMethodEngine.PATTERN_USER_NAME
    };
  }

  /** Whether this editor should be composed through the Engine at all. */
  composes(): boolean {
    return EditorPolicy.useEngine(this.traits);
  }

  /**
   * Whether a shift-modified letter should reach the Engine as composition helpcode rather than as
   * an uppercase letter. It means something only while a quanpin or shuangpin composition is open.
   */
  entersHelpcode(shifted: boolean): boolean {
    return ChineseHelpcodePolicy.entersHelpcode(this.englishMode, shifted, this.editing,
      this.scheme, this.localMode);
  }

  /** True when the Engine is composing English rather than Chinese. */
  isEnglish(): boolean {
    return this.englishMode;
  }

  /** Tells the Engine which grid the user is typing on, so a 2 means ABC rather than a digit. */
  /** The scheme now in force, which decides whether the nine-key flag means anything. */
  useScheme(name: string): void {
    this.schemeName = name;
  }

  setNineKey(enabled: boolean): void {
    // The Engine's nine-key flag belongs to quanpin alone — Japanese has its own kana grid and the
    // other schemes have none, and it answers "nine-key mode requires the quanpin scheme" for any
    // of them. Asking anyway put a refusal in the log on every Japanese focus.
    const wanted: boolean = enabled && this.schemeName === 'quanpin';
    if (this.handle === 0 || this.nineKeyMode === wanted) {
      return;
    }
    this.nineKeyMode = wanted;
    this.applyView(client.setNineKeyMode(this.handle, wanted));
  }

  /** Flips the composing language and reports the mode now in force. */
  toggleLanguage(): boolean {
    if (this.handle === 0) {
      return this.englishMode;
    }
    this.englishMode = !this.englishMode;
    this.applyView(client.setEnglishMode(this.handle, this.englishMode));
    return this.englishMode;
  }

  /** What this editor asked its return key to do, in the shared editor-action numbering. */
  returnAction(): number {
    return this.enterKey;
  }

  /** The return key, doing whatever this particular editor asked its return key to do. */
  submit(): void {
    if (this.inputClient !== undefined) {
      this.inputClient.sendKeyFunction(this.enterKey);
    }
  }

  /** The framework hands over a fresh client on every inputStart. */
  attach(inputClient: inputMethodEngine.InputClient): void {
    this.inputClient = inputClient;
    inputClient.getEditorAttribute().then((attribute: inputMethodEngine.EditorAttribute): void => {
      this.enterKey = attribute.enterKeyType;
      this.traits = KeyboardSession.traitsFor(attribute.inputPattern);
      // A password field must never see a composition buffer, and a field that asked for no
      // suggestions has said it does not want one. Latin for an address, where Chinese would only
      // be in the way.
      const english: boolean = this.englishMode || EditorPolicy.prefersLatin(this.traits);
      if (this.handle !== 0 && english !== this.englishMode) {
        this.englishMode = english;
        this.applyView(client.setEnglishMode(this.handle, english));
      }
      if (this.onEditorChanged !== undefined) {
        this.onEditorChanged();
      }
    }).catch((error: Object): void => {
      KeyboardLog.error(`editor attribute unavailable: ${describeError(error)}`);
    });
    if (this.handle !== 0) {
      this.apply(client.focus(this.handle, true));
      this.applyView(client.setEnglishMode(this.handle, this.englishMode));
      this.applyView(client.setNineKeyMode(this.handle, this.nineKeyMode));
    }
  }

  detach(): void {
    if (this.handle !== 0) {
      this.apply(client.focus(this.handle, false));
    }
    this.inputClient = undefined;
  }

  stop(): void {
    if (this.handle !== 0) {
      client.destroy(this.handle);
      this.handle = 0;
    }
  }

  press(ascii: number, shift: boolean): void {
    if (!this.composes()) {
      // Straight to the editor, with no composition and nothing learned. A password or a one-time
      // code is not something an input method should be holding, let alone remembering.
      this.insert(shift ? String.fromCharCode(ascii).toUpperCase() : String.fromCharCode(ascii));
      return;
    }
    if (this.handle === 0) {
      // Deliberately without the character: hilog is readable by tooling, and what the user types
      // does not belong in it. The refusal itself is the diagnostic.
      KeyboardLog.error('key ignored: no session');
      return;
    }
    this.apply(client.character(this.handle, ascii, shift));
  }

  private command(command: InputCommand): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.command(this.handle, command));
  }

  commitHighlighted(): void {
    this.command(InputCommand.SELECT_HIGHLIGHTED);
  }

  backspace(): void {
    this.command(InputCommand.BACKSPACE);
  }

  /** Throw the composition away without committing it, which is what 重输 means. */
  cancel(): void {
    this.command(InputCommand.CANCEL);
  }

  /** Commit the spelling as typed rather than any candidate. */
  commitRaw(): void {
    this.command(InputCommand.COMMIT_RAW);
  }

  moveLeft(): void {
    this.command(InputCommand.MOVE_LEFT);
  }

  moveRight(): void {
    this.command(InputCommand.MOVE_RIGHT);
  }

  nextPage(): void {
    this.command(InputCommand.NEXT_PAGE);
  }

  previousPage(): void {
    this.command(InputCommand.PREVIOUS_PAGE);
  }

  choose(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.select(this.handle, this.generation, index));
  }

  private apply(raw: string): void {
    let response: Response;
    try {
      response = JSON.parse(raw) as Response;
    } catch (error) {
      // Silence here would look exactly like a key that did nothing, which is the hardest kind of
      // failure to chase on a device. The reply itself stays out of the log: it carries candidates,
      // and candidates are the user's text.
      KeyboardLog.error(`unreadable engine reply: ${describeError(error)}`);
      return;
    }
    if (!response.ok) {
      KeyboardLog.error(`engine refused: ${response.error}`);
      return;
    }
    const value: EngineValue = response.value;
    // Bounded before it reaches the surface: a diagnostic is a message, not a place to print a
    // stack trace into a keyboard four rows tall.
    this.fullWidth = value.view.character_width === 'fullwidth';
    this.editing = value.view.editing_text;
    this.scheme = value.view.scheme;
    this.localMode = value.view.local_mode;
    this.diagnostic = InputDiagnosticPolicy.normalize(
      value.diagnostic === undefined ? null : value.diagnostic);
    const commit: string | null | undefined = value.commit;
    if (commit !== null && commit !== undefined && commit.length > 0
        && this.inputClient !== undefined) {
      // The Engine commits simplified; whether the user wanted traditional is a host decision, the
      // same boundary the Apple and Android hosts draw.
      this.inputClient.insertText(this.asTraditional(commit));
    }
    this.render(value.view);
  }

  /** For the entry points whose reply is a bare view. */
  private applyView(raw: string): void {
    let response: ViewResponse;
    try {
      response = JSON.parse(raw) as ViewResponse;
    } catch (error) {
      KeyboardLog.error(`unreadable engine view: ${describeError(error)}`);
      return;
    }
    if (!response.ok) {
      KeyboardLog.error(`engine refused: ${response.error}`);
      return;
    }
    this.render(response.value);
  }

  private diagnostic: string = '';
  private fullWidth: boolean = false;
  private traditional: boolean = false;
  private glosses: boolean = false;
  // Which view a pending gloss lookup belongs to. A gloss arrives after the keystroke that asked for
  // it, and by then the composition may have moved on; anything stale is dropped rather than painted
  // onto whatever is on screen now.
  private glossEpoch: number = 0;
  // ICU's Simplified-Traditional, which is the same transliteration Android reaches through its own
  // ICU and Apple through its host boundary. Built once: constructing one per commit would pay for
  // the table on every keystroke.
  private converter: i18n.Transliterator | undefined = undefined;
  private editing: string = '';
  private scheme: number = 0;
  private localMode: string = 'none';

  /**
   * Asks the packaged dictionary for English glosses and reports them when they arrive.
   *
   * Opt-in, offline, and bounded by the policy: an entry too long to be a gloss is not one. The
   * Engine's own annotation wins the shared slot, so a Wubi code is never displaced by a
   * translation.
   */
  private requestGlosses(view: EngineView, entries: CandidateEntry[]): void {
    if (!this.glosses || this.handle === 0 || view.candidates.length === 0) {
      return;
    }
    const token: GlossToken = CandidateGlossPolicy.token(this.handle, view.generation,
      ++this.glossEpoch);
    const candidates: GlossRequestCandidate[] = [];
    for (const candidate of view.candidates) {
      candidates.push({ text: candidate.text, source: candidate.source });
    }
    const request: GlossRequest = {
      generation: view.generation, user_data: '', candidates: candidates
    };
    try {
      const response: GlossResponse = JSON.parse(
        client.candidateGlosses(JSON.stringify(request), this.resourceDirectory)) as GlossResponse;
      if (!response.ok) {
        KeyboardLog.error(`candidate glosses refused: ${response.error}`);
        return;
      }
      if (!CandidateGlossPolicy.isCurrent(token, this.handle, this.generation, this.glossEpoch)) {
        return;
      }
      const glossed: CandidateEntry[] = [];
      for (let index: number = 0; index < entries.length; index++) {
        glossed.push({
          text: entries[index].text,
          hint: entries[index].hint,
          annotation: CandidateGlossPolicy.annotation(entries[index].annotation,
            index < response.value.length ? response.value[index] : null, true)
        });
      }
      if (this.onChanged !== undefined) {
        this.onChanged({
          candidates: glossed, editing: view.editing_text, spellings: view.nine_key_spellings,
          scheme: view.scheme, shuangpinProfile: view.shuangpin_profile,
          localMode: view.local_mode, english: view.dedicated_english,
          diagnostic: this.diagnostic
        });
      }
    } catch (error) {
      KeyboardLog.error(`candidate glosses unreadable: ${describeError(error)}`);
    }
  }

  private render(view: EngineView): void {
    this.generation = view.generation;
    const entries: CandidateEntry[] = [];
    for (const candidate of view.candidates) {
      entries.push({
        text: candidate.text,
        // Only the part of the code still untyped, and only where that means something. The policy
        // decides; this just supplies what it reasons about.
        hint: WubiCodeHintPolicy.hint(candidate.code, view.preedit, true, view.scheme,
          view.local_mode, view.answered_by_pinyin_fallback),
        annotation: candidate.annotation
      });
    }
    if (this.onChanged !== undefined) {
      this.onChanged({
        candidates: entries,
        editing: view.editing_text,
        spellings: view.nine_key_spellings,
        scheme: view.scheme,
        shuangpinProfile: view.shuangpin_profile,
        localMode: view.local_mode,
        english: view.dedicated_english,
        diagnostic: this.diagnostic
      });
    }
  }

  private clipboardFile(): string {
    return `${this.stateDirectory}/clipboard-history.json`;
  }

  /**
   * The saved clipboard history.
   *
   * A file too large to be a history of fifty bounded entries is not read at all: the bound exists
   * so that a wrong or corrupted path cannot turn into an unbounded read.
   */
  clipboardHistory(): ClipboardHistoryItem[] {
    const file: string = this.clipboardFile();
    try {
      if (!fs.accessSync(file) || fs.statSync(file).size > MAX_FILE_BYTES) {
        return [];
      }
      return ClipboardHistoryStore.parse(fs.readTextSync(file));
    } catch (error) {
      KeyboardLog.error(`clipboard history unreadable: ${describeError(error)}`);
      return [];
    }
  }

  saveClipboardHistory(items: ClipboardHistoryItem[]): boolean {
    try {
      const document: string = ClipboardHistoryStore.serialize(items);
      const handle = fs.openSync(this.clipboardFile(),
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(handle.fd, document);
      fs.closeSync(handle);
      return true;
    } catch (error) {
      KeyboardLog.error(`clipboard history not saved: ${describeError(error)}`);
      return false;
    }
  }

  /**
   * Whether this build may read the system clipboard at all.
   *
   * READ_PASTEBOARD is system_basic on OpenHarmony, so an ordinary third-party input method is
   * refused it however it asks; only a build signed with a provisioning profile carrying the ACL
   * gets it. Without this check a denied read is indistinguishable from an empty clipboard, and the
   * keyboard would tell the user there was nothing to save when in fact it was not allowed to look.
   */
  async canReadClipboard(): Promise<boolean> {
    try {
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const granted: abilityAccessCtrl.GrantStatus =
        await abilityAccessCtrl.createAtManager().checkAccessToken(
          info.appInfo.accessTokenId, 'ohos.permission.READ_PASTEBOARD');
      return granted === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      KeyboardLog.error(`clipboard permission unknown: ${describeError(error)}`);
      return false;
    }
  }

  /**
   * Whatever plain text the system clipboard holds, or an empty string when it holds none.
   *
   * The plain-text record is asked for only once the clipboard says it has one. getPrimaryText is
   * declared as returning a string, but on a clipboard holding an image or nothing at all it hands
   * back undefined, and the caller then has a string that is not one. This is a system boundary, so
   * the check belongs here rather than at every use.
   */
  async systemClipboardText(): Promise<string> {
    try {
      const data: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      if (data.getRecordCount() === 0 || !data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        return '';
      }
      const text: string | undefined = data.getPrimaryText();
      return text === undefined ? '' : text;
    } catch (error) {
      // A clipboard the user has not granted, or one holding something that is not text.
      KeyboardLog.error(`clipboard unavailable: ${describeError(error)}`);
      return '';
    }
  }

  /**
   * Applies a set of stored preferences together, to the live session and to disk.
   *
   * All of them at once, not one call each. A scheme, its shuangpin profile and its keyboard layout
   * are a single decision, and writing them separately fails on the second write: the session
   * refuses a revision it has already seen, and the store compares against what is on disk, which
   * the first write has already moved.
   *
   * The document is read, edited and written whole rather than patched. The store rejects anything
   * it cannot parse in full, and everything this keyboard does not understand travels across
   * untouched, so changing a skin here cannot quietly drop a setting made on another host.
   */
  changePreferences(changes: Map<string, Object>): boolean {
    if (this.handle === 0) {
      return false;
    }
    try {
      const loaded: SnapshotResponse =
        JSON.parse(client.loadPreferences(this.stateDirectory)) as SnapshotResponse;
      if (!loaded.ok) {
        KeyboardLog.error(`preferences unreadable: ${loaded.error}`);
        return false;
      }
      const snapshot: PreferencesSnapshot = loaded.value;
      // What is on disk now, which is what the store compares against before it overwrites.
      const expected: number = snapshot.revision;
      changes.forEach((value: Object, key: string): void => {
        snapshot.preferences[key] = value;
      });
      snapshot.revision = expected + 1;
      const document: string = JSON.stringify(snapshot);
      const applied: PrepareResponse =
        JSON.parse(client.updatePreferences(this.handle, document)) as PrepareResponse;
      if (!applied.ok) {
        KeyboardLog.error(`preferences refused: ${applied.error}`);
        return false;
      }
      const saved: PrepareResponse =
        JSON.parse(client.savePreferences(this.stateDirectory, expected, document)) as
          PrepareResponse;
      if (!saved.ok) {
        // The session already has them; only the write failed. Say so rather than pretending the
        // change did not happen, because on screen it plainly did.
        KeyboardLog.error(`preferences not persisted: ${saved.error}`);
      }
      return true;
    } catch (error) {
      KeyboardLog.error(`preferences failed: ${describeError(error)}`);
      return false;
    }
  }

  /**
   * One page of the local emoji catalog.
   *
   * Reads others.db directly rather than through the session: the catalog is a property of the
   * installed dictionary, not of what is being typed, and nothing about it changes with focus.
   */
  emojiPage(group: string, offset: number, limit: number): EmojiPage | null {
    const query: EmojiQuery = {
      category: 'emoji',
      limit: limit,
      offset: offset,
      group: group,
      cursor: true,
      list_groups: false
    };
    try {
      const response: EmojiResponse =
        JSON.parse(client.emojiCatalog(JSON.stringify(query), this.resourceDirectory)) as
          EmojiResponse;
      if (!response.ok) {
        KeyboardLog.error(`emoji catalog refused: ${response.error}`);
        return null;
      }
      return response.value;
    } catch (error) {
      KeyboardLog.error(`emoji catalog unreadable: ${describeError(error)}`);
      return null;
    }
  }

  /**
   * Simplified to Traditional, where the user asked for it and the text is Chinese to begin with.
   *
   * A converter that fails must not lose the text, so anything it cannot do falls back to what came
   * in. The policy decides whether it applies at all; Japanese and the local modes are not Chinese
   * output however the setting reads.
   */
  private asTraditional(text: string): string {
    if (!this.traditional) {
      return text;
    }
    if (this.converter === undefined) {
      try {
        this.converter = i18n.Transliterator.getInstance('Simplified-Traditional');
      } catch (error) {
        KeyboardLog.error(`no simplified-to-traditional transliterator: ${describeError(error)}`);
        this.traditional = false;
        return text;
      }
    }
    const converter: i18n.Transliterator = this.converter;
    return ChineseOutputPolicy.output(text, true,
      ChineseOutputPolicy.applies(this.englishMode, this.scheme, this.localMode),
      (value: string): string => converter.transform(value));
  }

  /**
   * Put text into the editor directly. It is text, not a composition, so it bypasses the Engine.
   *
   * Fullwidth is applied here rather than left to the Engine: the Engine converts what it commits,
   * and this is the path for everything it does not see — an emoji, a clipboard entry, a letter
   * typed in a password field. Without it the same setting would apply to some of the user's text
   * and not the rest.
   */
  insert(text: string): void {
    if (this.inputClient !== undefined) {
      const widened: string | null = FullWidthInputPolicy.output(text, this.fullWidth);
      this.inputClient.insertText(this.asTraditional(widened === null ? text : widened));
    }
  }

  /**
   * Every candidate for what is being spelled, not just the page on screen.
   *
   * Paging was the only way past the ninth candidate, which put the tail of a long answer dozens of
   * taps away. Showing the whole list at once is the arrangement the iOS keyboard settled on for the
   * same reason.
   */
  allCandidates(): string[] {
    if (this.handle === 0) {
      return [];
    }
    try {
      const response: SnapshotCandidates =
        JSON.parse(client.allCandidates(this.handle)) as SnapshotCandidates;
      if (!response.ok) {
        KeyboardLog.error(`candidate list refused: ${response.error}`);
        return [];
      }
      // The generation identifies the composition these belong to; selecting against a stale one
      // would act on a list the user is no longer looking at.
      this.generation = response.value.generation;
      const texts: string[] = [];
      for (const candidate of response.value.candidates) {
        texts.push(candidate.text);
      }
      return texts;
    } catch (error) {
      KeyboardLog.error(`candidate list unreadable: ${describeError(error)}`);
      return [];
    }
  }

  /**
   * The candidate-management operations behind a long press: promote it, pin it to the front, let go
   * of a pinned position, or take the entry out of the dictionary altogether.
   */
  promoteCandidate(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.pinCandidate(this.handle, this.generation, index));
  }

  /** Position 1 is the front of the list, which is what 固定到首位 means. */
  fixCandidateFirst(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.fixCandidatePosition(this.handle, this.generation, index, 1));
  }

  clearCandidatePosition(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.clearCandidatePosition(this.handle, this.generation, index));
  }

  removeCandidate(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.removeCandidate(this.handle, this.generation, index));
  }

  /** Select by position in the full list rather than in the page. */
  chooseAny(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.selectAnyCandidate(this.handle, this.generation, index));
  }

  /** Commit to one reading of the digits typed so far. */
  chooseSpelling(index: number): void {
    if (this.handle === 0) {
      return;
    }
    this.apply(client.chooseNineKeySpelling(this.handle, this.generation, index));
  }
}
