import inputMethodEngine from '@ohos.inputMethodEngine';
import client from 'libmsimeclient.so';
import { utf8Length } from './Utf8';
import { KeyboardLog, describeError } from './KeyboardLog';
import { DictionaryMaintenancePolicy } from './DictionaryMaintenancePolicy';
import { TypingStatisticsPolicy } from './TypingStatisticsPolicy';
import { KeyboardSkin } from './skin/KeyboardSkin';
import { CustomKeyboardSkin, CustomSkinDocument } from './skin/CustomKeyboardSkin';
import { KeyboardFormFactor } from './KeyboardFormFactor';
import { KeyboardScheme, PreferenceMapping, SchemeDefinition } from './KeyboardScheme';
import { EditorPolicy, EditorTraits } from './input/EditorPolicy';
import {
  CapitalizationMode, EnglishCapitalizationPolicy
} from './input/EnglishCapitalizationPolicy';
import { WubiCodeHintPolicy } from './input/WubiCodeHintPolicy';
import { KeyboardGeometry } from './KeyboardGeometry';
import { FullWidthInputPolicy } from './input/FullWidthInputPolicy';
import { ChineseHelpcodePolicy } from './input/ChineseHelpcodePolicy';
import { ChineseOutputPolicy } from './input/ChineseOutputPolicy';
import { KeyboardFeedback, FeedbackSettings, HapticStrength } from './KeyboardFeedback';
import { HardwareNavigationPreferences } from './HardwareKeyRouter';
import vibrator from '@ohos.vibrator';
import common from '@ohos.app.ability.common';
import i18n from '@ohos.i18n';
import { InputDiagnosticPolicy } from './input/InputDiagnosticPolicy';
import { InputModeHudPolicy } from './InputModeHudPolicy';
import { HardwareKeyTarget } from './HardwareKeyDispatch';
import { DEFAULT_VOICE_HOTKEY_BINDINGS, VoiceHotkeyAction, VoiceHotkeyBindings, VoiceHotkeyPolicy,
  VoiceKey } from './input/VoiceHotkeyPolicy';
import { HarmonyVoiceRecordingBehaviour } from './input/HarmonyVoiceRecordingBehaviour';
import { EnglishCompletions, EnglishReplacement, EnglishSuggestionPolicy }
  from './input/EnglishSuggestionPolicy';
import { ImeModeScopePolicy } from './input/ImeModeScopePolicy';
import { ModeBindings, DEFAULT_MODE_BINDINGS } from './InputModeRouting';
import { FloatingToolbarLayout, ToolbarButton, ToolbarComponents, ToolbarState }
  from './FloatingToolbarLayout';
import { ToolbarSkin, ToolbarSkinPolicy } from './ToolbarSkinPolicy';
import { DesktopSurface } from './DesktopSurface';
import { CandidateAnnotationPreferencePolicy } from './candidate/CandidateAnnotationPreferencePolicy';
import { CandidateManagementAction } from './candidate/CandidateManagementAction';
import { CandidateGlossPolicy } from './candidate/CandidateGlossPolicy';
import { CandidatePresentationPolicy } from './candidate/CandidatePresentationPolicy';
import {
  CandidateSkinCatalogPolicy, CandidateSkinPackage, CandidateSkinPaletteTokens, CandidateSkinDecoration
} from './candidate/CandidateSkinCatalogPolicy';
import { CandidateWidthPolicy } from './candidate/CandidateWidthPolicy';
import { OnlineCandidatePolicy, OnlineQuery } from './candidate/OnlineCandidatePolicy';
import {
  TranslationPolicy, TranslationQuery, TranslationPlanItem, TranslationEntry,
  TranslationProviderConfig, TencentTranslationConfig, NiuTransTranslationConfig, TranslationCandidate
} from './candidate/TranslationPolicy';
import { TranslationSensePolicy } from './candidate/TranslationSensePolicy';
import fs from '@ohos.file.fs';
import pasteboard from '@ohos.pasteboard';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import http from '@ohos.net.http';
import {
  ClipboardHistoryStore, ClipboardHistoryItem, ClipboardHistoryError, ClipboardFailure
} from './clipboard/ClipboardHistoryStore';
import { ClipboardHistoryPreferencePolicy } from './clipboard/ClipboardHistoryPreferencePolicy';
import {
  DEFAULT_VOICE_INPUT_CONFIGURATION, VoiceInputConfiguration, VoiceInputConfigurationPolicy
} from './input/VoiceInputConfiguration';
import {
  AiPolishPolicy, MAX_POLISH_SOURCE_CHARACTERS, PolishReplacement
} from './input/AiPolishPolicy';
import { HarmonyVoicePolisher } from './input/HarmonyVoicePolisher';
import { SmartPunctuationSpacePolicy, SmartPunctuationSpaceSnapshot, SpaceConvertDecision }
  from './input/SmartPunctuationSpacePolicy';
import { SmartPunctuationContext } from './input/SmartPunctuationContext';
import { PairedPunctuationPolicy, PairedPunctuationCompletion } from
  './input/PairedPunctuationPolicy';
import { CandidateTextPolicy, CandidateTextEdge } from './input/CandidateTextPolicy';
import { ReplyKeyboardPolicy, ReplyRequest } from './ReplyKeyboardPolicy';
import { ReplyContextPolicy } from './ReplyContextPolicy';
import {
  CommunityReplyLibraryPolicy, CommunityReplyTemplate
} from './CommunityReplyLibraryPolicy';
import {
  EmojiCatalogModel, EMOJI_RECENTS_MAX_BYTES, EmojiSymbolGroup,
  normalizeGroups, normalizeSymbolGroups
} from './emoji/EmojiCatalogModel';
import {
  SmartPunctuationRepeatPolicy, SmartPunctuationRepeatSnapshot
} from './input/SmartPunctuationRepeatPolicy';
import { BackspaceHoldPolicy } from './input/BackspaceHoldPolicy';
import {
  CompositionBoundary, CompositionBoundaryAction, CompositionBoundaryPolicy
} from './input/CompositionBoundaryPolicy';

// Shapes of the JSON the shared C ABI answers with. Only the fields this minimal surface reads are
// declared; the responses carry considerably more.
interface Candidate {
  text: string;
  highlighted: boolean;
  /** Which part of the Engine produced it; the gloss lookup treats sources differently. */
  source: number;
  /** Zero when unpinned, otherwise the fixed candidate slot (1..5). */
  fixed_position: number;
  /** The Engine input code that produced this candidate, used for scheme-specific hints. */
  code: string;
  /** An Engine-derived display suffix, never part of what gets committed. */
  annotation: string;
  /** Optional translation attached by the shared Engine for this generation. */
  translation?: string | null;
}

/** A candidate as the view draws it: the text, and whatever is printed beside it. */
export interface CandidateEntry {
  readonly text: string;
  readonly hint: string;
  readonly annotation: string;
  /** The annotation slot is a translation rather than an Engine annotation; they are styled
   * differently because the source styles only one of them. */
  readonly annotationIsTranslation: boolean;
  /** Engine-selected candidate; selection is not necessarily the first row. */
  readonly highlighted: boolean;
  readonly badge: string;
  readonly fixedPosition: number;
  readonly source: number;
  /** Translation attached to this exact Engine candidate, when one has been resolved. */
  readonly translation: string | null;
}

interface EngineView {
  candidates: Candidate[];
  editing_text: string;
  /**
   * 已经选中的那一段，运行时替这个宿主留在组字里而不是立刻上屏。
   *
   * 候选只吃掉部分输入时，引擎会继续组字并把选中的那一段交回来。留住它的宿主必须把它画出来：
   * 请求了却不画，用户已经选中的字既不在文档里也不在屏幕上，而组字在他取消之前不会结束
   * （scripts/test-phrase-preedit-hosts.py 守的就是这一半状态）。
   */
  phrase_prefix: string;
  /** Byte offset into `editing_text`, which for this ASCII text is also the character index. */
  caret_position: number;
  generation: number;
  /** Which spellings the digits typed so far could be, offered while the nine-key grid is up. */
  nine_key_spellings: string[];
  /**
   * What the Engine is committing its own output as.
   *
   * 'Fullwidth' or 'Halfwidth', capitalised: this is the Rust enum's own name, not the lowercase
   * spelling the preference document uses for the same idea. Comparing it against the preference
   * vocabulary matches nothing, which is a toggle that reports success and changes no face.
   */
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

interface TypingStatisticsRecordAction {
  operation: string;
  text: string;
  source: string;
  day: string;
  hour: number;
}

interface TypingStatisticsRecordRequest {
  directory: string;
  action: TypingStatisticsRecordAction;
}

interface MobileClipboardAction {
  operation: string;
  text?: string;
  pinned?: boolean;
}

interface MobileClipboardRequest {
  directory: string;
  legacy: string;
  action: MobileClipboardAction;
}

interface NativeClipboardEntry {
  text: string;
  timestampMs: number;
  pinned: boolean;
}

interface MobileClipboardValue {
  entries: NativeClipboardEntry[];
  captured?: boolean;
  reason?: string | null;
  updated?: boolean;
  removed?: boolean;
  cleared?: boolean;
}

interface MobileClipboardReply {
  ok: boolean;
  value: MobileClipboardValue;
  error: string;
}

export interface ClipboardHistoryMutation {
  readonly entries: ClipboardHistoryItem[];
  readonly failure: ClipboardFailure | null;
}

// The local emoji catalog lives in others.db beside the dictionaries, so the query carries the
// resource directory rather than going through a session.
/** `{prefix,limit}` as the shared ABI reads it; the prefix is ASCII letters and the limit 1..32. */
interface EnglishCompletionRequest {
  prefix: string;
  limit: number;
}

interface EmojiQuery {
  category: string;
  limit: number;
  offset: number;
  group: string;
  cursor: boolean;
  list_groups: boolean;
  list_symbol_groups: boolean;
  parent: string;
  search: string;
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

interface EmojiGroups {
  groups: string[];
}

interface EmojiGroupsResponse {
  ok: boolean;
  value: EmojiGroups;
  error: string;
}

interface EmojiSymbolGroups {
  symbol_groups: EmojiSymbolGroup[];
}

interface EmojiSymbolGroupsResponse {
  ok: boolean;
  value: EmojiSymbolGroups;
  error: string;
}

/**
 * One row of the expanded panel: the word and whatever is written under it.
 *
 * Deliberately narrower than CandidateEntry. The panel draws a text and a gloss and selects through
 * selectAnyCandidate, which takes a position in this list; the fixed slot and the source belong to
 * the page the management operations act on, and carrying them here would invite indexing one list
 * with the other's number.
 */
export interface ExpandedCandidate {
  readonly text: string;
  readonly annotation: string;
  readonly annotationIsTranslation: boolean;
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

interface NativeReply<T> {
  ok: boolean;
  value: T;
  error: string;
}

/** What the shared ABI is asked to turn into a provider request. */
interface AiHttpRequestInput {
  segmented_pinyin: string[];
  context: string;
  candidate_limit: number;
}

interface AiHttpRequest {
  config: PreparedAiAssistant;
  input: AiHttpRequestInput;
}

interface AiHttpDescriptor {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: Object;
  timeout_ms: number;
  connect_timeout_ms: number;
  max_response_bytes: number;
}

interface PreparedAiAssistant {
  enabled: boolean;
  provider: string;
  model: string;
  token: string;
  tokens: Record<string, string>;
  endpoint: string;
  candidate_limit: number;
  prompt_id: string;
  prompt: string;
  prompt_custom_1: string;
  prompt_custom_2: string;
  prompt_custom_3: string;
}

interface TranslationHttpDescriptor {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: Object;
  body_utf8?: string;
  timeout_ms: number;
  max_response_bytes: number;
  expected_count?: number;
}

interface TranslationResponseValue {
  generation: number;
  translations: TranslationEntry[];
}

interface GlossRequestCandidate {
  text: string;
  source: number;
}

interface GlossRequestDocument {
  generation: number;
  user_data: string;
  candidates: GlossRequestCandidate[];
}

interface TranslationPlanDocument {
  target_language: string;
  candidates: GlossRequestCandidate[];
}

interface TencentTranslationRequest {
  config: TencentTranslationConfig;
  texts: string[];
  source_language: string;
  target_language: string;
  timestamp: number;
}

interface NiuTransTranslationRequest {
  config: NiuTransTranslationConfig;
  text: string;
  source_language: string;
  target_language: string;
  timestamp: string;
}

interface CustomTranslationRequest {
  config: TranslationProviderConfig;
  text: string;
  source_language: string;
  target_language: string;
}

interface TranslationGlossSaveRequest {
  target_language: string;
  translations: TranslationEntry[];
}

interface OnlineApplyValue {
  applied: boolean;
  view: EngineView;
}

/** What the view draws. Grouped so a new field does not change every signature on the way there. */
export interface KeyboardState {
  readonly candidates: CandidateEntry[];
  readonly editing: string;
  readonly editingCaret: number;
  readonly spellings: string[];
  readonly scheme: number;
  readonly shuangpinProfile: string;
  readonly localMode: string;
  readonly english: boolean;
  readonly diagnostic: string;
}

interface EngineValue {
  /** False means the platform editor, rather than the Engine composition, owns the command. */
  handled: boolean;
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

interface VoiceGenerationResponse {
  ok: boolean;
  value: number;
  error: string;
}

interface VoiceTextResponse {
  ok: boolean;
  value: string | null;
  error: string;
}

interface SkinCatalogValue {
  packages: CandidateSkinPackage[];
}

interface SkinCatalogResponse {
  ok: boolean;
  value: SkinCatalogValue;
  error: string;
}

/** One file inside an external skin package, named the way the shared ABI names it. */
interface SkinResourceRequest {
  directory: string;
  id: string;
  relative: string;
  kind: string;
}

interface SkinResourceValue {
  contentType: string;
  bytes: number[];
}

/** A candidate decoration image, already encoded for the component that draws it. */
interface CandidateSkinImage {
  image: string | null;
  aspectRatio: number;
}

/** What every path that has no decoration to draw returns, rather than a fresh literal each time. */
const NO_CANDIDATE_SKIN_IMAGE: CandidateSkinImage = { image: null, aspectRatio: 1 };

// Enough for the sentence rule to walk back over trailing spaces and closing quotes to the mark that
// ended the last sentence. A caret further than this from one is in the middle of a sentence by any
// reading, and the call is made on every text change, so it stays bounded.
const MAX_CAPITALIZATION_CONTEXT_CHARACTERS: number = 64;

interface SkinResourceResponse {
  ok: boolean;
  value: SkinResourceValue;
  error: string;
}

interface SkinToolbarStylesheetResponse {
  ok: boolean;
  value: string | null;
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
  /** `app` remembers the mode per application; `global` shares one across all of them. */
  ime_mode_scope?: string;
  scheme: string;
  /** Optional in the shared document; absent means the Wubi remaining-code hint stays on. */
  wubi_code_hint?: boolean;
  /** Whether the mode badge is drawn after a Chinese/English switch. Defaults to on. */
  input_mode_hud?: boolean;
  /** Read-only English word completions while typing directly in English. Defaults to on. */
  english_suggestions?: boolean;
  shuangpin_profile: string;
  touch_keyboard_layout: string;
  touch_keyboard_skin: string;
  candidate_skin: string;
  candidate_theme: string;
  candidate_selected_bar: boolean | null;
  candidate_follow_cursor: boolean;
  number_row_selection: boolean;
  navigation: PreparedNavigationPreferences;
  candidate_layout: string;
  candidate_preedit_style: string;
  candidate_font_size: number;
  candidate_preedit_font_size: number;
  candidate_font_family: string;
  /** Named first so Latin comes from it and Han falls through; absent means one family answers. */
  candidate_english_font?: string | null;
  candidate_fallback_fonts: string[];
  candidate_text_color: string | null;
  candidate_accent_color: string | null;
  candidate_number_color: string | null;
  candidate_selected_color: string | null;
  candidate_hover_color: string | null;
  candidate_surface_color: string | null;
  candidate_border_color: string | null;
  // 'follow', 'dark' or 'light' for the keyboard specifically; theme is the global one it falls
  // back to, and only if both defer does the system decide.
  screen_keyboard_theme: string;
  /** 'follow', 'dark' or 'light' for the floating toolbar; it falls back to the global theme. */
  toolbar_theme?: string;
  /** 'follow', 'dark' or 'light' for the voice panel; it falls back to the global theme. */
  voice_theme?: string;
  /** 'follow', 'dark' or 'light' for the emoji panel; it falls back to the global theme. */
  emoji_theme?: string;
  /** 'follow', 'dark' or 'light' for the handwriting panel; it falls back to the global theme. */
  handwriting_theme?: string;
  theme: string;
  traditional_chinese_output: boolean;
  chinese_punctuation: boolean;
  smart_punctuation: boolean;
  smart_punctuation_repeat: boolean;
  smart_punctuation_space_convert: boolean;
  paired_punctuation: boolean;
  punctuation_lock: string;
  word_character: PreparedWordCharacterPreferences;
  floating_toolbar: PreparedFloatingToolbar;
  candidate_english_gloss: boolean;
  /** Tenths of a vp, which is the unit the shared settings store these in. */
  touch_key_spacing_tenths: number;
  touch_row_spacing_tenths: number;
  /** Added to the total height of the key rows, between -12 and 48 vp. */
  touch_keyboard_height_adjustment: number;
  /** Show the native Harmony voice entry in the top touch-keyboard shortcut bar. */
  touch_voice_shortcut: boolean;
  /** Shared privacy switch for the private clipboard history file and keyboard entry point. */
  clipboard_history: boolean;
  /** Shared custom touch-keyboard design; nested fields use the shared camelCase JSON shape. */
  custom_touch_keyboard_skin?: CustomSkinDocument;
  voice_input: VoiceInputConfiguration;
  ai_assistant: PreparedAiAssistant;
  touch_keyboard_schemes: PreparedTouchKeyboardSchemes;
  keybindings: PreparedKeybindings;
}

/** The shared touch-scheme record: which schemes the picker offers, and which one is current. */
interface PreparedTouchKeyboardSchemes {
  enabled?: string[];
  selected: string | null;
}

interface PreparedNavigationPreferences {
  minus_equal: boolean;
  comma_period: boolean;
  brackets: boolean;
  tab: boolean;
  page_up_down: boolean;
  mouse_wheel: boolean;
  arrows: boolean;
}

interface PreparedWordCharacterPreferences {
  enabled: boolean;
  keys: string;
}

/** The shared floating toolbar record. Only what a HarmonyOS toolbar can honour is read from it. */
interface PreparedFloatingToolbar {
  enabled: boolean;
  english_mode: boolean;
  punctuation: boolean;
  fullwidth: boolean;
  character_set: boolean;
  emoji: boolean;
  screen_keyboard: boolean;
  /** Shared switch for the settings button; absent in older documents, where it was always shown. */
  settings?: boolean;
  scale_percent: number;
  font_size: number;
}

/** The shared mode-switch bindings, which a host with a real keyboard is the one to consume. */
interface PreparedKeybindings {
  switch_language_shift: boolean;
  switch_language_ctrl: boolean;
  switch_language_ctrl_alt_space: boolean;
  toggle_character_set_ctrl_shift_f: boolean;
}

/** What the view needs to draw itself, resolved once from the prepared preferences. */
export interface KeyboardPreferences {
  readonly dark: boolean;
  readonly skinId: string;
  readonly candidateSkinId: string;
  /** Base palette used by an external candidate skin, when its manifest is available. */
  readonly candidateSkinBase: string;
  /** Manifest minimum width, clamped to the same bounds as the native estimate. */
  readonly candidateMinWidthVp: number;
  /** Image-only data URL for a compatible external candidate decoration. */
  readonly candidateDecorationImage: string | null;
  readonly candidateDecorationTopVp: number;
  readonly candidateDecorationWidthVp: number;
  readonly candidateDecorationAspectRatio: number;
  readonly candidateDark: boolean;
  readonly candidateSelectedBar: boolean | null;
  readonly pairedPunctuation: boolean;
  readonly keyboardTheme: string;
  readonly toolbarTheme: string;
  readonly voiceTheme: string;
  readonly emojiTheme: string;
  readonly handwritingTheme: string;
  readonly globalTheme: string;
  readonly scheme: string;
  readonly shuangpinProfile: string;
  readonly layout: string;
  /** Shared touch-scheme ids enabled in the native picker, in shared declaration order. */
  readonly enabledSchemes: string[];
  /**
   * Which of them the shared page last chose, or null when it has never said.
   *
   * Read here rather than inferred from `scheme` and `layout`: those two are the Engine's view and
   * say nothing about whether the picker still offers what they resolve to.
   */
  readonly selectedScheme: string | null;
  readonly candidateFollowCursor: boolean;
  readonly numberRowSelection: boolean;
  readonly navigation: HardwareNavigationPreferences;
  /** Whether the desktop candidate panel shows the spelling above its candidates. */
  readonly candidateShowPreedit: boolean;
  readonly candidateLayout: string;
  readonly candidateFontSize: number;
  readonly candidatePreeditFontSize: number;
  readonly candidateFontFamily: string;
  readonly candidateEnglishFont: string | null;
  readonly candidateFallbackFonts: string[];
  readonly candidateTextColor: string | null;
  readonly candidateAccentColor: string | null;
  readonly candidateNumberColor: string | null;
  readonly candidateSelectedColor: string | null;
  readonly candidateHoverColor: string | null;
  readonly candidateSurfaceColor: string | null;
  readonly candidateBorderColor: string | null;
  readonly keySpacingTenths: number;
  readonly rowSpacingTenths: number;
  readonly heightAdjustment: number;
  readonly voiceShortcut: boolean;
  readonly thoughtfulReply: boolean;
}

interface PreparedOptions {
  preferences: PreparedPreferences;
  /**
   * 让运行时把已选的那一段留在组字里而不是立刻上屏。
   *
   * 准备宿主时不带这个字段，是这个宿主自己要求的：它会把那一段画在候选条的读音前面。请求与绘制
   * 是一个决定，只做一半就等于把用户已经选中的字藏起来。
   */
  phrase_preedit?: boolean;
}

interface PrepareResponse {
  ok: boolean;
  value: PreparedOptions;
  error: string;
}

interface DictionaryAction {
  operation: string;
}

interface DictionaryRequest {
  options: PreparedOptions;
  action: DictionaryAction;
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
  MOVE_HOME = 6,
  MOVE_END = 7,
  DELETE_FORWARD = 8,
  FINISH_COMPOSITION = 9,
  COMMIT_READING = 11,
  BACKSPACE_SEGMENT = 12,
  MOVE_LEFT_SEGMENT = 13,
  MOVE_RIGHT_SEGMENT = 14,
  NEXT_PAGE = 100,
  PREVIOUS_PAGE = 101,
  NEXT_CANDIDATE = 102,
  PREVIOUS_CANDIDATE = 103,
  FIRST_CANDIDATE = 104
}

const JAPANESE_SCHEME: number = 3;

/**
 * Owns the native session for the lifetime of the extension ability and turns key presses into
 * committed text. The ability creates it; the panel's UI reads state back through onChanged.
 *
 * Deliberately thin: the Engine decides what a key means, this only forwards and applies the result.
 */
export class KeyboardSession implements HardwareKeyTarget {
  static readonly shared: KeyboardSession = new KeyboardSession();

  private handle: number = 0;
  private inputClient: inputMethodEngine.InputClient | undefined = undefined;
  private editorGeneration: number = 0;
  // Editor mutations are echoed asynchronously through KeyboardDelegate.textChange. Keep the
  // count raised until those callbacks arrive so our own commit cannot be mistaken for a host edit
  // and finish a residual composition that the Engine deliberately left active.
  private pendingOwnEdits: number = 0;
  private replyContextGeneration: number = 0;
  private replyResultEditorGeneration: number = -1;
  private replyResultContextGeneration: number = -1;
  private replyResultTexts: string[] = [];
  private generation: number = 0;
  // The Engine opens a session in whichever mode the preferences name, and the shared default is
  // English. Remembered here so every focus reasserts it rather than inheriting the previous editor.
  private englishMode: boolean = false;
  /** The editor generation in which the user explicitly chose Chinese or English. */
  private manualLanguageGeneration: number = -1;
  // Which application the mode belongs to. Windows and macOS both keep this per application by
  // default; this host used to keep one mode for every editor it was ever attached to.
  private englishSuggestionsEnabled: boolean = true;
  // The completion list currently on the strip, the prefix it was asked for, and a counter that
  // makes every earlier answer stale. A reply that arrives after the word moved on is discarded.
  private englishSuggestions: string[] = [];
  private englishSuggestionPrefix: string = '';
  private englishSuggestionEpoch: number = 0;
  private englishSuggestionRequested: string = '';
  // The Windows voice shortcuts, which only a machine with a hardware keyboard can press.
  private voiceHotkeys: VoiceHotkeyPolicy = new VoiceHotkeyPolicy();
  // Whether the recognizer is running. The view owns it and says so; the shortcuts need to know,
  // because Space and Escape belong to a composition at every other moment.
  private voiceRecording: boolean = false;
  private voiceBehaviour: HarmonyVoiceRecordingBehaviour = new HarmonyVoiceRecordingBehaviour();
  private modeScope: ImeModeScopePolicy = new ImeModeScopePolicy();
  private modeScopeSetting: string = 'app';
  private defaultEnglish: boolean = false;
  // Hardware events report this independently of the Engine's dedicated-English mode. The
  // floating toolbar uses it as the same high-priority status shown by the Windows presenter.
  private capsLock: boolean = false;
  // The grid is the Engine's business too: it decides what a 2 means, and it only reads them as
  // nine-key spellings once it has been told the grid is up.
  private nineKeyMode: boolean = false;
  private schemeName: string = 'quanpin';
  private profileName: string = 'xiaohe';
  private clipboardHistoryEnabled: boolean = false;
  // The two optional candidate annotations. Held here rather than in KeyboardPreferences because the
  // session builds the candidate entries itself; the view only draws what it is handed.
  private wubiCodeHint: boolean = true;
  private candidateEnglishGloss: boolean = false;
  // Read before the panels are built, so a badge the user turned off is never created at all.
  private modeBadge: boolean = true;
  private resourceDirectory: string = '';
  private stateDirectory: string = '';
  private systemDark: boolean = false;
  // What the editor wants its return key to do. Sending this rather than a newline is what makes the
  // key search in a search field and send in a message field, which is the whole point of having it.
  private enterKey: number = inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
  private traits: EditorTraits = {
    text: true, password: false, uri: false, email: false, noSuggestions: false
  };
  /** What the attached editor asked for, already reconciled with the kind of field it is. */
  private capitalization: CapitalizationMode = CapitalizationMode.NONE;
  private appearance: KeyboardPreferences = {
    dark: false,
    skinId: 'forest',
    candidateSkinId: 'willow_green',
    candidateSkinBase: 'willow_green',
    candidateMinWidthVp: CandidateWidthPolicy.MIN_WIDTH_VP,
    candidateDecorationImage: null,
    candidateDecorationTopVp: 0,
    candidateDecorationWidthVp: 0,
    candidateDecorationAspectRatio: 1,
    candidateDark: false,
    candidateSelectedBar: null,
    pairedPunctuation: true,
    keyboardTheme: 'follow',
    toolbarTheme: 'follow',
    globalTheme: 'system',
    emojiTheme: 'follow',
    handwritingTheme: 'follow',
    voiceTheme: 'follow',
    // Everything, which is what an absent shared list means; the prepared record narrows it.
    enabledSchemes: KeyboardScheme.SCHEMES.map(
      (candidate: SchemeDefinition): string => candidate.preferenceId),
    selectedScheme: null,
    scheme: 'quanpin',
    shuangpinProfile: 'xiaohe',
    layout: 'twenty_six_key',
    candidateFollowCursor: true,
    numberRowSelection: false,
    candidateShowPreedit: true,
    candidateLayout: 'vertical',
    navigation: {
      minusEqual: true, commaPeriod: true, brackets: false,
      tab: true, pageUpDown: true, mouseWheel: false, arrows: true
    },
    candidateFontSize: 18,
    candidatePreeditFontSize: 15,
    candidateFontFamily: 'Noto Sans SC',
    candidateEnglishFont: null,
    candidateFallbackFonts: ['Noto Sans SC', 'Microsoft YaHei'],
    candidateTextColor: null,
    candidateAccentColor: null,
    candidateNumberColor: null,
    candidateSelectedColor: null,
    candidateHoverColor: null,
    candidateSurfaceColor: null,
    candidateBorderColor: null,
    keySpacingTenths: KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS,
    rowSpacingTenths: KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS,
    heightAdjustment: KeyboardGeometry.DEFAULT_HEIGHT_ADJUSTMENT_VP,
    voiceShortcut: false,
    thoughtfulReply: false
  };
  private voiceInput: VoiceInputConfiguration = DEFAULT_VOICE_INPUT_CONFIGURATION;
  /**
   * The session's own polisher, separate from the recognizer's.
   *
   * The recognizer cancels its polisher whenever recognition starts, stops or is abandoned, which
   * is right for a transcript and wrong for a rewrite the user is waiting on: sharing one would let
   * tapping the microphone silently discard a polish request that was about to answer.
   */
  private readonly polisher: HarmonyVoicePolisher = new HarmonyVoicePolisher();
  private aiAssistant: PreparedAiAssistant = {
    enabled: false, provider: 'deepseek', model: '', token: '', tokens: {}, endpoint: '',
    candidate_limit: 3, prompt_id: 'custom_1', prompt: '', prompt_custom_1: '',
    prompt_custom_2: '', prompt_custom_3: ''
  };

  onChanged: ((state: KeyboardState) => void) | undefined = undefined;
  /** The view removes clipboard history immediately when the shared privacy switch is turned off. */
  onClipboardHistoryChanged: ((enabled: boolean) => void) | undefined = undefined;
  /** Read-only English completions for the strip: the prefix they answer and the words offered. */
  onEnglishSuggestions: ((prefix: string, items: string[]) => void) | undefined = undefined;
  /** What a voice shortcut asked for, for the view that owns the recognizer. */
  onVoiceHotkey: ((action: VoiceHotkeyAction) => void) | undefined = undefined;
  /** The view removes the voice surface immediately when shared voice input is turned off. */
  onVoiceInputChanged: ((enabled: boolean) => void) | undefined = undefined;
  /** Lets a desktop panel resize when a vertical candidate page changes height. */
  onCandidateCount: ((count: number) => void) | undefined = undefined;
  /** Lets a desktop panel follow the widest current candidate without measuring ArkUI nodes. */
  onCandidateWidth: ((widthVp: number) => void) | undefined = undefined;
  /** The native host owns panel geometry; the touch view reports its newly requested total height. */
  onTouchHeight: ((heightVp: number) => void) | undefined = undefined;
  /**
   * Whether a composition is open, for the host that owns the panel.
   *
   * A candidate window has nothing to say when nothing is being spelled, and the framework does not
   * show or hide one on its own, so the ability needs to hear about the transitions. The view has
   * onChanged; this is the same news for the other reader, and fires only when the answer changes.
   */
  onComposition: ((active: boolean) => void) | undefined = undefined;
  /** The mode badge's face, set by whichever window is currently drawing it. */
  onModeBadge: ((english: boolean, dark: boolean) => void) | undefined = undefined;
  /** The toolbar's face, set by whichever window is currently drawing it. */
  onToolbar: ((state: ToolbarState, buttons: ToolbarButton[], fontSize: number, scale: number,
               skin: KeyboardSkin, toolbarSkin: ToolbarSkin) => void) | undefined = undefined;
  /** The status-bar panel owns the window; the ArkUI handle only reports its pan gesture. */
  onToolbarDragStart: (() => void) | undefined = undefined;
  onToolbarDrag: ((offsetX: number, offsetY: number) => void) | undefined = undefined;
  /** The gear, which only the host can answer: it owns the window the settings open in. */
  onToolbarSettings: (() => void) | undefined = undefined;
  /**
   * A surface the toolbar asked for, which two readers need and for different reasons: the host
   * sizes and shows the window, the view draws what goes in it. Two slots rather than one, the way
   * onChanged and onComposition are already split, because a single slot silently keeps whichever
   * listener registered last — and the window then resizes around a face that was never drawn.
   */
  onSurfaceRequested: ((surface: DesktopSurface) => void) | undefined = undefined;
  onSurfaceChanged: ((surface: DesktopSurface) => void) | undefined = undefined;
  private desktopSurface: DesktopSurface = DesktopSurface.NONE;
  private composedLast: boolean = false;
  /** The editor's traits arrive after inputStart, so the view is told when they do. */
  onEditorChanged: (() => void) | undefined = undefined;
  /** Clears reply results when the focused editor or its cursor context changes. */
  onReplyContextChanged: (() => void) | undefined = undefined;
  /** Putting the keyboard away belongs to the panel, which the view has no handle on. */
  onDismiss: (() => void) | undefined = undefined;

  /**
   * True once the native ABI matches and a session exists.
   *
   * The options are not written here. prepareHost verifies the staged dictionary against the pinned
   * lock, lays out the derived state under the state root, and returns the document create expects;
   * a hand-written one would drift from the lock the moment the dictionary is republished.
   */
  private readCandidateSkinCatalog(stateRoot: string): CandidateSkinPackage[] {
    try {
      const response: SkinCatalogResponse =
        JSON.parse(client.skinCatalog(`${stateRoot}/skins`)) as SkinCatalogResponse;
      if (!response.ok || response.value === undefined || !Array.isArray(response.value.packages)) {
        return [];
      }
      return response.value.packages;
    } catch (error) {
      KeyboardLog.error(`candidate skin catalog unavailable: ${describeError(error)}`);
      return [];
    }
  }

  private readCandidateSkinImage(stateRoot: string, id: string,
                                 decoration: CandidateSkinDecoration | null): CandidateSkinImage {
    if (decoration === null) {
      return NO_CANDIDATE_SKIN_IMAGE;
    }
    try {
      const request: SkinResourceRequest = {
        directory: `${stateRoot}/skins`, id: id, relative: decoration.relative, kind: 'image'
      };
      const response: SkinResourceResponse =
        JSON.parse(client.skinResource(JSON.stringify(request))) as SkinResourceResponse;
      if (!response.ok || response.value === undefined) {
        return NO_CANDIDATE_SKIN_IMAGE;
      }
      const image: CandidateSkinImage = {
        image: CandidateSkinCatalogPolicy.imageDataUrl(response.value.contentType,
          response.value.bytes),
        aspectRatio: CandidateSkinCatalogPolicy.imageAspectRatio(response.value.contentType,
          response.value.bytes)
      };
      return image;
    } catch (error) {
      KeyboardLog.error(`candidate skin decoration unavailable: ${describeError(error)}`);
      return NO_CANDIDATE_SKIN_IMAGE;
    }
  }

  private readCandidateSkinToolbar(stateRoot: string, id: string,
                                    stylesheet: string | null): string | null {
    if (stylesheet === null || !KeyboardFormFactor.isDesktop()) {
      return null;
    }
    try {
      const response: SkinToolbarStylesheetResponse = JSON.parse(client.skinToolbarStylesheet(
        JSON.stringify({ directory: `${stateRoot}/skins`, id: id }))) as SkinToolbarStylesheetResponse;
      return response.ok && typeof response.value === 'string' ? response.value : null;
    } catch (error) {
      KeyboardLog.error(`candidate skin toolbar unavailable: ${describeError(error)}`);
      return null;
    }
  }

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
    this.systemDark = systemDark;
    this.feedbackSettings = this.feedback();
    const request: PrepareRequest = { resources: resources, state_root: stateRoot };
    let options: string;
    try {
      const prepared: PrepareResponse =
        JSON.parse(client.prepareHost(JSON.stringify(request))) as PrepareResponse;
      if (!prepared.ok) {
        KeyboardLog.error(`host preparation refused: ${prepared.error}`);
        return false;
      }
      const requested: PreparedOptions = prepared.value;
      requested.phrase_preedit = true;
      options = JSON.stringify(requested);
      const preferences: PreparedPreferences = prepared.value.preferences;
      this.clipboardHistoryEnabled = ClipboardHistoryPreferencePolicy.enabled(
        preferences.clipboard_history);
      this.wubiCodeHint = CandidateAnnotationPreferencePolicy.wubiCodeHint(
        preferences.wubi_code_hint);
      this.candidateEnglishGloss = CandidateAnnotationPreferencePolicy.englishGloss(
        preferences.candidate_english_gloss);
      this.modeBadge = InputModeHudPolicy.enabled(preferences.input_mode_hud);
      this.englishSuggestionsEnabled = preferences.english_suggestions !== false;
      if (ClipboardHistoryPreferencePolicy.shouldClearHistory(this.clipboardHistoryEnabled)) {
        this.clearClipboardHistoryFile();
      }
      if (this.onClipboardHistoryChanged !== undefined) {
        this.onClipboardHistoryChanged(this.clipboardHistoryEnabled);
      }
      const skinPackages: CandidateSkinPackage[] = this.readCandidateSkinCatalog(stateRoot);
      const candidateDark: boolean = KeyboardSkin.resolveDark(preferences.candidate_theme,
        preferences.theme, systemDark);
      const candidateTheme: string = candidateDark ? 'dark' : 'light';
      const skinSupported: boolean = CandidateSkinCatalogPolicy.supports(
        skinPackages, preferences.candidate_skin, preferences.candidate_layout, candidateTheme);
      const skinPalette: CandidateSkinPaletteTokens | null = CandidateSkinCatalogPolicy.palette(
        skinSupported ? skinPackages : [], preferences.candidate_skin, candidateDark);
      const skinBase: string | null = CandidateSkinCatalogPolicy.base(
        skinSupported ? skinPackages : [], preferences.candidate_skin);
      const skinMinWidth: number | null = CandidateSkinCatalogPolicy.minWidthVp(
        skinSupported ? skinPackages : [], preferences.candidate_skin);
      const skinSelectedBar: boolean | null = CandidateSkinCatalogPolicy.showSelectedBar(
        skinSupported ? skinPackages : [], preferences.candidate_skin, candidateDark);
      const skinDecoration: CandidateSkinDecoration | null = CandidateSkinCatalogPolicy.decoration(
        skinSupported ? skinPackages : [], preferences.candidate_skin);
      const skinToolbar: string | null = this.readCandidateSkinToolbar(stateRoot,
        preferences.candidate_skin, CandidateSkinCatalogPolicy.toolbarStylesheet(
          skinSupported ? skinPackages : [], preferences.candidate_skin));
      const skinImage: CandidateSkinImage = KeyboardFormFactor.isDesktop()
        ? this.readCandidateSkinImage(stateRoot, preferences.candidate_skin, skinDecoration)
        : NO_CANDIDATE_SKIN_IMAGE;
      this.voiceInput = preferences.voice_input;
      this.voiceHotkeys.use(KeyboardSession.hotkeyBindings(preferences.voice_input));
      this.customSkinDesign = CustomKeyboardSkin.from(preferences.custom_touch_keyboard_skin ?? null);
      if (this.onVoiceInputChanged !== undefined) {
        this.onVoiceInputChanged(this.voiceInputEnabled());
      }
      this.aiAssistant = preferences.ai_assistant;
      this.defaultEnglish = preferences.default_ime_mode === 'english';
      this.modeScopeSetting = preferences.ime_mode_scope === 'global' ? 'global' : 'app';
      this.englishMode = this.defaultEnglish;
      this.bindings = {
        switchLanguageShift: preferences.keybindings.switch_language_shift,
        switchLanguageCtrl: preferences.keybindings.switch_language_ctrl,
        switchLanguageCtrlAltSpace: preferences.keybindings.switch_language_ctrl_alt_space,
        toggleCharacterSetCtrlShiftF: preferences.keybindings.toggle_character_set_ctrl_shift_f
      };
      this.appearance = {
        // The keyboard's own theme wins, then the global one, and only if both defer does the
        // system decide. resolveDark is the ported rule every other host already follows.
        dark: KeyboardSkin.resolveDark(preferences.screen_keyboard_theme, preferences.theme,
          systemDark),
        skinId: preferences.touch_keyboard_skin,
        candidateSkinId: preferences.candidate_skin,
        candidateSkinBase: skinBase ?? preferences.candidate_skin,
        candidateMinWidthVp: skinMinWidth === null
          ? CandidateWidthPolicy.MIN_WIDTH_VP
          : Math.max(CandidateWidthPolicy.MIN_WIDTH_VP,
            Math.min(CandidateWidthPolicy.MAX_WIDTH_VP, skinMinWidth)),
        candidateDecorationImage: skinImage.image,
        candidateDecorationTopVp: skinImage.image === null ? 0 : (skinDecoration?.topVp ?? 0),
        candidateDecorationWidthVp: skinImage.image === null ? 0 : (skinDecoration?.widthVp ?? 0),
        candidateDecorationAspectRatio: skinImage.aspectRatio,
        candidateDark: candidateDark,
        candidateSelectedBar: preferences.candidate_selected_bar ?? skinSelectedBar,
        pairedPunctuation: preferences.paired_punctuation !== false,
        keyboardTheme: preferences.screen_keyboard_theme,
        toolbarTheme: preferences.toolbar_theme ?? 'follow',
        voiceTheme: preferences.voice_theme ?? 'follow',
        emojiTheme: preferences.emoji_theme ?? 'follow',
        handwritingTheme: preferences.handwriting_theme ?? 'follow',
        globalTheme: preferences.theme,
        scheme: preferences.scheme,
        shuangpinProfile: preferences.shuangpin_profile,
        layout: preferences.touch_keyboard_layout,
        selectedScheme: preferences.touch_keyboard_schemes?.selected ?? null,
        enabledSchemes: preferences.touch_keyboard_schemes?.enabled === undefined
          ? KeyboardScheme.SCHEMES.map((candidate: SchemeDefinition): string => candidate.preferenceId)
          : KeyboardScheme.enabledFromPreferenceIds(preferences.touch_keyboard_schemes.enabled)
            .map((candidate: SchemeDefinition): string => candidate.preferenceId),
        candidateFollowCursor: preferences.candidate_follow_cursor,
        numberRowSelection: preferences.number_row_selection,
        candidateShowPreedit: preferences.candidate_preedit_style !== 'empty',
        candidateLayout: preferences.candidate_layout === 'horizontal' ? 'horizontal' : 'vertical',
        navigation: {
          minusEqual: preferences.navigation?.minus_equal ?? true,
          commaPeriod: preferences.navigation?.comma_period ?? true,
          brackets: preferences.navigation?.brackets ?? false,
          tab: preferences.navigation?.tab ?? true,
          pageUpDown: preferences.navigation?.page_up_down ?? true,
          mouseWheel: preferences.navigation?.mouse_wheel ?? false,
          arrows: preferences.navigation?.arrows ?? true
        },
        // The shared store validates these to 12..32 and strips control
        // characters from family names. Clamp again at the host boundary so
        // an older staged document cannot produce an unusable panel.
        candidateFontSize: Math.max(12, Math.min(32, preferences.candidate_font_size)),
        candidatePreeditFontSize:
          Math.max(12, Math.min(32, preferences.candidate_preedit_font_size)),
        candidateFontFamily: preferences.candidate_font_family.trim().length > 0
          ? preferences.candidate_font_family : 'Noto Sans SC',
        candidateEnglishFont: preferences.candidate_english_font ?? null,
        candidateFallbackFonts: preferences.candidate_fallback_fonts.filter(
          (font: string): boolean => font.trim().length > 0),
        candidateTextColor: preferences.candidate_text_color ?? skinPalette?.text ?? null,
        candidateAccentColor: preferences.candidate_accent_color ?? skinPalette?.accent ?? null,
        candidateNumberColor: preferences.candidate_number_color ?? skinPalette?.number ?? null,
        candidateSelectedColor: preferences.candidate_selected_color ?? skinPalette?.selected ?? null,
        candidateHoverColor: preferences.candidate_hover_color ?? skinPalette?.hover ?? null,
        candidateSurfaceColor: preferences.candidate_surface_color ?? skinPalette?.surface ?? null,
        candidateBorderColor: preferences.candidate_border_color ?? skinPalette?.border ?? null,
        // Clamped rather than trusted: the store validates, but an older document or a host that
        // never learned the bounds would otherwise draw a keyboard nobody can hit.
        keySpacingTenths: KeyboardGeometry.keySpacing(preferences.touch_key_spacing_tenths),
        rowSpacingTenths: KeyboardGeometry.rowSpacing(preferences.touch_row_spacing_tenths),
        heightAdjustment:
          KeyboardGeometry.heightAdjustment(preferences.touch_keyboard_height_adjustment),
        voiceShortcut: preferences.touch_voice_shortcut,
        thoughtfulReply: preferences.touch_keyboard_schemes?.selected === 'thoughtful_reply'
      };
      this.toolbarSkin = ToolbarSkinPolicy.fromCss(
        this.skin(this.appearance.skinId,
          KeyboardSkin.resolveDark(this.appearance.toolbarTheme, this.appearance.globalTheme,
            systemDark)), skinToolbar);
      this.schemeName = preferences.scheme;
      this.profileName = preferences.shuangpin_profile;
      this.traditional = preferences.traditional_chinese_output;
      this.chinesePunctuation = preferences.chinese_punctuation;
      this.smartPunctuation = preferences.smart_punctuation !== false;
      this.smartPunctuationRepeat = preferences.smart_punctuation_repeat !== false;
      this.smartPunctuationSpaceConvert = preferences.smart_punctuation_space_convert === true;
      this.punctuationLock = preferences.punctuation_lock;
      this.wordCharacter = preferences.word_character.enabled
        ? preferences.word_character.keys : 'disabled';
      this.clearSmartPunctuationRepeat();
      this.toolbar = preferences.floating_toolbar;
      this.nineKeyMode = preferences.touch_keyboard_layout === 'nine_key'
        && preferences.scheme === 'quanpin';
    } catch (error) {
      KeyboardLog.error(`host preparation unreadable: ${describeError(error)}`);
      return false;
    }
    // Before the session exists and after the options are known: dictionary maintenance takes an
    // exclusive lock that a live session's shared lock would block, so this is the one moment in
    // the keyboard's life when queued personal-dictionary edits can actually be applied. A failure
    // is not a reason to refuse to start — the queue keeps its entries and the next start retries.
    this.drainPersonalDictionary(options);
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

  /**
   * Applies whatever the settings window queued for the personal dictionary.
   *
   * Words imported from a file cannot be written when they are chosen: the settings window has no
   * way to take the Engine's maintenance lock while this process is holding a session, and telling
   * the user "busy" would make importing a file depend on whether they happened to have the
   * keyboard open. They are queued instead, and this is where the queue is paid.
   *
   * Everything here is best effort. The store keeps entries it could not apply, so a failure costs
   * a delay rather than the import; refusing to start the keyboard over it would turn a dictionary
   * problem into no keyboard at all.
   */
  private drainPersonalDictionary(options: string): void {
    try {
      const reply: Record<string, Object> =
        JSON.parse(client.personalDictionarySync(options)) as Record<string, Object>;
      if (reply['ok'] !== true) {
        KeyboardLog.error('personal dictionary queue not applied; it will be retried');
      }
    } catch (error) {
      KeyboardLog.error(`personal dictionary queue unavailable: ${describeError(error)}`);
    }
  }

  /** Whether the Engine's output is being converted to traditional. */
  usesTraditional(): boolean {
    return this.traditional;
  }

  /** What the user chose for the keyboard's appearance and scheme. */
  preferences(): KeyboardPreferences {
    return this.appearance;
  }

  /** Resolve a touch-keyboard skin with the shared custom design when selected. */
  skin(id: string, dark: boolean): KeyboardSkin {
    return KeyboardSkin.from(id, dark, id === 'custom' ? this.customSkinDesign : null);
  }

  /** The built-ins plus the current shared custom design for the native picker. */
  keyboardSkins(dark: boolean): KeyboardSkin[] {
    return KeyboardSkin.choices(dark, this.customSkinDesign);
  }

  /** Whether the shared privacy preference permits this host's private history file. */
  clipboardHistoryAllowed(): boolean {
    return ClipboardHistoryPreferencePolicy.canReadOrWrite(this.clipboardHistoryEnabled);
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

  /**
   * Turns the platform's capitalize mode into the one the policy reasons about.
   *
   * Same reason traitsFor exists: the enumeration belongs to the runtime. It is optional in the
   * attribute, and an editor that does not declare one is asking for nothing, which is also what a
   * value this build has no name for means — the keyboard leaves the case alone rather than guessing.
   */
  private static capitalizationFor(
    mode: inputMethodEngine.CapitalizeMode | undefined): CapitalizationMode {
    if (mode === inputMethodEngine.CapitalizeMode.SENTENCES) {
      return CapitalizationMode.SENTENCES;
    }
    if (mode === inputMethodEngine.CapitalizeMode.WORDS) {
      return CapitalizationMode.WORDS;
    }
    if (mode === inputMethodEngine.CapitalizeMode.CHARACTERS) {
      return CapitalizationMode.ALL_CHARACTERS;
    }
    return CapitalizationMode.NONE;
  }

  /**
   * Whether the next English letter should arrive shifted.
   *
   * Two questions, both already ported and neither previously asked: what the editor wants, which
   * EditorPolicy reconciles with the kind of field it is — an address is never capitalized whatever
   * the platform says — and whether the text already there puts the caret at the start of a word or
   * a sentence. Only English has a case to shift; Chinese composition has none, and asking while the
   * Engine is composing would capitalize the pinyin rather than the result.
   */
  /**
   * Whether this editor asks for automatic capitals at all.
   *
   * Separate from the question below because false here means do nothing, not shift nothing: an
   * editor that wants no capitals has said nothing about the Shift the user pressed, and clearing it
   * on their behalf would drop a capital they asked for.
   */
  capitalizes(): boolean {
    return this.englishMode && this.capitalization !== CapitalizationMode.NONE;
  }

  shouldShiftNextLetter(): boolean {
    if (!this.englishMode || this.capitalization === CapitalizationMode.NONE) {
      return false;
    }
    if (this.capitalization === CapitalizationMode.ALL_CHARACTERS) {
      return true;
    }
    if (this.inputClient === undefined || this.editing.length > 0) {
      return false;
    }
    let context: string = '';
    try {
      context = this.inputClient.getForwardSync(MAX_CAPITALIZATION_CONTEXT_CHARACTERS);
    } catch (error) {
      // Without the text before the caret there is no way to tell a sentence start from the middle
      // of one, and shifting on a guess is the more visible mistake.
      KeyboardLog.error(`editor capitalization context unavailable: ${describeError(error)}`);
      return false;
    }
    return EnglishCapitalizationPolicy.shouldShift(this.capitalization, context);
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

  /**
   * Whether a gloss is expected under the candidates, which is a setting rather than an arrival.
   *
   * The strip reserves room by this and not by whether an answer has come back: the networked ones
   * land over a few hundred milliseconds, and a width that follows them widens one chip at a time
   * and pushes the rest along. Off means no room is kept and the chips are as wide as their words.
   */
  glossesExpected(): boolean {
    return this.candidateEnglishGloss;
  }

  /** True when the Engine is composing English rather than Chinese. */
  isEnglish(): boolean {
    return this.englishMode;
  }

  /** True when the editor now attached needs the full letter face instead of a nine-key grid. */
  prefersFullFace(): boolean {
    return EditorPolicy.prefersFullFace(this.traits);
  }

  /** Japanese romaji owns the unmodified hardware minus key; temporary R mode does not. */
  isJapanese(): boolean {
    return !this.englishMode && this.schemeName === 'japanese';
  }

  /** Which mode-switch gestures the user left bound, as the shared document has them. */
  modeBindings(): ModeBindings {
    return this.bindings;
  }

  /** Which unmodified hardware pair selects the first/last Han character. */
  wordCharacterBinding(): string {
    return this.wordCharacter;
  }

  /**
   * Chinese punctuation or ASCII, which the toolbar button and the Windows Ctrl+. binding share.
   *
   * Written as a preference rather than as a live session mode because that is how this host has
   * always changed it: the same value drives the toolbar face and the settings page, and two
   * mechanisms for one switch is how they come to disagree.
   */
  togglePunctuation(): boolean {
    this.chinesePunctuation = !this.chinesePunctuation;
    this.clearSmartPunctuationRepeat();
    this.writePreference('chinese_punctuation', this.chinesePunctuation);
    return this.chinesePunctuation;
  }

  /** Halfwidth ASCII or its fullwidth twin, which Ctrl+Shift+F toggles. */
  toggleCharacterWidth(): boolean {
    if (this.handle === 0) {
      return this.fullWidth;
    }
    this.applyView(client.setCharacterWidth(this.handle, !this.fullWidth));
    return this.fullWidth;
  }

  /** Whether the user wants a toolbar at all, and how big. */
  toolbarEnabled(): boolean {
    return this.toolbar.enabled;
  }

  toolbarScale(): number {
    return FloatingToolbarLayout.scale(this.toolbar.scale_percent / 100);
  }

  toolbarFontSize(): number {
    return FloatingToolbarLayout.fontSize(this.toolbar.font_size);
  }

  /** Whether the shared preference permits the badge shown after a Chinese/English switch. */
  modeBadgeEnabled(): boolean {
    return this.modeBadge;
  }

  toolbarComponents(): ToolbarComponents {
    return {
      englishMode: this.toolbar.english_mode, punctuation: this.toolbar.punctuation,
      fullwidth: this.toolbar.fullwidth, characterSet: this.toolbar.character_set,
      emoji: this.toolbar.emoji, screenKeyboard: this.toolbar.screen_keyboard,
      settings: this.toolbar.settings !== false
    };
  }

  /** Push the toolbar's face to whichever window is drawing it. */
  refreshToolbar(): void {
    if (this.onToolbar === undefined) {
      return;
    }
    const state: ToolbarState = {
      english: this.englishMode,
      temporaryEnglish: this.localMode === 'temporary_english',
      japanese: !this.englishMode && this.schemeName === 'japanese',
      capsLock: this.capsLock,
      chinesePunctuation: this.chinesePunctuation,
      fullWidth: this.fullWidth, traditional: this.traditional
    };
    this.onToolbar(state, FloatingToolbarLayout.buttons(this.toolbarComponents()),
      this.toolbarFontSize(), this.toolbarScale(),
      this.skin(this.appearance.skinId, this.appearance.dark), this.toolbarSkin);
  }

  beginToolbarDrag(): void {
    if (this.onToolbarDragStart !== undefined) {
      this.onToolbarDragStart();
    }
  }

  setCapsLock(enabled: boolean): void {
    if (this.capsLock === enabled) {
      return;
    }
    this.capsLock = enabled;
    this.refreshToolbar();
  }

  dragToolbar(offsetX: number, offsetY: number): void {
    if (this.onToolbarDrag !== undefined) {
      this.onToolbarDrag(offsetX, offsetY);
    }
  }

  /**
   * What a toolbar button does.
   *
   * The three that are preferences are written back to the document as well as applied, because they
   * are the same three the settings page shows: a toolbar that changed them only for this session
   * would disagree with the page the moment either was looked at.
   */
  runToolbarButton(button: ToolbarButton): void {
    switch (button) {
      case ToolbarButton.INPUT_MODE:
        this.toggleLanguage();
        break;
      case ToolbarButton.PUNCTUATION:
        this.togglePunctuation();
        break;
      case ToolbarButton.FULL_WIDTH:
        this.toggleCharacterWidth();
        break;
      case ToolbarButton.CHARACTER_SET:
        this.traditional = !this.traditional;
        this.writePreference('traditional_chinese_output', this.traditional);
        break;
      case ToolbarButton.EMOJI:
        this.requestSurface(DesktopSurface.EMOJI);
        break;
      case ToolbarButton.SCREEN_KEYBOARD:
        this.requestSurface(DesktopSurface.SCREEN_KEYBOARD);
        break;
      default:
        if (this.onToolbarSettings !== undefined) {
          this.onToolbarSettings();
        }
        break;
    }
    this.refreshToolbar();
  }

  /** One value, through the same store the settings page writes, revision check and all. */
  private writePreference(key: string, value: Object): void {
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set(key, value);
    this.changePreferences(changes);
  }

  /**
   * Ask for a surface that is not the candidate list.
   *
   * On a phone these are opened from the keyboard's own key faces. A desktop has none, so the
   * toolbar asks instead, and the host decides which window it goes in and how big it has to be.
   * Asking for the one already open closes it, the way tapping its icon does on the keyboard.
   */
  private requestSurface(surface: DesktopSurface): void {
    this.desktopSurface = this.desktopSurface === surface ? DesktopSurface.NONE : surface;
    // The view first: the window is sized around what it drew, so drawing it second would leave one
    // frame of a keyboard-sized window with a candidate strip in it.
    if (this.onSurfaceChanged !== undefined) {
      this.onSurfaceChanged(this.desktopSurface);
    }
    if (this.onSurfaceRequested !== undefined) {
      this.onSurfaceRequested(this.desktopSurface);
    }
  }

  /** Which of them is open, for the view that has to draw it. */
  openSurface(): DesktopSurface {
    return this.desktopSurface;
  }

  /** Tell whichever window is drawing the mode badge what to put on it. */
  setModeBadge(english: boolean): void {
    if (this.onModeBadge !== undefined) {
      this.onModeBadge(english, this.appearance.dark);
    }
  }

  /** Whether something is being spelled right now, which decides who a physical key belongs to. */
  composing(): boolean {
    return this.editing.length > 0;
  }

  /** Tells the Engine which grid the user is typing on, so a 2 means ABC rather than a digit. */
  /** The scheme now in force, which decides whether the nine-key flag means anything. */
  useScheme(name: string, profileName: string | null = null): void {
    this.schemeName = name;
    if (profileName !== null) {
      this.profileName = profileName;
    }
    // Scheme changes happen from the keyboard's own picker as well as the desktop toolbar. Keep
    // the persistent toolbar's language face in sync before the next key or button action.
    this.refreshToolbar();
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
    this.finishCompositionBoundary(CompositionBoundary.MODE_SWITCH);
    this.englishMode = !this.englishMode;
    this.manualLanguageGeneration = this.editorGeneration;
    // The user asked for this one, so it is the choice this application is remembered by.
    this.modeScope.remember(this.englishMode);
    this.applyView(client.setEnglishMode(this.handle, this.englishMode));
    return this.englishMode;
  }

  /** What this editor asked its return key to do, in the shared editor-action numbering. */
  returnAction(): number {
    return this.enterKey;
  }

  /** Ask the host to put the keyboard away, committing whatever was being composed first. */
  dismiss(): void {
    this.finishCompositionBoundary(CompositionBoundary.DEACTIVATE);
    if (this.onDismiss !== undefined) {
      this.onDismiss();
    }
  }

  private finishCompositionBoundary(boundary: CompositionBoundary): void {
    const action: CompositionBoundaryAction = CompositionBoundaryPolicy.action(
      this.composing(), this.schemeName === 'japanese', boundary);
    if (action === CompositionBoundaryAction.FINISH_COMPOSITION) {
      this.finishComposition();
    } else if (action === CompositionBoundaryAction.COMMIT_RAW) {
      this.commitRaw();
    }
  }

  /**
   * What Return does when no composition took it first.
   *
   * One call covers both halves here. Android splits them — performEditorAction for GO, SEARCH and
   * the rest, a committed newline otherwise — and the ported ReturnKeyAction is that split. On this
   * platform sendKeyFunction takes the enter key type itself and the framework does the right thing
   * with every value, ENTER_KEY_TYPE_NEW_LINE included. Measured, not assumed: replacing this with
   * the split put insertText("\n") into a WebView textarea that ignored it, and the same key with
   * the same editor (enter=8) had produced a newline the moment before.
   */
  submit(): void {
    if (this.inputClient !== undefined) {
      this.inputClient.sendKeyFunction(this.enterKey);
    }
  }

  /** Begin one host-independent voice generation, so late platform callbacks can be rejected. */
  voiceStart(): number {
    if (this.handle === 0 || !this.voiceInputEnabled()) {
      return 0;
    }
    try {
      const response: VoiceGenerationResponse = JSON.parse(client.voiceStart(this.handle)) as VoiceGenerationResponse;
      return response.ok && Number.isSafeInteger(response.value) && response.value > 0
        ? response.value : 0;
    } catch (error) {
      KeyboardLog.error(`voice session unavailable: ${describeError(error)}`);
      return 0;
    }
  }

  voiceInputConfiguration(): VoiceInputConfiguration {
    return this.voiceInput;
  }

  /**
   * The text before the caret, as the polish panel's starting point.
   *
   * Apple polishes the selection; HarmonyOS gives an input method no way to read one, so this host
   * offers what it can read instead. See `AiPolishPolicy` for why that is the same intent rather
   * than a lesser one.
   */
  polishSource(): string {
    if (this.inputClient === undefined || this.composing()) return '';
    try {
      return AiPolishPolicy.source(this.inputClient.getForwardSync(MAX_POLISH_SOURCE_CHARACTERS));
    } catch (error) {
      KeyboardLog.error(`polish source unavailable: ${describeError(error)}`);
      return '';
    }
  }

  /** Whether a polish provider is configured, which is what decides if the entry is offered. */
  polishConfigured(): boolean {
    const config: VoiceInputConfiguration = this.voiceInput;
    const provider: string = (config.polish_provider ?? '').trim();
    return provider.length > 0;
  }

  /**
   * Rewrites one piece of text through this host's polisher.
   *
   * The polisher is the one the voice path already uses. It is the right one and not merely a
   * convenient one: it allows the newlines a rewritten paragraph contains, where the AI candidate
   * parser beside it rejects every control character — that parser is for candidate words, and
   * sending a rewritten message through it would silently drop every multi-line answer.
   *
   * Returns null rather than throwing. Every failure here is "no rewrite to show", and the panel
   * has one sentence for that; distinguishing a refused endpoint from a timed-out one would give
   * the user nothing they could act on differently.
   */
  async polish(text: string): Promise<string | null> {
    if (text.length === 0) return null;
    const generation: number = this.editorGeneration;
    const result: string | null = await this.polisher.polish(this.voiceInput, text);
    // The editor may have moved while the model was writing. A rewrite of text that is no longer
    // there is not a result, and offering it would invite the user to replace the wrong thing.
    if (generation !== this.editorGeneration) return null;
    return result !== null && AiPolishPolicy.usable(text, result) ? result : null;
  }

  /**
   * Puts a rewrite in place of the text it was made from.
   *
   * The text before the caret is read again here rather than trusted from when the panel opened:
   * a polish request takes seconds, and anything typed in the meantime would otherwise be deleted
   * and replaced by the rewrite of something else. A mismatch is refused and reported.
   */
  applyPolish(source: string, result: string): boolean {
    if (this.inputClient === undefined || this.composing()) return false;
    let current: string;
    try {
      current = this.inputClient.getForwardSync(MAX_POLISH_SOURCE_CHARACTERS);
    } catch (error) {
      KeyboardLog.error(`polish target unreadable: ${describeError(error)}`);
      return false;
    }
    const replacement: PolishReplacement | null =
      AiPolishPolicy.replacement(source, result, current);
    if (replacement === null) return false;
    try {
      this.deleteEditorBackwardSync(replacement.deleteCount);
    } catch (error) {
      KeyboardLog.error(`polish could not replace the text: ${describeError(error)}`);
      return false;
    }
    this.insertWithSource(replacement.insert, 'ai');
    return true;
  }

  voiceInputEnabled(): boolean {
    return VoiceInputConfigurationPolicy.enabled(this.voiceInput.enabled);
  }

  voiceCancel(): void {
    if (this.handle === 0) {
      return;
    }
    try {
      client.voiceCancel(this.handle);
    } catch (error) {
      KeyboardLog.error(`voice cancellation unavailable: ${describeError(error)}`);
    }
  }

  /** Accept only the active generation and never log the recognized text. */
  voiceApply(generation: number, text: string): string | null {
    if (this.handle === 0 || generation <= 0 || text.length === 0) {
      return null;
    }
    try {
      const response: VoiceTextResponse = JSON.parse(client.voiceApply(this.handle, generation, text)) as VoiceTextResponse;
      return response.ok ? response.value : null;
    } catch (error) {
      KeyboardLog.error(`voice result unavailable: ${describeError(error)}`);
      return null;
    }
  }

  /** The framework hands over a fresh client on every inputStart. */
  attach(inputClient: inputMethodEngine.InputClient): void {
    const editorGeneration: number = ++this.editorGeneration;
    this.pendingOwnEdits = 0;
    this.invalidateReplyContext();
    this.clearSmartPunctuationRepeat();
    this.inputClient = inputClient;
    inputClient.getEditorAttribute().then((attribute: inputMethodEngine.EditorAttribute): void => {
      if (editorGeneration !== this.editorGeneration || this.inputClient !== inputClient) {
        return;
      }
      this.enterKey = attribute.enterKeyType;
      this.traits = KeyboardSession.traitsFor(attribute.inputPattern);
      this.capitalization = EditorPolicy.capitalizationMode(this.traits,
        KeyboardSession.capitalizationFor(attribute.capitalizeMode));
      // Says the keyboard reached a real editor, which nothing else in the log does. Verifying that
      // on a device meant reading the window manager's avoid-area traffic to infer it.
      KeyboardLog.info(`attached to editor: pattern=${attribute.inputPattern} `
        + `enter=${attribute.enterKeyType} capitalize=${this.capitalization}`);
      // Which application this editor belongs to, so the mode can be the one last chosen there.
      // Resolved with the attribute rather than at attach: the bundle name arrives with it.
      this.modeScope.activate(attribute.bundleName ?? null, this.modeScopeSetting);
      // A password field must never see a composition buffer, and a field that asked for no
      // suggestions has said it does not want one. Latin for an address, where Chinese would only
      // be in the way. That override is the editor's, not the user's, so it is never remembered.
      const english: boolean =
        this.modeScope.mode(this.defaultEnglish) || EditorPolicy.prefersLatin(this.traits);
      if (this.handle !== 0 && EditorPolicy.appliesDelayedLanguage(
        this.composing(), this.englishMode, english,
        this.manualLanguageGeneration === editorGeneration)) {
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
    this.editorGeneration++;
    this.manualLanguageGeneration = -1;
    this.pendingOwnEdits = 0;
    this.modeScope.deactivate();
    this.clearEnglishSuggestions();
    this.invalidateReplyContext();
    this.clearSmartPunctuationRepeat();
    this.cancelOnlineProviders();
    if (this.handle !== 0) {
      // Runtime focus(false) cancels whatever remains. Finish first while the old editor client is
      // still attached, so changing fields cannot silently discard what the user just typed.
      this.finishCompositionBoundary(CompositionBoundary.DEACTIVATE);
      this.apply(client.focus(this.handle, false));
    }
    this.inputClient = undefined;
  }

  stop(): void {
    this.editorGeneration++;
    this.pendingOwnEdits = 0;
    this.invalidateReplyContext();
    this.clearSmartPunctuationRepeat();
    this.cancelOnlineProviders();
    if (this.handle !== 0) {
      client.destroy(this.handle);
      this.handle = 0;
    }
  }

  /** Invalidate host-side network work before the focused editor changes or the session dies. */
  private cancelOnlineProviders(): void {
    this.onlineEpoch++;
    this.onlineSignature = '';
    if (this.onlineTimer >= 0) {
      clearTimeout(this.onlineTimer);
      this.onlineTimer = -1;
    }
    this.translationEpoch++;
    this.translationSignature = '';
    if (this.translationTimer >= 0) {
      clearTimeout(this.translationTimer);
      this.translationTimer = -1;
    }
  }

  /** Invalidate asynchronous reply work without logging or retaining editor text. */
  invalidateReplyContext(): void {
    this.replyContextGeneration++;
    this.replyResultEditorGeneration = -1;
    this.replyResultContextGeneration = -1;
    this.replyResultTexts = [];
    if (this.onReplyContextChanged !== undefined) {
      this.onReplyContextChanged();
    }
  }

  /** Resize only the phone/tablet soft-keyboard panel; desktop surfaces have separate geometry. */
  resizeTouchKeyboard(heightVp: number): void {
    if (!KeyboardFormFactor.isDesktop() && this.onTouchHeight !== undefined) {
      this.onTouchHeight(heightVp);
    }
  }

  /** Reconcile a document mutation reported by the editor with keyboard-owned edit echoes. */
  editorTextChanged(): void {
    this.invalidateReplyContext();
    if (!EditorPolicy.isExternalTextChange(this.pendingOwnEdits)) {
      this.pendingOwnEdits--;
      if (this.onEditorChanged !== undefined) {
        this.onEditorChanged();
      }
      return;
    }
    // A host edit may clear the field, replace the document or move text around the active
    // composition. Commit what the user typed before the Engine's state can drift from the editor.
    this.finishCompositionBoundary(CompositionBoundary.DEACTIVATE);
    this.clearEnglishSuggestions();
    this.clearSmartPunctuationRepeat();
    this.clearSmartPunctuationSpace();
    if (this.onEditorChanged !== undefined) {
      this.onEditorChanged();
    }
  }

  /** A selection move changes contextual UI but does not itself discard an active composition. */
  editorSelectionChanged(): void {
    this.invalidateReplyContext();
    this.clearEnglishSuggestions();
    if (this.onEditorChanged !== undefined) {
      this.onEditorChanged();
    }
  }

  /** Insert through the editor while reserving the asynchronous text-change echo it produces. */
  private insertEditorText(text: string): void {
    const inputClient: inputMethodEngine.InputClient | undefined = this.inputClient;
    if (inputClient === undefined) return;
    const generation: number = this.editorGeneration;
    this.pendingOwnEdits++;
    inputClient.insertText(text).catch((error: Object): void => {
      if (generation === this.editorGeneration && this.inputClient === inputClient
          && this.pendingOwnEdits > 0) {
        this.pendingOwnEdits--;
      }
      KeyboardLog.error(`editor insertion unavailable: ${describeError(error)}`);
    });
  }

  /** Synchronous insert variant for an atomic read/replace editor operation. */
  private insertEditorTextSync(text: string): void {
    if (this.inputClient === undefined) return;
    this.pendingOwnEdits++;
    try {
      this.inputClient.insertTextSync(text);
    } catch (error) {
      this.pendingOwnEdits--;
      throw error;
    }
  }

  /** Delete through the editor while reserving the asynchronous text-change echo it produces. */
  private deleteEditorBackwardSync(count: number): void {
    if (this.inputClient === undefined) return;
    this.pendingOwnEdits++;
    try {
      this.inputClient.deleteBackwardSync(count);
    } catch (error) {
      this.pendingOwnEdits--;
      throw error;
    }
  }

  /** Activate a prepared dictionary snapshot only at an idle boundary. */
  snapshotActivate(handle: number, expectedVersion: string): string {
    if (handle <= 0 || !/^[0-9a-f]{64}$/.test(expectedVersion) || this.composing()) {
      return JSON.stringify({ ok: false, error: 'snapshot access busy' });
    }
    const hadSession: boolean = this.handle !== 0;
    const english: boolean = this.englishMode;
    const nineKey: boolean = this.nineKeyMode;
    if (hadSession) this.stop();
    let result: string;
    try {
      result = client.snapshotActivate(handle, expectedVersion);
    } catch (error) {
      KeyboardLog.error(`snapshot activation unavailable: ${describeError(error)}`);
      result = JSON.stringify({ ok: false, error: 'snapshot activation failed' });
    }
    try {
      const parsed: SnapshotResponse = JSON.parse(result) as SnapshotResponse;
      if (!parsed.ok) {
        KeyboardLog.error(`snapshot activation refused: ${parsed.error}`);
      }
    } catch {
      // Preserve the native response for the caller; a malformed response is already an error.
    }
    // Stopping the live session is part of the maintenance boundary. Always recreate it, even
    // when the native activation refused, so a transient conflict cannot leave the keyboard dead.
    if (hadSession && this.start(this.resourceDirectory, this.stateDirectory, this.systemDark)) {
      this.englishMode = english;
      this.nineKeyMode = nineKey;
      if (this.inputClient !== undefined) {
        this.apply(client.focus(this.handle, true));
        this.applyView(client.setEnglishMode(this.handle, english));
        this.applyView(client.setNineKeyMode(this.handle, nineKey));
      }
    } else if (hadSession) {
      KeyboardLog.error('snapshot activation left the session unavailable');
    }
    return result;
  }

  /**
   * Run one shared dictionary-management action without violating the Engine maintenance lock.
   *
   * Reads can coexist with the live session. A write briefly recreates an idle session so the
   * Engine has exclusive dictionary access, but never cancels a composition to obtain it.
   */
  dictionary(actionDocument: string, resources: string, stateRoot: string): string {
    let action: DictionaryAction;
    try {
      const decoded: DictionaryAction | null = JSON.parse(actionDocument) as DictionaryAction | null;
      if (decoded === null || typeof decoded.operation !== 'string') {
        return JSON.stringify({ ok: false, error: 'invalid dictionary action' });
      }
      action = decoded;
    } catch (error) {
      return JSON.stringify({ ok: false, error: 'invalid dictionary action' });
    }
    const decision = DictionaryMaintenancePolicy.decide(action.operation, this.composing());
    if (!decision.allowed) {
      return JSON.stringify({ ok: false, error: decision.error });
    }
    const maintenance: boolean = decision.maintenance;
    const hadSession: boolean = this.handle !== 0;
    const english: boolean = this.englishMode;
    const nineKey: boolean = this.nineKeyMode;
    if (maintenance && hadSession) {
      this.stop();
    }
    let result: string;
    try {
      const bootstrap: PrepareRequest = { resources: resources, state_root: stateRoot };
      const prepared: PrepareResponse =
        JSON.parse(client.prepareHost(JSON.stringify(bootstrap))) as PrepareResponse;
      if (!prepared.ok) {
        return JSON.stringify(prepared);
      }
      const request: DictionaryRequest = { options: prepared.value, action: action };
      // Same request shape, different store. The queued route writes the personal-dictionary file
      // beside the preferences and is drained at the next session start; the Engine route needs
      // the maintenance lock this method has just taken.
      result = decision.queued
        ? client.personalDictionaryRequest(JSON.stringify(request))
        : client.dictionary(JSON.stringify(request));
    } catch (error) {
      KeyboardLog.error(`dictionary request unavailable: ${describeError(error)}`);
      result = JSON.stringify({ ok: false, error: 'dictionary request failed' });
    } finally {
      if (maintenance && hadSession) {
        if (this.start(resources, stateRoot, this.systemDark)) {
          this.englishMode = english;
          this.nineKeyMode = nineKey;
          if (this.inputClient !== undefined) {
            this.apply(client.focus(this.handle, true));
            this.applyView(client.setEnglishMode(this.handle, english));
            this.applyView(client.setNineKeyMode(this.handle, nineKey));
          }
        } else {
          KeyboardLog.error('dictionary maintenance left the session unavailable');
        }
      }
    }
    return result;
  }

  press(ascii: number, shift: boolean): void {
    // Checked before the repeat arming is cleared: the space that converts is the key immediately
    // after the mark, so this is the one press where both armings are live at once.
    if (this.convertPunctuationSpace(ascii)) {
      return;
    }
    this.clearSmartPunctuationRepeat();
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
    this.tapFeedback();
    const before: number = this.editing.length;
    this.apply(client.character(this.handle, ascii, shift));
    // A letter that leaves the composition exactly as it was is the one failure this path cannot
    // otherwise report: the key was claimed, so the application never sees it, and the Engine
    // answered `ok`, so apply() has nothing to complain about. The result is a key that silently
    // does nothing — which is what happened on a 2in1, where hardware keys compose nothing while
    // the same press() from the touch keyboard composes normally.
    //
    // What is logged is the shape of the failure, never the key: a character in hilog is the user's
    // text. The scheme and the local mode are the two host-side inputs that decide whether a letter
    // should have composed at all, and both are already public state.
    if (before === 0 && this.editing.length === 0) {
      KeyboardLog.error(`composing key produced no composition: scheme=${this.schemeName}`
        + ` local=${this.localMode} english=${this.englishMode} candidates=${this.currentCandidates.length}`);
    }
  }

  /** Route an ASCII punctuation key through the shared editor-context policy. */
  punctuation(ascii: number): void {
    if (this.handle === 0 || this.inputClient === undefined) return;
    let preceding: number = 0;
    try {
      // Harmony's getForwardSync returns the bounded text immediately before the cursor.
      preceding = SmartPunctuationContext.precedingCodePoint(this.inputClient.getForwardSync(2));
    } catch (error) {
      // Editor context is optional; zero deliberately falls back to Engine punctuation.
      KeyboardLog.error(`editor punctuation context unavailable: ${describeError(error)}`);
    }
    const now: number = Date.now();
    if (SmartPunctuationRepeatPolicy.shouldReplace(
      this.smartPunctuationSnapshot, ascii, preceding, now, this.editorGeneration,
      this.smartPunctuation, this.smartPunctuationRepeat, this.editing.length > 0,
      this.currentCandidates.length)) {
      const chinese: string | null = SmartPunctuationRepeatPolicy.chineseMark(ascii);
      if (chinese !== null) {
        try {
          // deleteBackwardSync(1) removes the one scalar just before the caret. The preceding
          // scalar was checked above, so a replacement cannot consume unrelated text.
          this.deleteEditorBackwardSync(1);
          this.insertEditorTextSync(chinese);
          this.recordTypingStatistics(chinese, this.typingSource());
          this.clearSmartPunctuationRepeat();
          this.refreshEnglishSuggestions();
          return;
        } catch (error) {
          KeyboardLog.error(`repeated punctuation replacement unavailable: ${describeError(error)}`);
          this.clearSmartPunctuationRepeat();
        }
      }
    }

    const raw: string = client.punctuationWithContext(this.handle, ascii, preceding);
    let completion: PairedPunctuationCompletion | null = null;
    let committed: string | null | undefined = null;
    try {
      const response: Response = JSON.parse(raw) as Response;
      if (response.ok) committed = response.value.commit;
      completion = response.ok
        ? PairedPunctuationPolicy.completion(response.value.commit,
          this.appearance.pairedPunctuation) : null;
    } catch (error) {
      KeyboardLog.error(`paired punctuation response unavailable: ${describeError(error)}`);
    }
    this.apply(raw);
    // PunctuationAscii intentionally has no Engine commit while idle. In that route the host must
    // write the literal mark itself; this is also the state from which a repeated smart mark can
    // be replaced on the next press.
    if ((committed === null || committed === undefined || committed.length === 0)
        && this.inputClient !== undefined && this.editing.length === 0
        && this.currentCandidates.length === 0) {
      try {
        const literal: string = FullWidthInputPolicy.output(String.fromCharCode(ascii), this.fullWidth)
          ?? String.fromCharCode(ascii);
        this.insertEditorTextSync(literal);
        this.recordTypingStatistics(literal, this.typingSource());
        this.refreshEnglishSuggestions();
        if (this.canArmSmartPunctuationRepeat(ascii, preceding)) {
          this.smartPunctuationSnapshot = SmartPunctuationRepeatPolicy.snapshot(
            ascii, literal, now, this.editorGeneration);
        } else {
          this.clearSmartPunctuationRepeat();
        }
      } catch (error) {
        KeyboardLog.error(`ASCII punctuation insertion unavailable: ${describeError(error)}`);
        this.clearSmartPunctuationRepeat();
      }
    } else {
      this.clearSmartPunctuationRepeat();
    }
    // Armed off the Engine's own commit rather than off the key that was pressed: what reaches the
    // editor is what the space would be correcting, and the two differ whenever the punctuation
    // policy rewrote the mark.
    this.smartPunctuationSpaceSnapshot = SmartPunctuationSpacePolicy.arm(
      committed, completion !== null, this.smartPunctuation, this.smartPunctuationSpaceConvert,
      this.editorGeneration);
    if (completion === null || this.inputClient === undefined) return;
    try {
      this.insertEditorTextSync(completion.closing);
      this.recordTypingStatistics(completion.closing, this.typingSource());
      this.refreshEnglishSuggestions();
      if (completion.opening === 0x3c) {
        const balanced: string = client.balancePairedPunctuationAfterAutoClose(
          this.handle, completion.opening);
        const balanceResponse: NativeReply<Object> = JSON.parse(balanced) as NativeReply<Object>;
        if (!balanceResponse.ok) {
          KeyboardLog.error(`book-title punctuation balance refused: ${balanceResponse.error}`);
        }
      }
      this.inputClient.moveCursorSync(inputMethodEngine.Direction.CURSOR_LEFT);
    } catch (error) {
      KeyboardLog.error(`paired punctuation completion unavailable: ${describeError(error)}`);
    }
  }

  private command(command: InputCommand): boolean {
    if (this.handle === 0) {
      return false;
    }
    return this.apply(client.command(this.handle, command));
  }

  commitHighlighted(): void {
    if (this.translationPage !== null) {
      this.choose(0);
      return;
    }
    this.command(InputCommand.SELECT_HIGHLIGHTED);
  }

  hasHighlightedTranslation(): boolean {
    if (this.translationPage !== null) return false;
    return this.currentCandidates.some((candidate: Candidate): boolean =>
      candidate.highlighted && typeof candidate.translation === 'string'
      && candidate.translation.length > 0);
  }

  hasHighlightedCandidate(): boolean {
    return this.currentCandidates.some((candidate: Candidate): boolean => candidate.highlighted);
  }

  /** Ctrl+Enter commits the resolved translation without changing the user's composition text. */
  commitTranslation(): void {
    if (this.translationPage !== null) return;
    const candidate: Candidate | undefined = this.currentCandidates.find(
      (entry: Candidate): boolean => entry.highlighted && typeof entry.translation === 'string'
        && entry.translation.length > 0);
    if (candidate === undefined || candidate.translation === undefined
        || candidate.translation === null) {
      return;
    }
    const translations: string[] = TranslationSensePolicy.split(candidate.translation);
    if (translations.length === 0) return;
    if (translations.length > 1) {
      this.translationPage = translations;
      this.publishTranslationPage();
      return;
    }
    this.cancel();
    this.insertWithSource(translations[0], 'translation');
  }

  backspace(): void {
    const handled: boolean = this.command(InputCommand.BACKSPACE);
    if (!BackspaceHoldPolicy.deletesEditor(handled) || this.inputClient === undefined) {
      return;
    }
    try {
      this.deleteEditorBackwardSync(1);
      this.refreshEnglishSuggestions();
    } catch (error) {
      KeyboardLog.error(`editor backspace unavailable: ${describeError(error)}`);
    }
  }

  /** Throw the composition away without committing it, which is what 重输 means. */
  cancel(): void {
    if (this.translationPage !== null) {
      this.translationPage = null;
      this.publishCurrentCandidates();
      return;
    }
    this.command(InputCommand.CANCEL);
  }

  /** Commit the spelling as typed rather than any candidate. */
  commitRaw(): void {
    this.command(InputCommand.COMMIT_RAW);
  }

  /** Commit the highlighted candidate, or the reading when the scheme has no converted candidate. */
  finishComposition(): boolean {
    return this.command(InputCommand.FINISH_COMPOSITION);
  }

  /** Commit Japanese kana as entered, without forcing the first converted candidate. */
  commitReading(): boolean {
    return this.command(InputCommand.COMMIT_READING);
  }

  /** Space starts Japanese conversion, then advances and wraps without committing. */
  convertJapanese(): boolean {
    if (this.scheme !== JAPANESE_SCHEME || this.editing.length === 0
        || this.currentCandidates.length === 0) {
      return false;
    }
    if (this.japaneseConversionIndex < 0
        || this.japaneseConversionReading !== this.editing) {
      this.japaneseConversionIndex = 0;
      this.japaneseConversionReading = this.editing;
      return true;
    }
    const next: number = this.japaneseConversionIndex + 1;
    const wraps: boolean = next >= this.currentCandidates.length;
    const wanted: number = wraps ? 0 : next;
    if (!this.command(wraps ? InputCommand.FIRST_CANDIDATE : InputCommand.NEXT_CANDIDATE)) {
      return false;
    }
    this.japaneseConversionIndex = wanted;
    return true;
  }

  /** Return commits the conversion only after Space; otherwise it preserves the kana reading. */
  commitJapanese(): boolean {
    if (this.scheme !== JAPANESE_SCHEME || this.editing.length === 0) {
      return false;
    }
    const converted: boolean = this.japaneseConversionActive();
    this.japaneseConversionIndex = -1;
    this.japaneseConversionReading = '';
    return converted ? this.command(InputCommand.SELECT_HIGHLIGHTED) : this.commitReading();
  }

  japaneseConversionActive(): boolean {
    return this.japaneseConversionIndex >= 0
      && this.japaneseConversionReading === this.editing;
  }

  moveLeft(): void {
    this.command(InputCommand.MOVE_LEFT);
  }

  moveRight(): void {
    this.command(InputCommand.MOVE_RIGHT);
  }

  moveHome(): void {
    this.command(InputCommand.MOVE_HOME);
  }

  moveEnd(): void {
    this.command(InputCommand.MOVE_END);
  }

  deleteForward(): void {
    this.command(InputCommand.DELETE_FORWARD);
  }

  backspaceSegment(): void {
    this.command(InputCommand.BACKSPACE_SEGMENT);
  }

  moveLeftSegment(): void {
    this.command(InputCommand.MOVE_LEFT_SEGMENT);
  }

  moveRightSegment(): void {
    this.command(InputCommand.MOVE_RIGHT_SEGMENT);
  }

  nextPage(): void {
    this.command(InputCommand.NEXT_PAGE);
  }

  previousPage(): void {
    this.command(InputCommand.PREVIOUS_PAGE);
  }

  nextCandidate(): void {
    this.command(InputCommand.NEXT_CANDIDATE);
  }

  previousCandidate(): void {
    this.command(InputCommand.PREVIOUS_CANDIDATE);
  }

  choose(index: number): void {
    if (this.translationPage !== null) {
      const translation: string | undefined = this.translationPage[index];
      if (translation === undefined) return;
      this.translationPage = null;
      this.command(InputCommand.CANCEL);
      this.insertWithSource(translation, 'translation');
      return;
    }
    if (this.handle === 0) {
      return;
    }
    this.apply(client.select(this.handle, this.generation, index));
  }

  /** Commit the first or last Han scalar of the highlighted candidate. */
  selectEdge(edge: CandidateTextEdge): void {
    if (this.handle === 0) return;
    const candidate: Candidate | undefined = this.currentCandidates.find(
      (entry: Candidate): boolean => entry.highlighted);
    if (candidate === undefined) return;
    const raw: string = client.selectEdge(this.handle, this.generation,
      this.currentCandidates.indexOf(candidate), edge === CandidateTextEdge.FIRST ? 0 : 1);
    let response: Response;
    try {
      response = JSON.parse(raw) as Response;
    } catch (error) {
      KeyboardLog.error(`candidate edge response unavailable: ${describeError(error)}`);
      return;
    }
    if (!response.ok) {
      KeyboardLog.error(`candidate edge refused: ${response.error}`);
      return;
    }
    const commit: string | null | undefined = response.value.commit;
    this.apply(raw);
    if (commit !== null && commit !== undefined && commit.length > 0) return;
    const fallback: string | null = CandidateTextPolicy.extractHanCharacter(candidate.text, edge);
    if (fallback === null) return;
    this.apply(client.command(this.handle, InputCommand.CANCEL));
    this.insertWithSource(fallback, this.typingSource());
  }

  private apply(raw: string): boolean {
    let response: Response;
    try {
      response = JSON.parse(raw) as Response;
    } catch (error) {
      // Silence here would look exactly like a key that did nothing, which is the hardest kind of
      // failure to chase on a device. The reply itself stays out of the log: it carries candidates,
      // and candidates are the user's text.
      KeyboardLog.error(`unreadable engine reply: ${describeError(error)}`);
      return false;
    }
    if (!response.ok) {
      KeyboardLog.error(`engine refused: ${response.error}`);
      return false;
    }
    const value: EngineValue = response.value;
    // Bounded before it reaches the surface: a diagnostic is a message, not a place to print a
    // stack trace into a keyboard four rows tall.
    this.editing = value.view.editing_text;
    this.editingCaret = value.view.caret_position;
    this.scheme = value.view.scheme;
    this.diagnostic = InputDiagnosticPolicy.normalize(
      value.diagnostic === undefined ? null : value.diagnostic);
    const commit: string | null | undefined = value.commit;
    if (commit !== null && commit !== undefined && commit.length > 0
        && this.inputClient !== undefined) {
      // The Engine commits simplified; whether the user wanted traditional is a host decision, the
      // same boundary the Apple and Android hosts draw.
      const output: string = this.asTraditional(commit);
      this.insertEditorText(output);
      this.recordTypingStatistics(output, this.typingSource());
    }
    this.render(value.view);
    return value.handled === true;
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
  private bindings: ModeBindings = DEFAULT_MODE_BINDINGS;
  private feedbackSettings: FeedbackSettings = KeyboardFeedback.DEFAULTS;
  private customSkinDesign: CustomKeyboardSkin = CustomKeyboardSkin.defaults();
  private vibratorFailed: boolean = false;
  private traditional: boolean = false;
  private chinesePunctuation: boolean = true;
  private smartPunctuation: boolean = true;
  private smartPunctuationRepeat: boolean = true;
  // Off by default, like the rest of the family on the Windows baseline: it changes a
  // character the user already saw land.
  private smartPunctuationSpaceConvert: boolean = false;
  private smartPunctuationSpaceSnapshot: SmartPunctuationSpaceSnapshot | null = null;
  private punctuationLock: string = 'follow';
  private wordCharacter: string = 'disabled';
  private smartPunctuationSnapshot: SmartPunctuationRepeatSnapshot | null = null;
  private toolbar: PreparedFloatingToolbar = {
    enabled: true, english_mode: true, punctuation: true, fullwidth: true, character_set: true,
    emoji: true, screen_keyboard: false, scale_percent: 100, font_size: 20
  };
  private toolbarSkin: ToolbarSkin = ToolbarSkinPolicy.base(KeyboardSkin.from('forest', false));
  private onlineTimer: number = -1;
  private onlineEpoch: number = 0;
  private onlineSignature: string = '';
  private translationTimer: number = -1;
  private translationEpoch: number = 0;
  private translationSignature: string = '';
  private readonly translationCache: Map<string, string> = new Map<string, string>();
  private readonly translationNegativeCache: Map<string, number> = new Map<string, number>();
  // ICU's Simplified-Traditional, which is the same transliteration Android reaches through its own
  // ICU and Apple through its host boundary. Built once: constructing one per commit would pay for
  // the table on every keystroke.
  private converter: i18n.Transliterator | undefined = undefined;
  private editing: string = '';
  private japaneseConversionIndex: number = -1;
  private japaneseConversionReading: string = '';
  // Where the segment keys have put the caret. Drawn by the candidate window, which is the
  // only place it is visible: the editor sees a committed string, not a composition.
  private editingCaret: number = 0;
  private currentCandidates: Candidate[] = [];
  private translationPage: string[] | null = null;
  private lastView: EngineView | undefined = undefined;
  private scheme: number = 0;
  private localMode: string = 'none';

  private render(view: EngineView): void {
    this.generation = view.generation;
    this.currentCandidates = view.candidates.slice();
    this.lastView = view;
    if (this.japaneseConversionIndex >= 0
        && view.editing_text !== this.japaneseConversionReading) {
      this.japaneseConversionIndex = -1;
      this.japaneseConversionReading = '';
    }
    if (this.translationPage !== null) return;
    const localModeChanged: boolean = this.localMode !== view.local_mode;
    this.localMode = view.local_mode;
    // Here rather than in apply(), because both paths end up here and only one of them went through
    // apply(): a reply that is a bare view — which is what every mode switch answers with — left
    // this behind, so the toolbar's 半 never became 全 and the next tap asked for the same thing
    // again.
    this.fullWidth = view.character_width === 'Fullwidth';
    const active: boolean = view.editing_text.length > 0;
    if (active !== this.composedLast) {
      this.composedLast = active;
      if (this.onComposition !== undefined) {
        this.onComposition(active);
      }
    }
    const entries: CandidateEntry[] = [];
    for (const candidate of view.candidates) {
      entries.push({
        text: candidate.text,
        highlighted: candidate.highlighted,
        badge: CandidatePresentationPolicy.badge(candidate.source),
        fixedPosition: candidate.fixed_position,
        source: candidate.source,
        translation: candidate.translation ?? null,
        // Only the part of the code still untyped, and only where that means something. The policy
        // decides; this just supplies what it reasons about.
        hint: WubiCodeHintPolicy.hint(candidate.code, view.preedit, this.wubiCodeHint, view.scheme,
          view.local_mode, view.answered_by_pinyin_fallback),
        annotation: CandidateGlossPolicy.annotation(candidate.annotation,
          candidate.translation ?? null, this.candidateEnglishGloss),
        annotationIsTranslation: CandidateGlossPolicy.annotationIsTranslation(candidate.annotation,
          candidate.translation ?? null, this.candidateEnglishGloss)
      });
    }
    if (this.onChanged !== undefined) {
      this.onChanged({
        candidates: entries,
        // 已选的那一段领在读音前面，与来源把 word_for_creating_word 拼在读音前面是同一件事。
        editing: view.phrase_prefix + view.editing_text,
        editingCaret: view.caret_position + view.phrase_prefix.length,
        spellings: view.nine_key_spellings,
        scheme: view.scheme,
        shuangpinProfile: view.shuangpin_profile,
        localMode: view.local_mode,
        english: view.dedicated_english,
        diagnostic: this.diagnostic
      });
    }
    if (this.onCandidateWidth !== undefined) {
      this.onCandidateWidth(CandidateWidthPolicy.widthVp(entries, view.editing_text,
        this.preferences().candidateFontSize, this.preferences().candidatePreeditFontSize,
        this.preferences().candidateMinWidthVp));
    }
    if (this.onCandidateCount !== undefined) {
      this.onCandidateCount(entries.length);
    }
    if (localModeChanged) {
      this.refreshToolbar();
    }
    // Candidate annotations and online providers are display-only work. Both run after the Engine
    // view is published, and native result application rechecks the exact generation.
    this.scheduleOnlineProviders();
    this.scheduleTranslations();
    // Every typed letter and every backspace arrives here, which is the one place that sees the
    // editor change in direct English as well as in a composition.
    this.refreshEnglishSuggestions();
  }

  private publishCurrentCandidates(): void {
    const view: EngineView | undefined = this.lastView;
    if (view === undefined || this.onChanged === undefined) return;
    const entries: CandidateEntry[] = view.candidates.map((candidate: Candidate): CandidateEntry => ({
      text: candidate.text, highlighted: candidate.highlighted,
      badge: CandidatePresentationPolicy.badge(candidate.source),
      fixedPosition: candidate.fixed_position, source: candidate.source,
      translation: candidate.translation ?? null,
      hint: WubiCodeHintPolicy.hint(candidate.code, view.preedit, this.wubiCodeHint, view.scheme,
        view.local_mode, view.answered_by_pinyin_fallback),
      annotation: CandidateGlossPolicy.annotation(candidate.annotation,
        candidate.translation ?? null, this.candidateEnglishGloss),
      annotationIsTranslation: CandidateGlossPolicy.annotationIsTranslation(candidate.annotation,
        candidate.translation ?? null, this.candidateEnglishGloss)
    }));
    this.onChanged({
      candidates: entries, editing: view.phrase_prefix + view.editing_text,
      editingCaret: view.caret_position + view.phrase_prefix.length,
      spellings: view.nine_key_spellings,
      scheme: view.scheme, shuangpinProfile: view.shuangpin_profile, localMode: view.local_mode,
      english: view.dedicated_english, diagnostic: this.diagnostic
    });
    if (this.onCandidateWidth !== undefined) {
      this.onCandidateWidth(CandidateWidthPolicy.widthVp(entries, view.editing_text,
        this.preferences().candidateFontSize, this.preferences().candidatePreeditFontSize,
        this.preferences().candidateMinWidthVp));
    }
    if (this.onCandidateCount !== undefined) this.onCandidateCount(entries.length);
  }

  private publishTranslationPage(): void {
    const translations: string[] | null = this.translationPage;
    if (translations === null || this.onChanged === undefined) return;
    const view: EngineView | undefined = this.lastView;
    const entries: CandidateEntry[] = translations.map((text: string, index: number): CandidateEntry => ({
      text: text, hint: '', annotation: '', annotationIsTranslation: false,
      highlighted: index === 0, badge: '',
      fixedPosition: 0, source: 0, translation: null
    }));
    this.onChanged({
      candidates: entries,
      editing: view?.editing_text ?? this.editing,
      editingCaret: view?.caret_position ?? this.editingCaret, spellings: [],
      scheme: view?.scheme ?? this.scheme, shuangpinProfile: view?.shuangpin_profile ?? this.profileName,
      localMode: view?.local_mode ?? this.localMode,
      english: view?.dedicated_english ?? this.englishMode, diagnostic: this.diagnostic
    });
    if (this.onCandidateWidth !== undefined) {
      this.onCandidateWidth(CandidateWidthPolicy.widthVp(entries, view?.editing_text ?? this.editing,
        this.preferences().candidateFontSize, this.preferences().candidatePreeditFontSize,
        this.preferences().candidateMinWidthVp));
    }
    if (this.onCandidateCount !== undefined) this.onCandidateCount(translations.length);
  }

  private scheduleOnlineProviders(): void {
    if (this.handle === 0) return;
    let reply: NativeReply<OnlineQuery | null>;
    try {
      reply = JSON.parse(client.onlineQuery(this.handle)) as NativeReply<OnlineQuery | null>;
    } catch (error) {
      KeyboardLog.error(`online query unavailable: ${describeError(error)}`);
      return;
    }
    if (!reply.ok || reply.value === null) {
      this.onlineSignature = '';
      return;
    }
    const query: OnlineQuery = reply.value;
    const signature: string = OnlineCandidatePolicy.signature(query);
    if (signature === this.onlineSignature) return;
    this.onlineSignature = signature;
    if (this.onlineTimer >= 0) clearTimeout(this.onlineTimer);
    const epoch: number = ++this.onlineEpoch;
    const handle: number = this.handle;
    this.onlineTimer = setTimeout((): void => {
      this.onlineTimer = -1;
      void this.fetchOnline(handle, JSON.stringify(query), query, epoch);
    }, OnlineCandidatePolicy.QUIET_INTERVAL_MS);
  }

  private async fetchOnline(handle: number, queryDocument: string, query: OnlineQuery,
    epoch: number): Promise<void> {
    if (epoch !== this.onlineEpoch || handle !== this.handle) return;
    let aiQuery: OnlineQuery = query;
    let aiDocument: string = queryDocument;
    if (query.cloud_candidates && query.cloud_eligible) {
      const applied: boolean = await this.fetchCloud(handle, queryDocument, epoch);
      // Applying a cloud result advances Engine's generation. Re-read the exact query before
      // sending AI so both optional providers can contribute without one becoming stale.
      if (applied && handle === this.handle && epoch === this.onlineEpoch) {
        try {
          const current: NativeReply<OnlineQuery | null> = JSON.parse(
            client.onlineQuery(handle)) as NativeReply<OnlineQuery | null>;
          if (current.ok && current.value !== null) {
            aiQuery = current.value;
            aiDocument = JSON.stringify(current.value);
          }
        } catch {
          return;
        }
      }
    }
    const assistant = aiQuery.ai_assistant;
    if (assistant?.enabled === true && aiQuery.ai_eligible) {
      await this.fetchAi(handle, aiDocument, assistant.candidate_limit, epoch);
    }
  }

  private async fetchCloud(handle: number, queryDocument: string, epoch: number): Promise<boolean> {
    let url: string;
    try {
      const reply: NativeReply<string> = JSON.parse(
        client.cloudRequestUrl(queryDocument)) as NativeReply<string>;
      if (!reply.ok || typeof reply.value !== 'string') return false;
      url = reply.value;
    } catch (error) {
      KeyboardLog.error(`cloud query unavailable: ${describeError(error)}`);
      return false;
    }
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: { Accept: 'application/json' },
        connectTimeout: 2500,
        readTimeout: 8000
      });
      if (epoch !== this.onlineEpoch || handle !== this.handle || response.responseCode < 200
        || response.responseCode >= 300 || typeof response.result !== 'string'
        || OnlineCandidatePolicy.MAX_CLOUD_RESPONSE_BYTES < response.result.length) return false;
      const applied: NativeReply<OnlineApplyValue> = JSON.parse(client.applyCloudResponse(
        handle, queryDocument, response.result)) as NativeReply<OnlineApplyValue>;
      if (applied.ok && applied.value.applied) this.render(applied.value.view);
      return applied.ok && applied.value.applied;
    } catch (error) {
      KeyboardLog.error(`cloud candidate unavailable: ${describeError(error)}`);
      return false;
    } finally {
      request.destroy();
    }
  }

  private async fetchAi(handle: number, queryDocument: string, limit: number,
    epoch: number): Promise<void> {
    let descriptor: AiHttpDescriptor | null;
    try {
      const reply: NativeReply<AiHttpDescriptor | null> = JSON.parse(
        client.aiRequestForQuery(handle, queryDocument)) as NativeReply<AiHttpDescriptor | null>;
      if (!reply.ok || reply.value === null) return;
      descriptor = reply.value;
    } catch (error) {
      KeyboardLog.error(`AI query unavailable: ${describeError(error)}`);
      return;
    }
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(descriptor.url, {
        method: http.RequestMethod.POST,
        header: descriptor.headers,
        connectTimeout: Math.min(8000, Math.max(1000, descriptor.connect_timeout_ms)),
        readTimeout: Math.min(10000, Math.max(1000, descriptor.timeout_ms)),
        extraData: JSON.stringify(descriptor.body)
      });
      if (epoch !== this.onlineEpoch || handle !== this.handle || response.responseCode < 200
        || response.responseCode >= 300 || typeof response.result !== 'string') return;
      const candidates: string[] | null = OnlineCandidatePolicy.aiCandidates(response.result, limit);
      if (candidates === null || candidates.length === 0) return;
      const applied: NativeReply<OnlineApplyValue> = JSON.parse(client.applyOnlineCandidates(
        handle, queryDocument, JSON.stringify(candidates), 1)) as NativeReply<OnlineApplyValue>;
      if (applied.ok && applied.value.applied) this.render(applied.value.view);
    } catch (error) {
      KeyboardLog.error(`AI candidate unavailable: ${describeError(error)}`);
    } finally {
      request.destroy();
    }
  }

  private scheduleTranslations(): void {
    if (this.handle === 0) return;
    let reply: NativeReply<TranslationQuery | null>;
    try {
      reply = JSON.parse(client.translationQuery(this.handle)) as NativeReply<TranslationQuery | null>;
    } catch (error) {
      KeyboardLog.error(`translation query unavailable: ${describeError(error)}`);
      return;
    }
    if (!reply.ok || reply.value === null) {
      this.translationSignature = '';
      return;
    }
    const query: TranslationQuery = reply.value;
    const signature: string = TranslationPolicy.signature(query);
    if (signature === this.translationSignature) return;
    this.translationSignature = signature;
    if (this.translationTimer >= 0) clearTimeout(this.translationTimer);
    const epoch: number = ++this.translationEpoch;
    const handle: number = this.handle;
    this.translationTimer = setTimeout((): void => {
      this.translationTimer = -1;
      void this.fetchTranslations(handle, JSON.stringify(query), query, epoch);
    }, TranslationPolicy.QUIET_INTERVAL_MS);
  }

  private async fetchTranslations(handle: number, queryDocument: string,
    query: TranslationQuery, epoch: number): Promise<void> {
    if (!this.translationCurrent(handle, epoch)) return;
    const entries: TranslationEntry[] = [];
    if (query.english_gloss && typeof query.resources === 'string' && query.resources.length > 0) {
      this.appendOfflineGloss(query, entries);
    }
    const deadline: number = Date.now() + 6000;
    const provider: string = TranslationPolicy.provider(query);
    for (const target of TranslationPolicy.targets(query)) {
      if (!this.translationCurrent(handle, epoch) || Date.now() >= deadline) return;
      let plan: TranslationPlanItem[] = [];
      try {
        const planDocument: string = TranslationPolicy.planRequest(target, query.candidates);
        const planReply: NativeReply<TranslationPlanItem[]> =
          JSON.parse(client.translationPlan(planDocument)) as NativeReply<TranslationPlanItem[]>;
        if (planReply.ok && Array.isArray(planReply.value)) plan = planReply.value;
      } catch (error) {
        KeyboardLog.error(`translation plan unavailable: ${describeError(error)}`);
      }
      if (plan.length === 0 || provider.length === 0) continue;
      const pending: TranslationPlanItem[] = [];
      for (const item of plan) {
        if (target === 'en' && query.english_gloss
          && entries.some((entry: TranslationEntry): boolean => entry.text === item.text)) {
          continue;
        }
        const key: string = TranslationPolicy.cacheKey(query, target, item);
        const cached: string | undefined = this.translationCache.get(key);
        if (cached !== undefined) {
          TranslationPolicy.append(entries, item.text, cached);
          continue;
        }
        const negativeUntil: number | undefined = this.translationNegativeCache.get(key);
        if (negativeUntil !== undefined) {
          if (negativeUntil > Date.now()) continue;
          this.translationNegativeCache.delete(key);
        }
        pending.push(item);
      }
      if (pending.length === 0) continue;
      if (provider === 'tencent' && query.tencent_tmt !== null
        && query.tencent_tmt !== undefined) {
        await this.fetchTencentTranslations(query, pending, entries, epoch, handle, deadline);
      } else {
        for (const item of pending) {
          if (!this.translationCurrent(handle, epoch) || Date.now() >= deadline) return;
          let value: string | null = null;
          if (provider === 'niutrans' && query.niutrans !== null
            && query.niutrans !== undefined) {
            value = await this.fetchNiuTranslation(query.niutrans, item, epoch, handle);
          } else if (provider === 'custom' && query.custom_translation !== null
            && query.custom_translation !== undefined) {
            value = await this.fetchCustomTranslation(query.custom_translation, item, epoch, handle);
          }
          this.recordTranslation(query, target, item, value, entries);
        }
      }
    }
    if (!this.translationCurrent(handle, epoch) || entries.length === 0) return;
    let appliedCurrent: boolean = false;
    try {
      const applied: NativeReply<OnlineApplyValue> = JSON.parse(client.applyTranslations(
        handle, query.generation, JSON.stringify(entries))) as NativeReply<OnlineApplyValue>;
      if (applied.ok && applied.value !== undefined && applied.value.view !== undefined
        && applied.value.applied !== false) {
        appliedCurrent = applied.value.applied;
        this.render(applied.value.view);
      }
      if (appliedCurrent && query.user_data !== undefined && query.user_data.length > 0
        && TranslationPolicy.targets(query).includes('en')) {
        const saveRequest: TranslationGlossSaveRequest = {
          target_language: 'en', translations: entries
        };
        client.translationGlossSave(JSON.stringify(saveRequest), query.user_data);
      }
    } catch (error) {
      KeyboardLog.error(`candidate translations unavailable: ${describeError(error)}`);
    }
  }

  private appendOfflineGloss(query: TranslationQuery, entries: TranslationEntry[]): void {
    try {
      const request: GlossRequestDocument = {
        generation: query.generation,
        user_data: query.user_data ?? '',
        candidates: query.candidates.map((candidate: TranslationCandidate): GlossRequestCandidate => ({
          text: candidate.text, source: 0
        }))
      };
      const glossResponse: string = client.candidateGlosses(
        JSON.stringify(request), query.resources ?? '');
      const reply: NativeReply<TranslationResponseValue> =
        JSON.parse(glossResponse) as NativeReply<TranslationResponseValue>;
      if (!reply.ok || reply.value === undefined || reply.value.generation !== query.generation
        || !Array.isArray(reply.value.translations)) return;
      for (const entry of reply.value.translations) {
        TranslationPolicy.append(entries, entry.text, entry.translation);
      }
    } catch (error) {
      KeyboardLog.error(`offline candidate glosses unavailable: ${describeError(error)}`);
    }
  }

  private async fetchTencentTranslations(query: TranslationQuery, items: TranslationPlanItem[],
    entries: TranslationEntry[], epoch: number, handle: number, deadline: number): Promise<void> {
    const groups: Map<string, TranslationPlanItem[]> = new Map<string, TranslationPlanItem[]>();
    for (const item of items) {
      const group: string = `${item.source_language}\n${item.target_language}`;
      const values: TranslationPlanItem[] = groups.get(group) ?? [];
      values.push(item);
      groups.set(group, values);
    }
    for (const group of groups.values()) {
      if (!this.translationCurrent(handle, epoch) || Date.now() >= deadline) return;
      const config: TencentTranslationConfig | null | undefined = query.tencent_tmt;
      if (config === null || config === undefined) return;
      const request: TencentTranslationRequest = {
        config: config,
        texts: group.map((item: TranslationPlanItem): string => item.key),
        source_language: group[0].source_language,
        target_language: group[0].target_language,
        timestamp: Math.floor(Date.now() / 1000)
      };
      let descriptor: TranslationHttpDescriptor | null = null;
      try {
        const descriptorResponse: string = client.tencentTranslationHttpRequest(
          JSON.stringify(request));
        const reply: NativeReply<TranslationHttpDescriptor | null> =
          JSON.parse(descriptorResponse) as NativeReply<TranslationHttpDescriptor | null>;
        if (reply.ok) descriptor = reply.value;
      } catch (error) {
        KeyboardLog.error(`Tencent translation descriptor unavailable: ${describeError(error)}`);
      }
      if (descriptor === null) continue;
      const body: string | null = await this.translationHttp(descriptor, false, epoch, handle);
      if (body === null) continue;
      try {
        const parsed: NativeReply<string[] | null> = JSON.parse(client.parseTencentTranslationResponse(
          body, group.length)) as NativeReply<string[] | null>;
        if (!parsed.ok || parsed.value === null || parsed.value.length !== group.length) continue;
        for (let index: number = 0; index < group.length; index++) {
          this.recordTranslation(query, group[0].target_language, group[index], parsed.value[index],
            entries);
        }
      } catch (error) {
        KeyboardLog.error(`Tencent translation response unavailable: ${describeError(error)}`);
      }
    }
  }

  private async fetchNiuTranslation(config: NiuTransTranslationConfig, item: TranslationPlanItem,
    epoch: number, handle: number): Promise<string | null> {
    const request: NiuTransTranslationRequest = {
        config: config,
        text: item.key,
        source_language: item.source_language,
        target_language: item.target_language,
        timestamp: String(Date.now())
    };
    const descriptor: TranslationHttpDescriptor | null = this.translationDescriptor(
      client.niuTransTranslationHttpRequest(JSON.stringify(request)));
    if (descriptor === null) return null;
    const body: string | null = await this.translationHttp(descriptor, false, epoch, handle);
    if (body === null) return null;
    try {
      const reply: NativeReply<string | null> = JSON.parse(
        client.parseNiuTransTranslationResponse(body)) as NativeReply<string | null>;
      return reply.ok && reply.value !== null ? reply.value : null;
    } catch {
      return null;
    }
  }

  private async fetchCustomTranslation(config: TranslationProviderConfig, item: TranslationPlanItem,
    epoch: number, handle: number): Promise<string | null> {
    const request: CustomTranslationRequest = {
        config: config,
        text: item.key,
        source_language: item.source_language,
        target_language: item.target_language
    };
    const descriptor: TranslationHttpDescriptor | null = this.translationDescriptor(
      client.customTranslationHttpRequest(JSON.stringify(request)));
    if (descriptor === null) return null;
    const body: string | null = await this.translationHttp(descriptor, true, epoch, handle);
    if (body === null) return null;
    try {
      const reply: NativeReply<string | null> = JSON.parse(
        client.parseCustomTranslationResponse(body)) as NativeReply<string | null>;
      return reply.ok && reply.value !== null ? reply.value : null;
    } catch {
      return null;
    }
  }

  private recordTranslation(query: TranslationQuery, target: string, item: TranslationPlanItem,
    value: string | null, entries: TranslationEntry[]): void {
    if (value === null) {
      this.translationNegativeCache.set(TranslationPolicy.cacheKey(query, target, item),
        Date.now() + TranslationPolicy.NEGATIVE_CACHE_MS);
      return;
    }
    const normalised: string = TranslationPolicy.normalise(value);
    if (normalised.length === 0) {
      this.translationNegativeCache.set(TranslationPolicy.cacheKey(query, target, item),
        Date.now() + TranslationPolicy.NEGATIVE_CACHE_MS);
      return;
    }
    this.translationCache.set(TranslationPolicy.cacheKey(query, target, item), normalised);
    this.translationNegativeCache.delete(TranslationPolicy.cacheKey(query, target, item));
    TranslationPolicy.append(entries, item.text, normalised);
  }

  private translationDescriptor(raw: string): TranslationHttpDescriptor | null {
    try {
      const reply: NativeReply<TranslationHttpDescriptor | null> =
        JSON.parse(raw) as NativeReply<TranslationHttpDescriptor | null>;
      return reply.ok && reply.value !== null ? reply.value : null;
    } catch {
      return null;
    }
  }

  private async translationHttp(descriptor: TranslationHttpDescriptor, allowHttp: boolean,
    epoch: number, handle: number): Promise<string | null> {
    if (!this.translationCurrent(handle, epoch) || typeof descriptor.url !== 'string'
      || descriptor.url.length > 2048 || descriptor.url.includes('\n')
      || descriptor.url.includes('\r')
      || (!descriptor.url.startsWith('https://')
        && !(allowHttp && descriptor.url.startsWith('http://')))) return null;
    if (descriptor.max_response_bytes > TranslationPolicy.MAX_RESPONSE_BYTES) return null;
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(descriptor.url, {
        method: http.RequestMethod.POST,
        header: descriptor.headers,
        connectTimeout: Math.min(3000, Math.max(1000, descriptor.timeout_ms)),
        readTimeout: Math.min(8000, Math.max(1000, descriptor.timeout_ms)),
        extraData: descriptor.body_utf8 !== undefined
          ? descriptor.body_utf8 : JSON.stringify(descriptor.body ?? {})
      });
      if (!this.translationCurrent(handle, epoch) || response.responseCode < 200
        || response.responseCode >= 300 || typeof response.result !== 'string'
        || utf8Length(response.result) > TranslationPolicy.MAX_RESPONSE_BYTES) return null;
      return response.result;
    } catch (error) {
      KeyboardLog.error(`candidate translation request unavailable: ${describeError(error)}`);
      return null;
    } finally {
      request.destroy();
    }
  }

  private translationCurrent(handle: number, epoch: number): boolean {
    return handle !== 0 && handle === this.handle && epoch === this.translationEpoch;
  }

  private feedbackFile(): string {
    return KeyboardSession.feedbackFileIn(this.stateDirectory);
  }

  private static feedbackFileIn(stateRoot: string): string {
    return `${stateRoot}/key-feedback.json`;
  }

  /**
   * The same file, named by a caller that has no live session.
   *
   * The settings page runs in the application rather than in the keyboard extension, so it has a
   * state directory but no session to ask. Both processes read and write the one file.
   */
  static feedbackIn(stateRoot: string): FeedbackSettings {
    try {
      const path: string = KeyboardSession.feedbackFileIn(stateRoot);
      if (!fs.accessSync(path)) {
        return KeyboardFeedback.DEFAULTS;
      }
      return KeyboardFeedback.parse(fs.readTextSync(path));
    } catch (error) {
      KeyboardLog.error(`key feedback unreadable: ${describeError(error)}`);
      return KeyboardFeedback.DEFAULTS;
    }
  }

  static saveFeedbackIn(stateRoot: string, settings: FeedbackSettings): boolean {
    try {
      const handle = fs.openSync(KeyboardSession.feedbackFileIn(stateRoot),
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(handle.fd, KeyboardFeedback.serialize(settings));
      fs.closeSync(handle);
      return true;
    } catch (error) {
      KeyboardLog.error(`key feedback not saved: ${describeError(error)}`);
      return false;
    }
  }

  /** How keys should feel on this device, which is not something the shared preferences carry. */
  feedback(): FeedbackSettings {
    try {
      if (!fs.accessSync(this.feedbackFile())) {
        return KeyboardFeedback.DEFAULTS;
      }
      return KeyboardFeedback.parse(fs.readTextSync(this.feedbackFile()));
    } catch (error) {
      KeyboardLog.error(`key feedback unreadable: ${describeError(error)}`);
      return KeyboardFeedback.DEFAULTS;
    }
  }

  saveFeedback(settings: FeedbackSettings): boolean {
    try {
      const handle = fs.openSync(this.feedbackFile(),
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(handle.fd, KeyboardFeedback.serialize(settings));
      fs.closeSync(handle);
      this.feedbackSettings = settings;
      return true;
    } catch (error) {
      KeyboardLog.error(`key feedback not saved: ${describeError(error)}`);
      return false;
    }
  }

  /**
   * Fires the feedback a key press asks for.
   *
   * Failures are logged once rather than per keystroke: a device without a vibrator would otherwise
   * fill the log with the same line at typing speed.
   */
  private tapFeedback(): void {
    const settings: FeedbackSettings = this.feedbackSettings;
    if (!settings.haptics || this.vibratorFailed) {
      return;
    }
    try {
      vibrator.startVibration(
        { type: 'time', duration: KeyboardFeedback.duration(settings.strength) },
        { usage: 'physicalFeedback' });
    } catch (error) {
      this.vibratorFailed = true;
      KeyboardLog.error(`vibration unavailable: ${describeError(error)}`);
    }
  }

  /** `stateRoot` is `<files>/state`; the shared mobile store owns `<files>/MSIME`. */
  private clipboardRoot(): string {
    const separator: number = this.stateDirectory.lastIndexOf('/');
    return separator > 0 ? this.stateDirectory.substring(0, separator) : '';
  }

  private clearClipboardHistoryFile(): void {
    if (this.stateDirectory.length === 0) {
      return;
    }
    const value: MobileClipboardValue | null = this.mobileClipboard({ operation: 'clear' });
    if (value === null || value.cleared !== true) {
      KeyboardLog.error('clipboard history not cleared');
    }
  }

  /** One locked native transaction; errors never expose clipboard contents in the log. */
  private mobileClipboard(action: MobileClipboardAction): MobileClipboardValue | null {
    const directory: string = this.clipboardRoot();
    if (directory.length === 0) return null;
    const request: MobileClipboardRequest = {
      directory: directory, legacy: 'harmony_state', action: action
    };
    try {
      const reply: MobileClipboardReply = JSON.parse(
        client.mobileClipboardHistory(JSON.stringify(request))) as MobileClipboardReply;
      if (!reply.ok || reply.value === undefined || reply.value === null
        || !Array.isArray(reply.value.entries)) return null;
      return reply.value;
    } catch (error) {
      KeyboardLog.error(`clipboard history unavailable: ${describeError(error)}`);
      return null;
    }
  }

  /** Validate and translate the native camel-case record before it reaches ArkUI. */
  private clipboardEntries(value: MobileClipboardValue): ClipboardHistoryItem[] {
    const rows: ClipboardHistoryItem[] = value.entries.map(
      (entry: NativeClipboardEntry): ClipboardHistoryItem => ({
        text: entry.text, at: entry.timestampMs, pinned: entry.pinned
      }));
    return ClipboardHistoryStore.parse(JSON.stringify(rows));
  }

  /**
   * The saved clipboard history.
   *
   * A file too large to be a history of fifty bounded entries is not read at all: the bound exists
   * so that a wrong or corrupted path cannot turn into an unbounded read.
   */
  clipboardHistory(): ClipboardHistoryItem[] {
    if (!this.clipboardHistoryAllowed()) {
      return [];
    }
    try {
      const value: MobileClipboardValue | null = this.mobileClipboard({ operation: 'load' });
      return value === null ? [] : this.clipboardEntries(value);
    } catch (error) {
      KeyboardLog.error(`clipboard history unreadable: ${describeError(error)}`);
      return [];
    }
  }

  captureClipboardHistory(text: string): ClipboardHistoryMutation {
    if (!this.clipboardHistoryAllowed()) {
      return { entries: [], failure: ClipboardFailure.INVALID_FILE };
    }
    try {
      // Reuse the tested public validation and its specific user-facing failures before crossing
      // the ABI. The native transaction repeats these checks against the persisted document.
      ClipboardHistoryStore.add([], text, Date.now());
      const value: MobileClipboardValue | null = this.mobileClipboard(
        { operation: 'capture', text: text });
      if (value === null) return { entries: [], failure: ClipboardFailure.INVALID_FILE };
      const entries: ClipboardHistoryItem[] = this.clipboardEntries(value);
      if (value.captured !== true) {
        return { entries: entries, failure: value.reason === 'full'
          ? ClipboardFailure.FULL : ClipboardFailure.INVALID_FILE };
      }
      return { entries: entries, failure: null };
    } catch (error) {
      return { entries: [], failure: error instanceof ClipboardHistoryError
        ? error.failure : ClipboardFailure.INVALID_FILE };
    }
  }

  setClipboardPinned(text: string, pinned: boolean): ClipboardHistoryMutation {
    return this.mutateClipboard({ operation: 'set_pinned', text: text, pinned: pinned }, 'updated');
  }

  removeClipboardHistory(text: string): ClipboardHistoryMutation {
    return this.mutateClipboard({ operation: 'remove', text: text }, 'removed');
  }

  clearClipboardHistory(): ClipboardHistoryMutation {
    return this.mutateClipboard({ operation: 'clear' }, 'cleared');
  }

  private mutateClipboard(action: MobileClipboardAction,
                          flag: string): ClipboardHistoryMutation {
    if (!this.clipboardHistoryAllowed()) {
      return { entries: [], failure: ClipboardFailure.INVALID_FILE };
    }
    try {
      const value: MobileClipboardValue | null = this.mobileClipboard(action);
      if (value === null) return { entries: [], failure: ClipboardFailure.INVALID_FILE };
      const succeeded: boolean = flag === 'updated' ? value.updated === true
        : flag === 'removed' ? value.removed === true : value.cleared === true;
      return { entries: this.clipboardEntries(value),
        failure: succeeded ? null : ClipboardFailure.STALE };
    } catch (error) {
      return { entries: [], failure: ClipboardFailure.INVALID_FILE };
    }
  }

  private emojiRecentsFile(): string {
    return `${this.stateDirectory}/emoji_recents.json`;
  }

  /** Recent emoji belong to this keyboard installation, not to the shared preference schema. */
  emojiRecents(): string[] {
    if (this.stateDirectory.length === 0) {
      return [];
    }
    const file: string = this.emojiRecentsFile();
    try {
      if (!fs.accessSync(file) || fs.statSync(file).size > EMOJI_RECENTS_MAX_BYTES) {
        return [];
      }
      return EmojiCatalogModel.parseRecents(fs.readTextSync(file));
    } catch (error) {
      KeyboardLog.error(`emoji recents unavailable: ${describeError(error)}`);
      return [];
    }
  }

  recordEmojiRecent(text: string): string[] {
    let recents: string[];
    try {
      recents = EmojiCatalogModel.recordRecent(this.emojiRecents(), text);
    } catch (error) {
      KeyboardLog.error(`emoji recent rejected: ${describeError(error)}`);
      return this.emojiRecents();
    }
    if (this.stateDirectory.length === 0) {
      return recents;
    }
    try {
      const handle = fs.openSync(this.emojiRecentsFile(),
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, EmojiCatalogModel.serializeRecents(recents));
      } finally {
        fs.closeSync(handle);
      }
    } catch (error) {
      KeyboardLog.error(`emoji recents not persisted: ${describeError(error)}`);
    }
    return recents;
  }

  clearEmojiRecents(): boolean {
    if (this.stateDirectory.length === 0) {
      return false;
    }
    try {
      const handle = fs.openSync(this.emojiRecentsFile(),
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, '[]');
      } finally {
        fs.closeSync(handle);
      }
      return true;
    } catch (error) {
      KeyboardLog.error(`emoji recents not cleared: ${describeError(error)}`);
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

  /** Reads only the bounded, app-private reply templates explicitly shared by the settings app. */
  communityReplyTemplates(): CommunityReplyTemplate[] {
    // KeyboardExtensionAbility passes files/state as stateDirectory; the settings process shares
    // its explicit library one level above, at files/CommunityLibrary.json.
    const file: string = `${this.stateDirectory}/../CommunityLibrary.json`;
    try {
      if (!fs.accessSync(file) || fs.statSync(file).size > CommunityReplyLibraryPolicy.MAX_BYTES) {
        return [];
      }
      return CommunityReplyLibraryPolicy.parse(fs.readTextSync(file));
    } catch (error) {
      KeyboardLog.error(`community reply library unavailable: ${describeError(error)}`);
      return [];
    }
  }

  /** Generates bounded reply candidates through the shared AI ABI without involving Engine state. */
  async thoughtfulReplies(source: string, style: string, extraPrompt: string = ''): Promise<string[]> {
    const request: ReplyRequest | null = ReplyKeyboardPolicy.request(source, style, extraPrompt);
    if (request === null || !this.aiAssistant.enabled || this.aiAssistant.endpoint.length === 0) {
      return [];
    }
    const editorGeneration: number = this.editorGeneration;
    const contextGeneration: number = this.replyContextGeneration;
    const config: PreparedAiAssistant = {
      enabled: this.aiAssistant.enabled, provider: this.aiAssistant.provider,
      model: this.aiAssistant.model, token: this.aiAssistant.token, tokens: this.aiAssistant.tokens,
      endpoint: this.aiAssistant.endpoint, candidate_limit: 3, prompt_id: this.aiAssistant.prompt_id,
      prompt: request.prompt, prompt_custom_1: this.aiAssistant.prompt_custom_1,
      prompt_custom_2: this.aiAssistant.prompt_custom_2, prompt_custom_3: this.aiAssistant.prompt_custom_3
    };
    const input: AiHttpRequestInput = {
      segmented_pinyin: ['reply'], context: request.source, candidate_limit: 3
    };
    const payload: AiHttpRequest = { config: config, input: input };
    const document: string = JSON.stringify(payload);
    let descriptor: AiHttpDescriptor | null;
    try {
      const raw: NativeReply<AiHttpDescriptor | null> = JSON.parse(
        client.aiHttpRequest(document)) as NativeReply<AiHttpDescriptor | null>;
      if (!raw.ok || raw.value === null) return [];
      descriptor = raw.value;
    } catch (error) {
      KeyboardLog.error(`thoughtful reply request unavailable: ${describeError(error)}`);
      return [];
    }
    const requestHttp = http.createHttp();
    try {
      const response: http.HttpResponse = await requestHttp.request(descriptor.url, {
        method: http.RequestMethod.POST, header: descriptor.headers,
        connectTimeout: Math.min(8000, Math.max(1000, descriptor.connect_timeout_ms)),
        readTimeout: Math.min(10000, Math.max(1000, descriptor.timeout_ms)),
        extraData: JSON.stringify(descriptor.body)
      });
      if (!ReplyContextPolicy.matches(editorGeneration, this.editorGeneration,
        contextGeneration, this.replyContextGeneration)
        || this.inputClient === undefined
        || response.responseCode < 200 || response.responseCode >= 300
        || typeof response.result !== 'string'
        || utf8Length(response.result) > descriptor.max_response_bytes) return [];
      const parsed: NativeReply<string[] | null> = JSON.parse(client.parseAiResponse(
        response.result, 3)) as NativeReply<string[] | null>;
      const results: string[] = parsed.ok ? ReplyKeyboardPolicy.results(parsed.value) : [];
      if (!ReplyContextPolicy.matches(editorGeneration, this.editorGeneration,
        contextGeneration, this.replyContextGeneration) || results.length === 0) return [];
      this.replyResultEditorGeneration = editorGeneration;
      this.replyResultContextGeneration = contextGeneration;
      this.replyResultTexts = results;
      return results;
    } catch (error) {
      KeyboardLog.error(`thoughtful reply unavailable: ${describeError(error)}`);
      return [];
    } finally {
      requestHttp.destroy();
    }
  }

  /** Insert a reply only if it was generated for the still-current editor context. */
  insertReply(text: string): boolean {
    if (!ReplyContextPolicy.matches(this.replyResultEditorGeneration, this.editorGeneration,
      this.replyResultContextGeneration, this.replyContextGeneration)
      || !this.replyResultTexts.includes(text)) return false;
    this.insertWithSource(text, 'reply');
    this.invalidateReplyContext();
    return true;
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
  /**
   * The four preference values one scheme choice decides, read against the document on disk.
   *
   * Picking Japanese has to leave a record of the Chinese scheme it replaced, or the shared settings
   * page has nothing to restore when the user asks for 中文 again and falls back to quanpin — which
   * on a typist who was on 五笔 looks like the keyboard forgot. The Engine's own scheme field cannot
   * hold it, since it is the field being replaced.
   *
   * Read here rather than from the prepared record the view holds: the settings page is a second
   * writer, and the value that matters is the one currently on disk. The write that follows does its
   * own load and compares revisions, so a genuine conflict is still refused rather than overwritten.
   */
  /**
   * Write back a scheme the enabled list moved the keyboard to, and say whether it moved.
   *
   * The shared settings page owns which schemes are offered. Turn off the one the keyboard is on
   * and it vanishes from the picker while the keyboard goes on using it — there is then no way to
   * see or leave it short of choosing something else. MSIME-Apple normalizes the stored scheme the
   * moment the enabled list is written (DisabledSchemesAreHiddenAndCurrentSchemeFallsBack); this
   * host reads the list at attach instead, because the page and the keyboard are separate processes
   * and the write the page makes is to the document, not to a running keyboard.
   *
   * The decision stays in mappingForRuntimeSelection: whether the pair is a move at all, and that
   * the reply keyboard is never a destination, are the two things it answers.
   */
  applyRuntimeSelection(applied: SchemeDefinition, selected: SchemeDefinition): boolean {
    const current: Record<string, Object> | undefined = this.loadPreferenceDocument();
    const mapping: PreferenceMapping | null = KeyboardScheme.mappingForRuntimeSelection(
      applied, selected,
      current === undefined ? null : this.text(current['last_chinese_scheme']),
      current === undefined ? null : this.text(current['shuangpin_profile']));
    if (mapping === null) {
      return false;
    }
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('scheme', mapping.scheme);
    changes.set('last_chinese_scheme', mapping.lastChineseScheme);
    changes.set('shuangpin_profile', mapping.shuangpinProfile);
    changes.set('touch_keyboard_layout', mapping.touchKeyboardLayout);
    if (!this.changePreferences(changes)) {
      return false;
    }
    this.useScheme(selected.engineScheme, selected.shuangpinProfile);
    KeyboardLog.info(`scheme fell back to ${selected.preferenceId}: `
      + `${applied.preferenceId} is no longer enabled`);
    return true;
  }

  schemeChanges(candidate: SchemeDefinition): Map<string, Object> {
    const current: Record<string, Object> | undefined = this.loadPreferenceDocument();
    const mapping: PreferenceMapping = KeyboardScheme.mapping(candidate,
      current === undefined ? null : this.text(current['last_chinese_scheme']),
      current === undefined ? null : this.text(current['shuangpin_profile']));
    const changes: Map<string, Object> = new Map<string, Object>();
    changes.set('scheme', mapping.scheme);
    changes.set('last_chinese_scheme', mapping.lastChineseScheme);
    changes.set('shuangpin_profile', mapping.shuangpinProfile);
    changes.set('touch_keyboard_layout', mapping.touchKeyboardLayout);
    return changes;
  }

  /** The stored document, or undefined when it cannot be read; the caller then uses the defaults. */
  private loadPreferenceDocument(): Record<string, Object> | undefined {
    try {
      const loaded: SnapshotResponse =
        JSON.parse(client.loadPreferences(this.stateDirectory)) as SnapshotResponse;
      if (!loaded.ok) {
        KeyboardLog.error(`preferences unreadable: ${loaded.error}`);
        return undefined;
      }
      return loaded.value.preferences;
    } catch (error) {
      KeyboardLog.error(`preferences unreadable: ${describeError(error)}`);
      return undefined;
    }
  }

  /** A stored value only counts as a scheme name if it is actually a string. */
  private text(value: Object | undefined): string | null {
    return typeof value === 'string' ? value as string : null;
  }

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
      const nextClipboardHistory: boolean = ClipboardHistoryPreferencePolicy.enabled(
        snapshot.preferences['clipboard_history']);
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
      this.clipboardHistoryEnabled = nextClipboardHistory;
      if (changes.has('voice_input')) {
        this.voiceInput = snapshot.preferences.voice_input as VoiceInputConfiguration;
        if (this.onVoiceInputChanged !== undefined) {
          this.onVoiceInputChanged(this.voiceInputEnabled());
        }
      }
      if (ClipboardHistoryPreferencePolicy.shouldClearHistory(nextClipboardHistory)) {
        this.clearClipboardHistoryFile();
      }
      if (this.onClipboardHistoryChanged !== undefined) {
        this.onClipboardHistoryChanged(nextClipboardHistory);
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
    return this.emojiCatalogPage('emoji', group, offset, limit);
  }

  emojiCatalogPage(category: string, group: string, offset: number, limit: number,
                  parent: string = '', search: string = ''): EmojiPage | null {
    const query: EmojiQuery = {
      category: category,
      limit: limit,
      offset: offset,
      group: group,
      cursor: true,
      list_groups: false,
      list_symbol_groups: false,
      parent: parent,
      search: search
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

  emojiGroups(category: string): string[] {
    const query: EmojiQuery = {
      category: category,
      limit: 1,
      offset: 0,
      group: '',
      cursor: false,
      list_groups: true,
      list_symbol_groups: false,
      parent: '',
      search: ''
    };
    try {
      const raw: string = client.emojiCatalog(JSON.stringify(query), this.resourceDirectory);
      const response: EmojiGroupsResponse = JSON.parse(raw) as EmojiGroupsResponse;
      if (!response.ok || !Array.isArray(response.value.groups)) {
        return [];
      }
      return normalizeGroups(response.value.groups);
    } catch (error) {
      KeyboardLog.error(`emoji groups unavailable: ${describeError(error)}`);
      return [];
    }
  }

  emojiSymbolGroups(): EmojiSymbolGroup[] {
    const query: EmojiQuery = {
      category: 'symbols',
      limit: 1,
      offset: 0,
      group: '',
      cursor: false,
      list_groups: false,
      list_symbol_groups: true,
      parent: '',
      search: ''
    };
    try {
      const raw: string = client.emojiCatalog(JSON.stringify(query), this.resourceDirectory);
      const response: EmojiSymbolGroupsResponse = JSON.parse(raw) as EmojiSymbolGroupsResponse;
      if (!response.ok || !Array.isArray(response.value.symbol_groups)) {
        return [];
      }
      return normalizeSymbolGroups(response.value.symbol_groups);
    } catch (error) {
      KeyboardLog.error(`emoji symbol groups unavailable: ${describeError(error)}`);
      return [];
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
      const output: string = this.asTraditional(widened === null ? text : widened);
      this.insertEditorText(output);
      this.recordTypingStatistics(output, this.typingSource());
      this.refreshEnglishSuggestions();
    }
  }

  /**
   * Offer completions for the English word being typed.
   *
   * Only in direct English with nothing composing: a pinyin composition already has a candidate
   * strip of its own, and the two would be competing for it. The query is a packaged-dictionary
   * lookup that creates no session, so it runs off the UI thread and its answer is checked against
   * the word still in the editor before anything is drawn.
   */
  private refreshEnglishSuggestions(): void {
    if (!this.englishSuggestionsEnabled || !this.englishMode || this.composing()
        || this.inputClient === undefined || this.resourceDirectory.length === 0) {
      this.clearEnglishSuggestions();
      return;
    }
    const prefix: string = this.englishWordBeforeCursor();
    if (!EnglishSuggestionPolicy.suggestible(prefix)) {
      this.clearEnglishSuggestions();
      return;
    }
    if (prefix === this.englishSuggestionRequested) {
      return;
    }
    const epoch: number = ++this.englishSuggestionEpoch;
    this.englishSuggestionRequested = prefix;
    const request: EnglishCompletionRequest = { prefix: prefix, limit: EnglishSuggestionPolicy.LIMIT };
    const resources: string = this.resourceDirectory;
    // A promise rather than a direct call: the lookup opens a packaged dictionary, and the keyboard
    // has to keep drawing while it happens.
    Promise.resolve().then((): string =>
      client.englishCompletions(JSON.stringify(request), resources)
    ).then((raw: string): void => {
      const completions: EnglishCompletions | null = EnglishSuggestionPolicy.decode(raw);
      this.applyEnglishSuggestions(epoch, prefix, completions);
    }).catch((error: Object): void => {
      // Completions are optional display state; a failed lookup never blocks input.
      KeyboardLog.error(`english completions unavailable: ${describeError(error)}`);
    });
  }

  private applyEnglishSuggestions(epoch: number, prefix: string,
                                  completions: EnglishCompletions | null): void {
    if (epoch !== this.englishSuggestionEpoch || completions === null
        || completions.prefix !== prefix || prefix !== this.englishWordBeforeCursor()) {
      return;
    }
    this.englishSuggestions = completions.items;
    this.englishSuggestionPrefix = prefix;
    this.publishEnglishSuggestions();
  }

  private clearEnglishSuggestions(): void {
    this.englishSuggestionEpoch++;
    this.englishSuggestionRequested = '';
    if (this.englishSuggestions.length === 0 && this.englishSuggestionPrefix.length === 0) {
      return;
    }
    this.englishSuggestions = [];
    this.englishSuggestionPrefix = '';
    this.publishEnglishSuggestions();
  }

  private publishEnglishSuggestions(): void {
    if (this.onEnglishSuggestions !== undefined) {
      this.onEnglishSuggestions(this.englishSuggestionPrefix, this.englishSuggestions.slice());
    }
  }

  /** What the editor says is immediately before the caret, as far back as a word can run. */
  private englishWordBeforeCursor(): string {
    if (this.inputClient === undefined) {
      return '';
    }
    try {
      return EnglishSuggestionPolicy.currentWord(
        this.inputClient.getForwardSync(EnglishSuggestionPolicy.CONTEXT_CHARACTERS));
    } catch (error) {
      return '';
    }
  }

  /**
   * Accept a completion, replacing the letters it completes.
   *
   * The word is re-read rather than trusted: the list was drawn some keystrokes ago, and if the
   * editor has moved on since then the deletion would eat text the completion was never about.
   */
  useEnglishSuggestion(index: number): void {
    if (index < 0 || index >= this.englishSuggestions.length || this.inputClient === undefined) {
      return;
    }
    const typed: string = this.englishWordBeforeCursor();
    if (typed !== this.englishSuggestionPrefix) {
      this.clearEnglishSuggestions();
      return;
    }
    const replacement: EnglishReplacement | null = EnglishSuggestionPolicy.replacement(
      typed, this.englishSuggestions[index],
      EnglishSuggestionPolicy.startedCapitalized(typed));
    if (replacement === null) {
      this.clearEnglishSuggestions();
      return;
    }
    try {
      this.deleteEditorBackwardSync(replacement.deleteCount);
    } catch (error) {
      KeyboardLog.error(`english completion could not replace the word: ${describeError(error)}`);
      this.clearEnglishSuggestions();
      return;
    }
    this.insert(replacement.insert);
    this.clearEnglishSuggestions();
  }

  /** The five switches as the policy reads them; an older document keeps the shared defaults. */
  private static hotkeyBindings(voice: VoiceInputConfiguration): VoiceHotkeyBindings {
    return {
      ralt: voice.hotkey_ralt ?? DEFAULT_VOICE_HOTKEY_BINDINGS.ralt,
      ctrlWin: voice.hotkey_ctrl_win ?? DEFAULT_VOICE_HOTKEY_BINDINGS.ctrlWin,
      rctrlRalt: voice.hotkey_rctrl_ralt ?? DEFAULT_VOICE_HOTKEY_BINDINGS.rctrlRalt,
      holdSpaceLock: voice.hotkey_hold_space_lock ?? DEFAULT_VOICE_HOTKEY_BINDINGS.holdSpaceLock,
      ctrlF9: voice.hotkey_ctrl_f9 ?? DEFAULT_VOICE_HOTKEY_BINDINGS.ctrlF9
    };
  }

  /**
   * Offer a hardware key to the voice shortcuts.
   *
   * Returns whether the key was claimed, so the caller knows not to hand it on.
   */
  routeVoiceHotkey(key: VoiceKey): boolean {
    if (!this.voiceInputEnabled()) {
      return false;
    }
    const action: VoiceHotkeyAction = this.voiceHotkeys.accept(key, this.voiceRecording);
    if (action === VoiceHotkeyAction.NONE) {
      return false;
    }
    if (this.onVoiceHotkey !== undefined) {
      this.onVoiceHotkey(action);
    }
    return true;
  }

  /**
   * The view says when the recognizer starts and stops.
   *
   * A recording that ended by itself — a final result, a provider failure — leaves no hold or lock
   * behind, or the next press of the hold key would be read as the release of a recording that is
   * no longer running.
   */
  setVoiceRecording(active: boolean, cancelled: boolean = false): void {
    const changed: boolean = this.voiceRecording !== active;
    this.voiceRecording = active;
    if (!active) {
      this.voiceHotkeys.reset();
    }
    if (!changed) {
      return;
    }
    // Tones and quiet are display-only work around the recording, never in its way: a failure here
    // is logged inside the behaviour and the recording carries on regardless.
    if (active) {
      this.voiceBehaviour.starting(this.voiceInput).catch((error: Object): void => {
        KeyboardLog.error(`voice start behaviour failed: ${describeError(error)}`);
      });
      return;
    }
    const done: Promise<void> = cancelled
      ? this.voiceBehaviour.cancelled() : this.voiceBehaviour.finished(this.voiceInput);
    done.catch((error: Object): void => {
      KeyboardLog.error(`voice end behaviour failed: ${describeError(error)}`);
    });
  }

  /** The extension's context, which is what turns a packaged tone into something playable. */
  useVoiceContext(context: common.Context): void {
    this.voiceBehaviour.use(context);
  }

  /** Whether the current recording outlives its hold key, for the panel that says so. */
  voiceHotkeyLocked(): boolean {
    return this.voiceHotkeys.isLocked();
  }

  /** Insert a platform-produced result and attribute it to its actual source. */
  insertWithSource(text: string, source: string): void {
    if (this.inputClient === undefined || text.length === 0) return;
    const output: string = this.asTraditional(text);
    this.insertEditorText(output);
    this.recordTypingStatistics(output, source);
  }

  private typingSource(): string {
    return TypingStatisticsPolicy.source(this.schemeName, this.profileName, this.englishMode,
      this.nineKeyMode, this.localMode);
  }

  private clearSmartPunctuationRepeat(): void {
    this.smartPunctuationSnapshot = null;
  }

  /**
   * Rewrites a just-committed Chinese mark as ASCII when the next key is a space.
   *
   * Returns whether it did, because the caller must then not also deliver the space: the user is
   * correcting the mark they just typed, not typing a mark and then a space.
   *
   * What is actually before the caret is re-read here rather than trusted from the arming. The
   * arming records what was committed; anything may have happened since, and the source declines
   * in exactly the same way when the two disagree.
   */
  convertPunctuationSpace(character: number): boolean {
    const snapshot: SmartPunctuationSpaceSnapshot | null = this.smartPunctuationSpaceSnapshot;
    if (snapshot === null || character !== 0x20 || this.inputClient === undefined) {
      return false;
    }
    let preceding: number = 0;
    try {
      preceding = SmartPunctuationContext.precedingCodePoint(this.inputClient.getForwardSync(2));
    } catch (error) {
      KeyboardLog.error(`punctuation space context unavailable: ${describeError(error)}`);
      this.clearSmartPunctuationSpace();
      return false;
    }
    const decision: SpaceConvertDecision = SmartPunctuationSpacePolicy.decide(
      snapshot, character, preceding, this.editing.length > 0, this.editorGeneration);
    if (decision !== SpaceConvertDecision.CONVERT) {
      this.clearSmartPunctuationSpace();
      return false;
    }
    const ascii: string = String.fromCharCode(snapshot.ascii);
    try {
      // The preceding scalar was just checked to be the armed mark, so this cannot eat other text.
      this.deleteEditorBackwardSync(1);
      this.insertEditorTextSync(ascii);
      this.recordTypingStatistics(ascii, this.typingSource());
    } catch (error) {
      KeyboardLog.error(`punctuation space conversion unavailable: ${describeError(error)}`);
      this.clearSmartPunctuationSpace();
      return false;
    }
    this.clearSmartPunctuationSpace();
    // Typing the same mark again turns it back, which is the existing repeat behaviour and what the
    // source arms at this point too: the conversion has to be undoable without reaching for
    // backspace, or a mis-fire costs more than it saves.
    this.smartPunctuationSnapshot = SmartPunctuationRepeatPolicy.snapshot(
      snapshot.ascii, ascii, Date.now(), this.editorGeneration);
    return true;
  }

  private clearSmartPunctuationSpace(): void {
    this.smartPunctuationSpaceSnapshot = null;
  }

  private canArmSmartPunctuationRepeat(ascii: number, preceding: number): boolean {
    const view: EngineView | undefined = this.lastView;
    const dedicatedEnglish: boolean = view?.dedicated_english ?? this.englishMode;
    return this.smartPunctuation && this.smartPunctuationRepeat
      && this.chinesePunctuation && this.punctuationLock === 'follow'
      && !dedicatedEnglish && this.localMode === 'none' && this.schemeName !== 'japanese'
      && this.editing.length === 0 && this.currentCandidates.length === 0
      && SmartPunctuationRepeatPolicy.chineseMark(ascii) !== null
      && SmartPunctuationRepeatPolicy.isAsciiAlphanumeric(preceding);
  }

  private recordTypingStatistics(text: string, source: string): void {
    if (text.length === 0 || this.stateDirectory.length === 0) return;
    // One Date for both fields: a day and an hour read from separate instants either side of
    // midnight would file the commit under one day and the other day's hour.
    const instant: Date = new Date();
    const action: TypingStatisticsRecordAction = {
      operation: 'record', text: text, source: source,
      day: TypingStatisticsPolicy.day(instant), hour: TypingStatisticsPolicy.hour(instant)
    };
    const requestDocument: TypingStatisticsRecordRequest = {
      directory: this.stateDirectory, action: action
    };
    const request: string = JSON.stringify(requestDocument);
    // Native storage takes a file lock. Defer it off the key event so a slow filesystem never
    // changes the latency of the next key, while retaining the same bounded text and source.
    setTimeout((): void => {
      try {
        const response: string = client.typingStatistics(request);
        const value: Record<string, Object> = JSON.parse(response) as Record<string, Object>;
        if (value.ok !== true) KeyboardLog.error('typing statistics write refused');
      } catch (error) {
        KeyboardLog.error(`typing statistics unavailable: ${describeError(error)}`);
      }
    }, 0);
  }

  /**
   * Every candidate for what is being spelled, not just the page on screen.
   *
   * Paging was the only way past the ninth candidate, which put the tail of a long answer dozens of
   * taps away. Showing the whole list at once is the arrangement the iOS keyboard settled on for the
   * same reason.
   */
  /**
   * Every candidate the composition has, not just the page the strip shows.
   *
   * Returns the entries rather than their text. The native record has carried the annotation and
   * the translation all along and this threw both away, so the expanded panel could draw a list of
   * words with no glosses under them while the strip beside it had them — and the gloss the long
   * press offers had nothing to read. Only the fields the panel uses are filled: the management
   * operations index the page rather than this list, so the source does not offer them here either.
   */
  allCandidates(): ExpandedCandidate[] {
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
      const entries: ExpandedCandidate[] = [];
      for (const candidate of response.value.candidates) {
        entries.push({
          text: candidate.text,
          annotation: CandidateGlossPolicy.annotation(candidate.annotation,
            candidate.translation ?? null, this.candidateEnglishGloss),
          annotationIsTranslation: CandidateGlossPolicy.annotationIsTranslation(
            candidate.annotation, candidate.translation ?? null, this.candidateEnglishGloss)
        });
      }
      return entries;
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
    this.fixCandidatePosition(index, 1);
  }

  fixCandidatePosition(index: number, position: number): void {
    if (this.handle === 0) {
      return;
    }
    // Checked here rather than trusted from the menu. Today the menu is the only caller and it only
    // ever builds slots 1 to 5, so this throws for nobody; it is here because this is the last point
    // before the slot becomes an argument to the Engine, and a session method is callable by
    // anything in the host.
    this.apply(client.fixCandidatePosition(this.handle, this.generation, index,
      CandidateManagementAction.validatePosition(position)));
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

  /**
   * The Windows maintenance chord's target, checked before it is acted on.
   *
   * The hardware key says which slot; whether that slot holds a candidate the user dictionary can
   * be asked to forget is this side's business. Cloud, AI, Emoji and Japanese candidates come from
   * sources the Host API would refuse, and a chord that silently does nothing eight times is worse
   * than one that was never claimed — so the caller is told whether it was acted on.
   */
  /**
   * Throw away the Engine's candidate cache for this session.
   *
   * The other half of the Windows maintenance pair: the slot keys remove one candidate the
   * dictionary got wrong, this one clears everything the Engine has cached when the whole list looks
   * stale. Nothing the user typed is lost — the view is refreshed, not the composition.
   */
  resetCache(): void {
    if (this.handle === 0) {
      return;
    }
    this.applyView(client.resetCache(this.handle));
  }

  removeManagedCandidate(index: number): boolean {
    const view: EngineView | undefined = this.lastView;
    if (this.handle === 0 || view === undefined || index < 0
        || index >= view.candidates.length) {
      return false;
    }
    const candidate: Candidate = view.candidates[index];
    if (!CandidateManagementAction.candidateActionsAvailable(
        KeyboardScheme.engineSchemeName(view.scheme), candidate.source)) {
      return false;
    }
    this.apply(client.removeCandidate(this.handle, this.generation, index));
    return true;
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
