/**
 * Behavioural checks for the logic ported from the Android keyboard.
 *
 * HarmonyOS's own test framework (hypium) is instrumented: it needs a device or emulator, which the
 * HarmonyOS phone image is currently gated behind account eligibility. These classes hold no ArkUI or
 * NAPI dependency, so they run under plain node, and the assertions are written against the Java
 * source they were ported from rather than against the port.
 */
import { KeyboardGeometry } from '../entry/src/main/ets/keyboard/KeyboardGeometry';
import { KeyboardMetrics } from '../entry/src/main/ets/keyboard/KeyboardMetrics';
import {
  ClipboardHistoryStore, ClipboardHistoryItem, ClipboardHistoryError, ClipboardFailure
} from '../entry/src/main/ets/keyboard/clipboard/ClipboardHistoryStore';
import {
  EmojiCatalogModel, EmojiItem, EMOJI_PAGE_SIZE, EMOJI_RECENTS_LIMIT, MAX_TEXT_CODE_POINTS,
  normalizeGroups, normalizeSymbolGroups
} from '../entry/src/main/ets/keyboard/emoji/EmojiCatalogModel';
import { CandidateWrapPolicy } from '../entry/src/main/ets/keyboard/candidate/CandidateWrapPolicy';
import { KeyboardScheme, SchemeDefinition, PreferenceMapping }
  from '../entry/src/main/ets/keyboard/KeyboardScheme';
import { ReplyKeyboardPolicy } from '../entry/src/main/ets/keyboard/ReplyKeyboardPolicy';
import { ReplyContextPolicy } from '../entry/src/main/ets/keyboard/ReplyContextPolicy';
import { CommunityReplyLibraryPolicy } from '../entry/src/main/ets/keyboard/CommunityReplyLibraryPolicy';
import { NineKeyLayout, NineKey } from '../entry/src/main/ets/keyboard/input/NineKeyLayout';
import {
  JapaneseNineKeyLayout, JapaneseKey, VariantGroup,
  DIRECTION_CENTRE, DIRECTION_LEFT, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_DOWN
} from '../entry/src/main/ets/keyboard/input/JapaneseNineKeyLayout';
import { JapaneseNineKeyActions } from '../entry/src/main/ets/keyboard/input/JapaneseNineKeyActions';
import { ChineseHelpcodePolicy } from '../entry/src/main/ets/keyboard/input/ChineseHelpcodePolicy';
import { WubiCodeHintPolicy } from '../entry/src/main/ets/keyboard/input/WubiCodeHintPolicy';
import { LetterKeyFacePolicy } from '../entry/src/main/ets/keyboard/input/LetterKeyFacePolicy';
import { EnglishCapitalizationPolicy, CapitalizationMode }
  from '../entry/src/main/ets/keyboard/input/EnglishCapitalizationPolicy';
import { EnglishLetterCaseState, LetterCaseMode }
  from '../entry/src/main/ets/keyboard/input/EnglishLetterCaseState';
import { JapaneseVariantPolicy } from '../entry/src/main/ets/keyboard/input/JapaneseVariantPolicy';
import { ClipboardHistoryPolicy } from '../entry/src/main/ets/keyboard/clipboard/ClipboardHistoryPolicy';
import { FullWidthInputPolicy } from '../entry/src/main/ets/keyboard/input/FullWidthInputPolicy';
import { InputDiagnosticPolicy } from '../entry/src/main/ets/keyboard/input/InputDiagnosticPolicy';
import { ChineseOutputPolicy } from '../entry/src/main/ets/keyboard/input/ChineseOutputPolicy';
import { LocalInputMode } from '../entry/src/main/ets/keyboard/input/LocalInputMode';
import { QuickPunctuationPolicy, PunctuationEntry }
  from '../entry/src/main/ets/keyboard/input/QuickPunctuationPolicy';
import { SmartPunctuationContext } from
  '../entry/src/main/ets/keyboard/input/SmartPunctuationContext';
import {
  SmartPunctuationRepeatPolicy, SmartPunctuationRepeatSnapshot
} from '../entry/src/main/ets/keyboard/input/SmartPunctuationRepeatPolicy';
import { PairedPunctuationPolicy } from
  '../entry/src/main/ets/keyboard/input/PairedPunctuationPolicy';
import { ReturnKeyAction } from '../entry/src/main/ets/keyboard/input/ReturnKeyAction';
import { SpaceCursorMovement } from '../entry/src/main/ets/keyboard/input/SpaceCursorMovement';
import { CandidateManagementAction, ManagementAction }
  from '../entry/src/main/ets/keyboard/candidate/CandidateManagementAction';
import { CandidateGlossPolicy, GlossToken }
  from '../entry/src/main/ets/keyboard/candidate/CandidateGlossPolicy';
import { ShuangpinKeyHintPolicy } from '../entry/src/main/ets/keyboard/input/ShuangpinKeyHintPolicy';
import { EditorPolicy, EditorTraits } from '../entry/src/main/ets/keyboard/input/EditorPolicy';
import { KeyboardSkin } from '../entry/src/main/ets/keyboard/skin/KeyboardSkin';
import { ToolbarSkinPolicy } from '../entry/src/main/ets/keyboard/ToolbarSkinPolicy';
import { CustomKeyboardSkin, CustomSkinDocument, supportedPhoto }
  from '../entry/src/main/ets/keyboard/skin/CustomKeyboardSkin';
import { DictionaryMaintenancePolicy }
  from '../entry/src/main/ets/keyboard/DictionaryMaintenancePolicy';
import {
  HandwritingStrokePolicy, HANDWRITING_CANVAS_SIZE, HANDWRITING_MAX_CANDIDATES,
} from '../entry/src/main/ets/keyboard/input/HandwritingStrokePolicy';
import { VoiceRecognitionPolicy, VOICE_MAX_TEXT } from
  '../entry/src/main/ets/keyboard/input/VoiceRecognitionPolicy';
import { AccountCloudBridge, AccountSessionStore, AccountTransport } from
  '../entry/src/main/ets/account/AccountCloudBridge';
import { TypingStatisticsPolicy } from '../entry/src/main/ets/keyboard/TypingStatisticsPolicy';
import { OnlineCandidatePolicy } from
  '../entry/src/main/ets/keyboard/candidate/OnlineCandidatePolicy';
import { TranslationPolicy, TranslationQuery, TranslationEntry } from
  '../entry/src/main/ets/keyboard/candidate/TranslationPolicy';
import { TranslationSensePolicy } from
  '../entry/src/main/ets/keyboard/candidate/TranslationSensePolicy';
import { HardwareKeyRouter, HardwareKeyAction, HardwareKey } from
  '../entry/src/main/ets/keyboard/HardwareKeyRouter';
import { CandidateTextPolicy, CandidateTextEdge } from
  '../entry/src/main/ets/keyboard/input/CandidateTextPolicy';
import { CandidateSkinPolicy } from '../entry/src/main/ets/keyboard/candidate/CandidateSkinPolicy';
import { CandidateSkinCatalogPolicy, CandidateSkinPackage } from
  '../entry/src/main/ets/keyboard/candidate/CandidateSkinCatalogPolicy';
import { CandidateWidthPolicy } from '../entry/src/main/ets/keyboard/candidate/CandidateWidthPolicy';
import { CandidatePresentationPolicy } from '../entry/src/main/ets/keyboard/candidate/CandidatePresentationPolicy';
import { CandidateWheelPolicy } from '../entry/src/main/ets/keyboard/candidate/CandidateWheelPolicy';
import { CandidateAnchorPolicy, CandidateAnchor }
  from '../entry/src/main/ets/inputmethodextability/CandidateAnchorPolicy';
import { FloatingToolbarLayout, ToolbarButton }
  from '../entry/src/main/ets/keyboard/FloatingToolbarLayout';
import { FloatingToolbarDragPolicy } from '../entry/src/main/ets/keyboard/FloatingToolbarDragPolicy';

function selectedBarVisible(value: boolean | null): boolean {
  return value !== false;
}

let failures = 0;
let checks = 0;

/** Kept local so the suite needs no node type definitions, which this repository does not carry. */
function assertOk(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertThrows(body: () => void, pattern: RegExp, message: string): void {
  try {
    body();
  } catch (error) {
    const text = error instanceof Error ? error.message : String(error);
    if (!pattern.test(text)) {
      throw new Error(`${message}: threw "${text}", expected ${pattern}`);
    }
    return;
  }
  throw new Error(`${message}: nothing was thrown`);
}

function group(name: string, body: () => void): void {
  try {
    body();
    console.log(`  ok  ${name}`);
  } catch (error) {
    failures++;
    console.log(`FAIL  ${name}`);
    console.log(`      ${error instanceof Error ? error.message : String(error)}`);
  }
}

function check(condition: boolean, message: string): void {
  checks++;
  assertOk(condition, message);
}

console.log('KeyboardGeometry');

console.log('DictionaryMaintenancePolicy');

console.log('HandwritingStrokePolicy');

console.log('VoiceRecognitionPolicy');

group('maps Harmony commits to shared typing-statistics sources', () => {
  check(TypingStatisticsPolicy.source('quanpin', 'xiaohe', false, false, 'none') === 'quanpin',
    'quanpin uses the shared source id');
  check(TypingStatisticsPolicy.source('quanpin', 'xiaohe', false, true, 'none') === 'nineKey',
    'nine-key quanpin has its own source id');
  check(TypingStatisticsPolicy.source('shuangpin', 'microsoft', false, false, 'none') === 'microsoft',
    'shuangpin profile is retained');
  check(TypingStatisticsPolicy.source('wubi', 'xiaohe', false, false, 'none') === 'wubi',
    'wubi uses the shared source id');
  check(TypingStatisticsPolicy.source('quanpin', 'xiaohe', true, false, 'none') === 'english',
    'dedicated English takes precedence');
  check(TypingStatisticsPolicy.source('quanpin', 'xiaohe', false, false, 'emoji') === 'local',
    'local modes are attributed as local input');
  check(TypingStatisticsPolicy.source('quanpin', 'xiaohe', false, false,
    'temporary_japanese') === 'japanese', 'temporary Japanese retains its language source');
  check(TypingStatisticsPolicy.day(new Date(2026, 8, 19)) === '2026-09-19',
    'day keys use the native local calendar date');
});

group('bounds and deduplicates asynchronous online AI candidates', () => {
  const response = JSON.stringify({ choices: [{ message: { content: JSON.stringify({
    candidates: [{ text: '你好' }, { text: '你好' }, { text: '世界' }, { text: 'bad\ntext' }]
  }) } }] });
  const values = OnlineCandidatePolicy.aiCandidates(response, 3);
  check(values !== null && values.length === 2 && values[0] === '你好' && values[1] === '世界',
    'AI response keeps provider order and removes duplicates or controls');
  check(OnlineCandidatePolicy.aiCandidates(JSON.stringify({ error: { code: 'bad' } }), 3) === null,
    'AI error envelope is rejected');
  check(OnlineCandidatePolicy.aiCandidates(response, 0) === null,
    'AI candidate limit stays within shared bounds');
  check(OnlineCandidatePolicy.aiCandidates('x'.repeat(1024 * 1024 + 1), 3) === null,
    'oversized AI response is rejected before parsing');
});

group('keeps translation provider policy bounded and credential-free in signatures', () => {
  const query: TranslationQuery = {
    generation: 12,
    target_language: 'en',
    target_languages: ['en', 'ja'],
    candidates: [{ text: '你好' }, { text: '你好' }],
    custom_translation: null,
    tencent_tmt: null,
    niutrans: { enabled: true, app_id: 'account', apikey: 'secret' },
    english_gloss: true,
    resources: '/data/resources',
    user_data: '/data/state'
  };
  check(TranslationPolicy.provider(query) === 'niutrans', 'NiuTrans has provider precedence');
  check(TranslationPolicy.targets(query).join(',') === 'en,ja', 'targets are deduplicated');
  check(!TranslationPolicy.signature(query).includes('secret'),
    'provider signatures never contain credentials');
  check(TranslationPolicy.cacheKey(query, 'en', {
    text: '你好', key: '你好', source_language: 'zh', target_language: 'en'
  }).includes('niutrans:account'), 'cache scope identifies the provider account');
});

group('merges translation rows without unbounded display growth', () => {
  const entries: TranslationEntry[] = [];
  TranslationPolicy.append(entries, '你好', 'hello');
  TranslationPolicy.append(entries, '你好', 'hello');
  TranslationPolicy.append(entries, '你好', 'greeting');
  TranslationPolicy.append(entries, '世界', '\u0000bad');
  check(entries.length === 1 && entries[0].translation === 'hello / greeting',
    'rows deduplicate and join in provider order');
  TranslationPolicy.append(entries, '你好', 'x'.repeat(5000));
  check(entries[0].translation === 'hello / greeting', 'oversized glosses are ignored');
});

group('bounds native speech language, session and result text', () => {
  check(VoiceRecognitionPolicy.language('  ') === 'zh-CN', 'voice defaults to Chinese');
  check(VoiceRecognitionPolicy.language('x'.repeat(100)).length <= 32,
    'voice language is bounded');
  check(VoiceRecognitionPolicy.sessionId(12) === 'msime-voice-12',
    'voice session ids are deterministic');
  check(VoiceRecognitionPolicy.result(' 水\n水\u0000 ') === '水\n水',
    'voice result removes control bytes and trims');
  check(VoiceRecognitionPolicy.result('x'.repeat(VOICE_MAX_TEXT + 20)).length === VOICE_MAX_TEXT,
    'voice result is bounded');
});

group('bounds handwriting points and rejects empty recognition requests', () => {
  const point = HandwritingStrokePolicy.point(999, -4);
  check(point.x === HANDWRITING_CANVAS_SIZE && point.y === 0,
    'handwriting points stay inside the canvas');
  check(!HandwritingStrokePolicy.canRecognize([]), 'empty ink does not trigger OCR');
  check(HandwritingStrokePolicy.canRecognize([{ points: [point] }]),
    'a bounded stroke is recognisable');
});

group('normalizes OCR candidates without leaking control text or duplicates', () => {
  const candidates = HandwritingStrokePolicy.candidates(' 水\n水\u0000永木未未 ');
  check(candidates.join('') === '水永木未', 'OCR candidates are unique and trimmed');
  check(HandwritingStrokePolicy.candidates('甲乙丙丁戊己庚辛').length === HANDWRITING_MAX_CANDIDATES,
    'OCR candidates are bounded');
});

group('allows reads during composition without restarting the session', () => {
  const decision = DictionaryMaintenancePolicy.decide('list', true);
  check(decision.allowed, 'dictionary reads remain available while composing');
  check(!decision.maintenance, 'dictionary reads do not request maintenance');
});

group('opens an exclusive window for idle mutations', () => {
  for (const operation of ['edit', 'import', 'retry', 'dismiss_failure']) {
    const decision = DictionaryMaintenancePolicy.decide(operation, false);
    check(decision.allowed, `${operation} is allowed while idle`);
    check(decision.maintenance, `${operation} is marked as maintenance`);
  }
});

group('refuses every mutation while composition is active', () => {
  for (const operation of ['edit', 'import', 'retry', 'dismiss_failure']) {
    const decision = DictionaryMaintenancePolicy.decide(operation, true);
    check(!decision.allowed, `${operation} is refused while composing`);
    check(decision.maintenance, `${operation} remains classified as maintenance`);
    check(decision.error === 'dictionary maintenance busy', `${operation} reports the busy state`);
  }
});

group('spacing clamps to its range and falls back on a negative', () => {
  check(KeyboardGeometry.keySpacing(-1) === KeyboardGeometry.DEFAULT_KEY_SPACING_TENTHS,
    'a negative key spacing takes the default rather than the minimum');
  check(KeyboardGeometry.keySpacing(10) === KeyboardGeometry.MIN_KEY_SPACING_TENTHS,
    'below-range key spacing clamps up');
  check(KeyboardGeometry.keySpacing(999) === KeyboardGeometry.MAX_KEY_SPACING_TENTHS,
    'above-range key spacing clamps down');
  check(KeyboardGeometry.rowSpacing(-1) === KeyboardGeometry.DEFAULT_ROW_SPACING_TENTHS,
    'a negative row spacing takes the default');
  check(KeyboardGeometry.rowSpacing(10) === KeyboardGeometry.MIN_ROW_SPACING_TENTHS,
    'below-range row spacing clamps up');
  check(KeyboardGeometry.rowSpacing(999) === KeyboardGeometry.MAX_ROW_SPACING_TENTHS,
    'above-range row spacing clamps down');
});

group('an unset height adjustment is the default, not the minimum', () => {
  check(KeyboardGeometry.heightAdjustment(null) === KeyboardGeometry.DEFAULT_HEIGHT_ADJUSTMENT_VP,
    'null stands for the Java Integer.MIN_VALUE sentinel');
  check(KeyboardGeometry.heightAdjustment(-100) === KeyboardGeometry.MIN_HEIGHT_ADJUSTMENT_VP,
    'a set value below the range still clamps');
  check(KeyboardGeometry.heightAdjustment(100) === KeyboardGeometry.MAX_HEIGHT_ADJUSTMENT_VP,
    'a set value above the range clamps');
});

group('row heights spend the whole adjustment without losing a pixel', () => {
  const base = KeyboardGeometry.STANDARD_ROW_HEIGHT_VP;
  for (const adjustment of [0, 1, 7, -5, 47, 48]) {
    for (const rowCount of [1, 3, 4, 5]) {
      let sum = 0;
      for (let row = 0; row < rowCount; row++) {
        sum += KeyboardGeometry.adjustedRowHeight(base, adjustment, rowCount, row);
      }
      const expected = base * rowCount + KeyboardGeometry.heightAdjustment(adjustment);
      check(sum === expected,
        `rows must sum to ${expected} for adjustment ${adjustment} across ${rowCount} rows, got ${sum}`);
    }
  }
});

group('candidate window height follows the shared layout orientation', () => {
  const horizontal = KeyboardMetrics.candidateHeightVp('horizontal', 9);
  const vertical = KeyboardMetrics.candidateHeightVp('vertical', 9);
  check(horizontal === KeyboardMetrics.candidateHeightVp('horizontal', 1),
    'horizontal candidates stay a single row');
  check(vertical > horizontal, 'vertical candidates get room for their page');
  check(KeyboardMetrics.candidateHeightVp('vertical', 0) ===
    KeyboardMetrics.candidateHeightVp('vertical', 1), 'an empty page keeps one row');
  check(KeyboardMetrics.candidateHeightVp('vertical', 99) === vertical,
    'vertical height is bounded to one candidate page');
  check(KeyboardMetrics.candidateHeightVp('horizontal', 1, false)
      === horizontal - KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP,
    'hidden preedit removes the composition row from panel height');
  check(KeyboardMetrics.candidateHeightVp('vertical', 2, true, 24)
      === KeyboardMetrics.candidateHeightVp('vertical', 2) + 24,
    'candidate decoration reserves its top inset in the panel height');
  check(KeyboardMetrics.candidateHeightVp('vertical', 2, true, 9999)
      === KeyboardMetrics.candidateHeightVp('vertical', 2) + 512,
    'candidate decoration height stays bounded');
});

group('invalid geometry is rejected rather than silently clamped', () => {
  assertThrows(() => KeyboardGeometry.adjustedRowHeight(0, 0, 3, 0), /Invalid keyboard height/, "rejects invalid input");
  assertThrows(() => KeyboardGeometry.adjustedRowHeight(48, 0, 0, 0), /Invalid keyboard height/, "rejects invalid input");
  assertThrows(() => KeyboardGeometry.adjustedRowHeight(48, 0, 3, 3), /Invalid keyboard height/, "rejects invalid input");
  assertThrows(() => KeyboardGeometry.adjustedRowHeight(48, 0, 3, -1), /Invalid keyboard height/, "rejects invalid input");
  checks += 4;
});

group('display strings match the Java formatting', () => {
  check(KeyboardGeometry.display(60) === '6.0', 'tenths render with one decimal');
  check(KeyboardGeometry.display(35) === '3.5', 'tenths render the fraction');
  check(KeyboardGeometry.displayHeight(5) === '+5', 'a positive adjustment carries a sign');
  check(KeyboardGeometry.displayHeight(-5) === '-5', 'a negative adjustment keeps its own sign');
  check(KeyboardGeometry.displayHeight(0) === '0', 'zero carries no sign');
  check(KeyboardGeometry.halfGapPixels(60, 3) === 9, 'half gap rounds to whole pixels');
  check(KeyboardGeometry.halfGapPixels(60, 0) === 0, 'a non-positive density yields no gap');
  check(KeyboardGeometry.halfGapPixels(60, Number.NaN) === 0, 'a non-finite density yields no gap');
});

console.log('CandidateWrapPolicy');

group('a single candidate never wraps, however wide', () => {
  const rows = CandidateWrapPolicy.rows(100, 4, [400]);
  check(rows.length === 1 && rows[0] === 0, 'an overlong first candidate stays on row zero');
});

group('candidates wrap when the row plus spacing would overflow', () => {
  const rows = CandidateWrapPolicy.rows(100, 10, [40, 40, 40]);
  // 40, then 40+10+40 = 90 fits, then 90+10+40 = 140 overflows.
  check(rows[0] === 0 && rows[1] === 0 && rows[2] === 1, `expected [0,0,1], got [${rows.join(',')}]`);
});

group('spacing counts toward the overflow decision', () => {
  const tight = CandidateWrapPolicy.rows(90, 10, [40, 40]);
  const loose = CandidateWrapPolicy.rows(90, 0, [40, 40]);
  check(tight[1] === 0, '40+10+40 = 90 fits exactly in 90');
  check(loose[1] === 0, 'without spacing the pair fits too');
  const overflow = CandidateWrapPolicy.rows(89, 10, [40, 40]);
  check(overflow[1] === 1, 'one pixel narrower and the second candidate wraps');
});

group('an empty candidate list allocates no rows', () => {
  check(CandidateWrapPolicy.rows(100, 4, []).length === 0, 'no candidates means no rows');
});

group('invalid wrap dimensions are rejected', () => {
  assertThrows(() => CandidateWrapPolicy.rows(-1, 4, [10]), /Invalid candidate wrap/, "rejects invalid input");
  assertThrows(() => CandidateWrapPolicy.rows(100, -1, [10]), /Invalid candidate wrap/, "rejects invalid input");
  assertThrows(() => CandidateWrapPolicy.rows(100, 4, [-10]), /Invalid candidate width/, "rejects invalid input");
  checks += 3;
});

console.log('KeyboardScheme');

group('preference ids resolve to their scheme', () => {
  check(KeyboardScheme.fromPreferenceId('quanpin') === KeyboardScheme.QUANPIN, 'quanpin resolves');
  check(KeyboardScheme.fromPreferenceId('nine_key') === KeyboardScheme.QUANPIN_NINE_KEY,
    'nine_key is the quanpin nine-key scheme, not a layout flag');
  check(KeyboardScheme.fromPreferenceId('unknown') === null, 'an unknown id resolves to nothing');
  check(KeyboardScheme.fromPreferenceId(null) === null, 'a null id resolves to nothing');
});

group('engine preferences map back to the right scheme', () => {
  check(KeyboardScheme.fromPreferences('quanpin', null, 'handwriting') === KeyboardScheme.HANDWRITING,
    'handwriting is a layout on top of quanpin');
  check(KeyboardScheme.fromPreferences('quanpin', null, 'nine_key') === KeyboardScheme.QUANPIN_NINE_KEY,
    'quanpin plus nine_key is the nine-key scheme');
  check(KeyboardScheme.fromPreferences('japanese', null, 'nine_key') === KeyboardScheme.JAPANESE_NINE_KEY,
    'japanese plus nine_key is the japanese nine-key scheme');
  check(KeyboardScheme.fromPreferences('japanese', null, 'twenty_six_key') === KeyboardScheme.JAPANESE,
    'japanese on a full layout is the 26-key japanese scheme');
  check(KeyboardScheme.fromPreferences('wubi', null, 'twenty_six_key') === KeyboardScheme.WUBI,
    'wubi resolves by engine scheme');
  check(KeyboardScheme.fromPreferences('shuangpin', 'ziranma', 'twenty_six_key') === KeyboardScheme.ZIRANMA,
    'a shuangpin profile picks its scheme');
  check(KeyboardScheme.fromPreferences('shuangpin', 'nonsense', 'twenty_six_key') === KeyboardScheme.XIAOHE,
    'an unknown shuangpin profile falls back to xiaohe');
  check(KeyboardScheme.fromPreferences('nonsense', null, 'twenty_six_key') === KeyboardScheme.QUANPIN,
    'an unknown scheme falls back to quanpin');
});

group('enabled schemes keep the fixed order and never resolve to nothing', () => {
  const enabled = KeyboardScheme.enabledFromPreferenceIds(['wubi', 'quanpin', 'xiaohe']);
  check(enabled.length === 3, 'three known ids yield three schemes');
  check(enabled[0] === KeyboardScheme.QUANPIN && enabled[1] === KeyboardScheme.XIAOHE
    && enabled[2] === KeyboardScheme.WUBI,
    'declaration order wins over the order the ids arrived in');
  const unknown = KeyboardScheme.enabledFromPreferenceIds(['nope']);
  check(unknown.length === 1 && unknown[0] === KeyboardScheme.QUANPIN,
    'an all-unknown list falls back to quanpin rather than an empty keyboard');
  check(KeyboardScheme.enabledFromPreferenceIds(null).length === KeyboardScheme.SCHEMES.length,
    'a null list means everything is enabled');
});

group('selection prefers the shared choice, then the applied one', () => {
  const enabled: SchemeDefinition[] = [KeyboardScheme.QUANPIN, KeyboardScheme.WUBI];
  check(KeyboardScheme.resolveEnabledSelection(KeyboardScheme.QUANPIN, 'wubi', enabled)
    === KeyboardScheme.WUBI, 'the shared selection is authoritative');
  check(KeyboardScheme.resolveEnabledSelection(KeyboardScheme.WUBI, null, enabled)
    === KeyboardScheme.WUBI, 'without a shared selection the applied scheme is preserved');
  check(KeyboardScheme.resolveEnabledSelection(KeyboardScheme.QUANPIN, 'xiaohe', enabled)
    === KeyboardScheme.QUANPIN, 'a selection outside the enabled set falls back to the first enabled');
  check(KeyboardScheme.resolveEnabledSelection(null, null, []) === KeyboardScheme.QUANPIN,
    'an empty enabled set still yields a usable keyboard');
});

group('mapping keeps the last Chinese scheme across a Japanese switch', () => {
  const japanese: PreferenceMapping = KeyboardScheme.mapping(KeyboardScheme.JAPANESE, 'wubi', 'xiaohe');
  check(japanese.scheme === 'japanese', 'the engine scheme follows the selection');
  check(japanese.lastChineseScheme === 'wubi',
    'switching to Japanese must not forget which Chinese scheme to come back to');
  const wubi: PreferenceMapping = KeyboardScheme.mapping(KeyboardScheme.WUBI, 'quanpin', 'xiaohe');
  check(wubi.lastChineseScheme === 'wubi', 'a Chinese scheme becomes the one to come back to');
  const shuangpin: PreferenceMapping = KeyboardScheme.mapping(KeyboardScheme.ZIRANMA, 'quanpin', 'xiaohe');
  check(shuangpin.shuangpinProfile === 'ziranma', 'the scheme carries its own profile');
  const kept: PreferenceMapping = KeyboardScheme.mapping(KeyboardScheme.QUANPIN, 'quanpin', 'microsoft');
  check(kept.shuangpinProfile === 'microsoft', 'a non-shuangpin scheme preserves the stored profile');
  const normalised: PreferenceMapping = KeyboardScheme.mapping(KeyboardScheme.QUANPIN, 'quanpin', 'nonsense');
  check(normalised.shuangpinProfile === 'xiaohe', 'an unknown stored profile normalises to xiaohe');
  const fallback: PreferenceMapping = KeyboardScheme.mapping(KeyboardScheme.JAPANESE, 'nonsense', 'xiaohe');
  check(fallback.lastChineseScheme === 'quanpin', 'an unknown last Chinese scheme normalises to quanpin');
});

group('a runtime selection that changes nothing produces no update', () => {
  check(KeyboardScheme.mappingForRuntimeSelection(KeyboardScheme.QUANPIN, KeyboardScheme.QUANPIN,
    'quanpin', 'xiaohe') === null, 'selecting the applied scheme is not a change');
  check(KeyboardScheme.mappingForRuntimeSelection(KeyboardScheme.QUANPIN, KeyboardScheme.THOUGHTFUL_REPLY,
    'quanpin', 'xiaohe') === null, 'the reply surface is not an engine scheme');
  check(KeyboardScheme.mappingForRuntimeSelection(KeyboardScheme.QUANPIN, null, 'quanpin', 'xiaohe')
    === null, 'no selection is not a change');
  const change = KeyboardScheme.mappingForRuntimeSelection(KeyboardScheme.QUANPIN, KeyboardScheme.WUBI,
    'quanpin', 'xiaohe');
  check(change !== null && change.scheme === 'wubi', 'a real change produces a mapping');
});

console.log('NineKeyLayout');

group('the quanpin grid is three by three and sends characters, not labels', () => {
  const rows: NineKey[][] = NineKeyLayout.rows();
  check(rows.length === 3, 'three rows');
  for (const row of rows) {
    check(row.length === 3, 'three keys per row');
  }
  check(rows[0][0].input === "'", 'the word-split key sends an apostrophe, not its label');
  check(rows[0][0].label === '分词', 'the word-split key is labelled in Chinese');
  check(rows[0][1].input === '2' && rows[0][1].label === 'ABC', 'ABC sends 2');
  check(rows[2][2].input === '9' && rows[2][2].label === 'WXYZ', 'WXYZ sends 9');
  check(NineKeyLayout.punctuation().length === 4, 'four punctuation marks ride alongside the grid');
});

console.log('JapaneseNineKeyLayout');

group('every key carries exactly five directions', () => {
  const keys: JapaneseKey[] = JapaneseNineKeyLayout.keys();
  check(keys.length === 11, 'eleven kana keys');
  for (const entry of keys) {
    check(entry.kana.length === 5, 'five kana per key');
    check(entry.strokes.length === 5, 'five strokes per key');
  }
  const digits: JapaneseKey[] = JapaneseNineKeyLayout.digitKeys();
  check(digits.length === 11, 'eleven digit-layer keys');
  for (const entry of digits) {
    check(entry.kana.length === 5 && entry.strokes.length === 5,
      'the digit layer keeps the same five-direction shape');
  }
});

group('kana map to the romanization the Engine expects', () => {
  const keys: JapaneseKey[] = JapaneseNineKeyLayout.keys();
  check(keys[0].kana[DIRECTION_CENTRE] === 'あ' && keys[0].strokes[DIRECTION_CENTRE] === 'a',
    'the first key composes a');
  check(keys[2].kana[DIRECTION_LEFT] === 'し' && keys[2].strokes[DIRECTION_LEFT] === 'shi',
    'shi is spelled with three letters, not si');
  check(keys[3].kana[DIRECTION_UP] === 'つ' && keys[3].strokes[DIRECTION_UP] === 'tsu',
    'tsu is spelled with three letters');
  check(keys[9].kana[DIRECTION_UP] === 'ん' && keys[9].strokes[DIRECTION_UP] === "n'",
    'the syllabic n carries its apostrophe so it does not swallow the next vowel');
  check(keys[7].strokes[DIRECTION_LEFT] === '' && keys[7].kana[DIRECTION_LEFT] === '「',
    'a bracket on the ya key commits directly rather than composing');
  check(keys[10].strokes[DIRECTION_CENTRE] === '',
    'the punctuation key composes nothing');
});

group('variant groups pair every label with a stroke', () => {
  const variants: VariantGroup[] = JapaneseNineKeyLayout.variants();
  check(variants.length === 3, 'small kana, voiced and semi-voiced');
  for (const entry of variants) {
    check(entry.kana.length === entry.strokes.length && entry.kana.length > 0,
      `${entry.title} pairs every label with a stroke`);
  }
  check(variants[1].kana.length === 21, 'the voiced group carries twenty-one kana');
  check(JapaneseNineKeyLayout.digitBrackets().length === 8, 'eight bracket pairs');
});

group('a flick shorter than the threshold stays on the centre', () => {
  check(JapaneseNineKeyLayout.direction(0, 0, 10) === DIRECTION_CENTRE, 'no movement is the centre');
  check(JapaneseNineKeyLayout.direction(9, 9, 10) === DIRECTION_CENTRE,
    'movement below the threshold in both axes is the centre');
  check(JapaneseNineKeyLayout.direction(10, 0, 10) === DIRECTION_RIGHT,
    'reaching the threshold leaves the centre');
});

group('the larger axis decides, so a diagonal never falls between directions', () => {
  check(JapaneseNineKeyLayout.direction(-30, 0, 10) === DIRECTION_LEFT, 'left');
  check(JapaneseNineKeyLayout.direction(30, 0, 10) === DIRECTION_RIGHT, 'right');
  check(JapaneseNineKeyLayout.direction(0, -30, 10) === DIRECTION_UP, 'up');
  check(JapaneseNineKeyLayout.direction(0, 30, 10) === DIRECTION_DOWN, 'down');
  check(JapaneseNineKeyLayout.direction(-30, 20, 10) === DIRECTION_LEFT,
    'a wider horizontal movement is horizontal');
  check(JapaneseNineKeyLayout.direction(20, -30, 10) === DIRECTION_UP,
    'a taller vertical movement is vertical');
  check(JapaneseNineKeyLayout.direction(30, 30, 10) === DIRECTION_DOWN,
    'an exact diagonal resolves vertically rather than being ambiguous');
});

group('a negative flick threshold is rejected', () => {
  assertThrows(() => JapaneseNineKeyLayout.direction(0, 0, -1), /Flick threshold/,
    'rejects invalid input');
  checks++;
});

group('side keys say what the next press will do', () => {
  check(JapaneseNineKeyActions.spaceTitle(true) === '変換', 'space converts while composing');
  check(JapaneseNineKeyActions.spaceTitle(false) === '空白', 'space inserts a blank otherwise');
  check(JapaneseNineKeyActions.returnTitle(true) === '確定', 'return confirms while composing');
  check(JapaneseNineKeyActions.returnTitle(false) === '改行', 'return breaks the line otherwise');
});

console.log('Input policies');

console.log('ReplyKeyboardPolicy');

group('reply source and request bounds are explicit', () => {
  check(ReplyKeyboardPolicy.source('  对方的话  ') === '对方的话', 'trims source text');
  check(ReplyKeyboardPolicy.source('   ') === null, 'rejects empty source');
  check(ReplyKeyboardPolicy.source('含\n换行') === null, 'rejects control characters');
  const request = ReplyKeyboardPolicy.request('对方的话', '高情商');
  check(request !== null && request.prompt.includes('高情商'), 'builds style prompt');
});

group('reply results are safe, unique and bounded', () => {
  const values: string[] = ReplyKeyboardPolicy.results(['一', '一', '二', '三', '四']);
  check(values.length === 3 && values[2] === '三', 'deduplicates and limits results');
  check(ReplyKeyboardPolicy.results(['好\u0000']).length === 0, 'rejects control characters');
  check(ReplyKeyboardPolicy.STYLES.length === 9, 'keeps the shared nine reply styles');
});

group('community reply templates accept only bounded reply entries', () => {
  const values = CommunityReplyLibraryPolicy.parse(JSON.stringify([
    { id: 'one', kind: 'reply', name: '礼貌', content: { prompt: '保持礼貌。' } },
    { id: 'dictionary', kind: 'dictionary', name: '词库', content: { prompt: '忽略' } }
  ]));
  check(values.length === 1 && values[0].id === 'one', 'filters non-reply resources');
  check(CommunityReplyLibraryPolicy.parse('[{"id":"one","kind":"reply","name":"x","content":{"prompt":"y"}},{"id":"one","kind":"reply","name":"z","content":{"prompt":"q"}}]').length === 0, 'rejects duplicate ids');
  check(CommunityReplyLibraryPolicy.parse('[{"id":"one","kind":"reply","name":"x","content":{"prompt":"bad\u0000"}}]').length === 0, 'rejects control text');
  check(CommunityReplyLibraryPolicy.parse('not-json').length === 0, 'rejects malformed documents');
});

group('reply results stay bound to the editor context', () => {
  check(ReplyContextPolicy.matches(3, 3, 7, 7), 'accepts the same editor generations');
  check(!ReplyContextPolicy.matches(3, 4, 7, 7), 'rejects a changed editor');
  check(!ReplyContextPolicy.matches(3, 3, 7, 8), 'rejects a changed cursor context');
  check(!ReplyContextPolicy.matches(-1, -1, 0, 0), 'rejects invalid generations');
});

group('helpcode needs a composition, a pinyin scheme and no local mode', () => {
  check(ChineseHelpcodePolicy.entersHelpcode(false, true, 'ni', 0, 'none'),
    'shift during a quanpin composition enters helpcode');
  check(!ChineseHelpcodePolicy.entersHelpcode(false, false, 'ni', 0, 'none'),
    'without shift there is no helpcode');
  check(!ChineseHelpcodePolicy.entersHelpcode(true, true, 'ni', 0, 'none'),
    'dedicated English never enters helpcode');
  check(!ChineseHelpcodePolicy.entersHelpcode(false, true, '', 0, 'none'),
    'an empty composition has nothing to annotate');
  check(!ChineseHelpcodePolicy.entersHelpcode(false, true, 'ni', 2, 'none'),
    'wubi has no helpcode');
  check(!ChineseHelpcodePolicy.entersHelpcode(false, true, 'ni', 0, 'unicode'),
    'a local mode owns the keystroke instead');
  check(ChineseHelpcodePolicy.eligible(false, 'ni', 1, 'none'), 'shuangpin is eligible too');
});

group('the wubi hint shows only the untyped suffix', () => {
  check(WubiCodeHintPolicy.hint('ggll', 'gg', true, 2, 'none', false) === 'll',
    'the remaining code is the suffix');
  check(WubiCodeHintPolicy.hint('gg', 'gg', true, 2, 'none', false) === '',
    'a fully typed code has no remainder');
  check(WubiCodeHintPolicy.hint('ggll', 'xx', true, 2, 'none', false) === '',
    'a code that is not an extension is not annotated');
  check(WubiCodeHintPolicy.hint('ggll', 'gg', false, 2, 'none', false) === '',
    'the hint can be switched off');
  check(WubiCodeHintPolicy.hint('ggll', 'gg', true, 0, 'none', false) === '',
    'only the wubi scheme is annotated');
  check(WubiCodeHintPolicy.hint('ggll', 'gg', true, 2, 'none', true) === '',
    'a pinyin fallback candidate is not annotated: its code is not the one being typed');
  check(WubiCodeHintPolicy.hint('ggll', 'gg', true, 2, 'unicode', false) === '',
    'a local mode candidate is not annotated');
  check(WubiCodeHintPolicy.hint(null, 'gg', true, 2, 'none', false) === '', 'a null code is safe');
  check(WubiCodeHintPolicy.hint('g'.repeat(65), 'g', true, 2, 'none', false) === '',
    'an implausibly long code is refused rather than rendered');
});

group('the letter face and the engine input are decided separately', () => {
  check(LetterKeyFacePolicy.face('a', true, false, false) === 'A',
    'Chinese mode prints uppercase faces while still sending lowercase');
  check(LetterKeyFacePolicy.face('a', true, true, false) === 'a',
    'a local mode drops back to the lowercase face');
  check(LetterKeyFacePolicy.face('a', false, false, false) === 'a',
    'English unshifted is lowercase');
  check(LetterKeyFacePolicy.face('a', false, false, true) === 'A', 'English shifted is uppercase');
  check(LetterKeyFacePolicy.face('', true, false, false) === '', 'an empty face stays empty');
  check(LetterKeyFacePolicy.accessibilityLabel('a', false, false, true) === '大写 A',
    'a shifted English key announces uppercase');
  check(LetterKeyFacePolicy.accessibilityLabel('a', true, false, false) === '字母 A',
    'a Chinese key announces the letter');
  check(LetterKeyFacePolicy.accessibilityLabel(null, true, false, false) === '字母',
    'a missing letter still announces something');
});

group('word capitalization starts after anything that is not a letter or digit', () => {
  const words = CapitalizationMode.WORDS;
  check(EnglishCapitalizationPolicy.shouldShift(words, '') === true, 'an empty field starts a word');
  check(EnglishCapitalizationPolicy.shouldShift(words, 'hello ') === true, 'a space starts a word');
  check(EnglishCapitalizationPolicy.shouldShift(words, 'hello') === false, 'mid-word stays lowercase');
  check(EnglishCapitalizationPolicy.shouldShift(words, 'don\'') === false,
    'an apostrophe keeps the word going rather than starting a new one');
  check(EnglishCapitalizationPolicy.shouldShift(words, 'don\u2019') === false,
    'a typographic apostrophe behaves the same');
  check(EnglishCapitalizationPolicy.shouldShift(words, 'x1') === false, 'a digit is part of the word');
  check(EnglishCapitalizationPolicy.shouldShift(words, null) === false, 'no context means no shift');
});

group('sentence capitalization looks past closers and whitespace', () => {
  const sentences = CapitalizationMode.SENTENCES;
  check(EnglishCapitalizationPolicy.shouldShift(sentences, '') === true, 'an empty field starts a sentence');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, 'Hi. ') === true, 'a full stop ends a sentence');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, 'Hi.') === true, 'even without the space');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, 'Hi') === false, 'mid-sentence stays lowercase');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, 'Hi." ') === true,
    'a closing quote after the stop is skipped');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, 'Hi) ') === false,
    'a closer with no terminator behind it does not start a sentence');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, 'Hi\n') === true, 'a newline starts a sentence');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, '你好。') === true,
    'the full-width stop ends a sentence too');
  check(EnglishCapitalizationPolicy.shouldShift(sentences, '   ') === true,
    'whitespace all the way back is the start of the field');
});

group('the other two capitalization modes are unconditional', () => {
  check(EnglishCapitalizationPolicy.shouldShift(CapitalizationMode.NONE, '') === false,
    'none never shifts');
  check(EnglishCapitalizationPolicy.shouldShift(CapitalizationMode.ALL_CHARACTERS, 'abc') === true,
    'all characters always shifts');
});

group('a one-shot shift is spent by the next letter', () => {
  const state = new EnglishLetterCaseState();
  check(state.mode() === LetterCaseMode.LOWERCASE, 'starts lowercase');
  state.toggle(1000);
  check(state.mode() === LetterCaseMode.SHIFTED, 'one tap shifts');
  check(state.consumeLetter() === true, 'the letter spends it');
  check(state.mode() === LetterCaseMode.LOWERCASE, 'and it falls back to lowercase');
  check(state.consumeLetter() === false, 'a second letter has nothing to spend');
});

group('a double tap inside the interval locks, a slow one does not', () => {
  const quick = new EnglishLetterCaseState();
  quick.toggle(1000);
  quick.toggle(1000 + EnglishLetterCaseState.CAPS_LOCK_INTERVAL_MILLIS);
  check(quick.mode() === LetterCaseMode.CAPS_LOCK, 'exactly at the interval still locks');
  check(quick.keyText() === '⇪', 'the key face shows the lock');
  check(quick.consumeLetter() === false, 'caps lock is not spent by a letter');

  const slow = new EnglishLetterCaseState();
  slow.toggle(1000);
  slow.toggle(1000 + EnglishLetterCaseState.CAPS_LOCK_INTERVAL_MILLIS + 1);
  check(slow.mode() === LetterCaseMode.LOWERCASE, 'one millisecond later it just toggles off');
  check(slow.keyText() === '⇧', 'the key face shows the plain shift');
});

group('automatic shift never overrides caps lock', () => {
  const locked = new EnglishLetterCaseState();
  locked.toggle(1000);
  locked.toggle(1100);
  check(locked.applyAutomatic(false) === false, 'the policy cannot unlock caps lock');
  check(locked.mode() === LetterCaseMode.CAPS_LOCK, 'and the mode is unchanged');

  const plain = new EnglishLetterCaseState();
  check(plain.applyAutomatic(true) === true, 'applying a shift reports the change');
  check(plain.isAutomatic() === true, 'and marks it automatic');
  check(plain.accessibilityValue() === '自动开启', 'which the announcement distinguishes');
  check(plain.applyAutomatic(true) === false, 'reapplying the same shift is not a change');
  plain.toggle(2000);
  check(plain.isAutomatic() === false, 'a manual tap clears the automatic flag');
});

group('a negative uptime is rejected rather than treated as a fast tap', () => {
  const state = new EnglishLetterCaseState();
  assertThrows(() => state.toggle(-1), /Uptime/, 'rejects invalid input');
  checks++;
});

console.log('Output and editor policies');

group('maps shared candidate skins to native Harmony palettes', () => {
  check(CandidateSkinPolicy.rowDetailColor(false, '#111111', '#ffffff') === '#111111',
    'unselected candidate details use the normal text colour');
  check(CandidateSkinPolicy.rowDetailColor(true, '#111111', '#ffffff') === '#ffffff',
    'selected candidate details follow the selected text colour');
  check(CandidateSkinPolicy.harmonySkin('fluent') === 'porcelain', 'Fluent uses the clean palette');
  check(CandidateSkinPolicy.harmonySkin('wechat') === 'forest', 'WeChat uses the green palette');
  check(CandidateSkinPolicy.harmonySkin('graphite') === 'blueprint', 'Graphite uses the blue-gray palette');
  check(CandidateSkinPolicy.harmonySkin('willow_green') === 'forest', 'Willow green uses the green palette');
  check(CandidateSkinPolicy.harmonySkin('unknown') === 'forest', 'unknown ids fall back safely');
  check(CandidateSkinPolicy.showSelectedBar('fluent'), 'Fluent shows its selected bar');
  check(!CandidateSkinPolicy.showSelectedBar('wechat'), 'WeChat skin omits its selected bar');
  check(!CandidateSkinPolicy.showSelectedBar('graphite'), 'Graphite skin omits its selected bar');
  check(CandidateSkinPolicy.harmonySkin('sample', 'wechat') === 'forest',
    'external skins inherit the WeChat Harmony palette');
  check(CandidateSkinPolicy.harmonySkin('sample', 'graphite') === 'blueprint',
    'external skins inherit the Graphite Harmony palette');
});

group('resolves external candidate skin tokens without trusting missing fields', () => {
  const sample: CandidateSkinPackage = {
    id: 'sample', base: 'wechat', layouts: ['vertical'], themes: ['dark'], minWidthDip: 360,
    decorationTopDip: 24, decorationWidthDip: 180, toolbarStylesheet: 'toolbar.css',
    preview: 'images/preview.svg',
    candidate: {
      dark: {
        accent: '#123456', selected: '#234567', hover: '#345678', surface: '#456789',
        border: '#56789A', text: '#6789AB', number: '#789ABC', showSelectedBar: false
      },
      light: {
        accent: null, selected: null, hover: null, surface: null, border: null,
        text: null, number: null, showSelectedBar: null
      }
    }
  };
  const packages: CandidateSkinPackage[] = [sample];
  const palette = CandidateSkinCatalogPolicy.palette(packages, 'sample', true);
  check(palette !== null && palette.accent === '#123456', 'external accent is selected by theme');
  check(CandidateSkinCatalogPolicy.base(packages, 'sample') === 'wechat',
    'external base skin is retained');
  check(CandidateSkinCatalogPolicy.supports(packages, 'sample', 'vertical', 'dark'),
    'manifest compatibility accepts a declared layout and theme');
  check(!CandidateSkinCatalogPolicy.supports(packages, 'sample', 'horizontal', 'dark'),
    'manifest compatibility rejects an undeclared layout');
  check(CandidateSkinCatalogPolicy.minWidthVp(packages, 'sample') === 360,
    'external minimum width is exposed to the native panel');
  check(CandidateSkinCatalogPolicy.showSelectedBar(packages, 'sample', true) === false,
    'external selected-bar override is retained');
  check(CandidateSkinCatalogPolicy.toolbarStylesheet(packages, 'sample') === 'toolbar.css',
    'external toolbar stylesheet is retained');
  const decoration = CandidateSkinCatalogPolicy.decoration(packages, 'sample');
  check(decoration !== null && decoration.topVp === 24 && decoration.widthVp === 180,
    'external decoration geometry is retained');
  check(CandidateSkinCatalogPolicy.decoration(packages, 'missing') === null,
    'unknown packages do not invent decoration geometry');
  check(CandidateSkinCatalogPolicy.imageDataUrl('image/png', [0, 1, 2])
    === 'data:image/png;base64,AAEC', 'image bytes become an image-only data URL');
  check(CandidateSkinCatalogPolicy.imageDataUrl('text/css', [0, 1, 2]) === null,
    'non-image resources cannot become decoration URLs');
  check(CandidateSkinCatalogPolicy.imageAspectRatio('image/png', [
    0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0x02, 0, 0, 0, 0x01
  ]) === 2, 'PNG dimensions preserve the decoration aspect ratio');
  check(CandidateSkinCatalogPolicy.palette(packages, 'missing', true) === null,
    'unknown package does not invent a palette');
  check(CandidateSkinCatalogPolicy.color('#123456') === '#123456',
    'hex colors remain available to ArkUI');
  check(CandidateSkinCatalogPolicy.color('rgba(1, 2, 3, 0.5)') === 'rgba(1, 2, 3, 0.5)',
    'rgba colors remain available to ArkUI');
  check(CandidateSkinCatalogPolicy.color('red;} .poison {') === null,
    'declaration-like color tokens are rejected');
  check(CandidateSkinCatalogPolicy.color('rgb(256, 0, 0)') === null,
    'out-of-range rgb channels are rejected');
  check(CandidateSkinPolicy.showSelectedBar('sample', false) === false,
    'explicit external selected-bar value wins over the base default');
});

group('maps safe external toolbar CSS to ArkUI values', () => {
  const base = KeyboardSkin.from('forest', true);
  const toolbar = ToolbarSkinPolicy.fromCss(base, `
    .status-bar { background: #101820; border: 1px solid #223344; border-radius: 6px; }
    .drag-handle { background-color: #556677; }
    .divider { background: rgba(80, 90, 100, .5); }
    .icon { color: rgba(200, 210, 220, .9); font-family: "Noto Sans SC", sans-serif; }
    .icon:hover { background-color: #334455; }
    .english-candidate-label { font-family: "JetBrains Mono", monospace; }
  `);
  check(toolbar.backgroundColor === '#101820', 'toolbar background is mapped');
  check(toolbar.borderColor === '#223344', 'toolbar border is mapped');
  check(toolbar.dragHandleColor === '#556677', 'toolbar drag handle color is mapped');
  check(toolbar.dividerColor === 'rgba(80, 90, 100, .5)', 'toolbar divider color is mapped');
  check(toolbar.buttonColor === 'rgba(200, 210, 220, .9)', 'toolbar icon color is mapped');
  check(toolbar.buttonHoverColor === '#334455', 'toolbar hover color is mapped');
  check(toolbar.cornerRadiusVp === 6, 'toolbar radius is bounded and mapped');
  check(toolbar.fontFamily === '"Noto Sans SC", sans-serif', 'toolbar font family is mapped');
  check(toolbar.englishFontFamily === '"JetBrains Mono", monospace',
    'English toolbar font family is mapped');
  const unsafe = ToolbarSkinPolicy.fromCss(base,
    '.status-bar { background: url(https://example.invalid/x); } .icon { color: red; }');
  check(unsafe.backgroundColor === base.keyBackground, 'resource URLs are ignored');
  check(unsafe.buttonColor === base.accent, 'unsupported colour syntax is ignored');
});

group('applies Windows toolbar scale and font-size bounds to Harmony geometry', () => {
  check(FloatingToolbarLayout.scale(0.75) === 0.75, 'minimum toolbar scale is retained');
  check(FloatingToolbarLayout.scale(1.12) === 1, 'scale snaps to the nearest Windows step');
  check(FloatingToolbarLayout.scale(1.4) === 1.5, 'upper scale snaps to the nearest step');
  check(FloatingToolbarLayout.scale(2) === 1, 'out-of-range scale uses the Windows default');
  check(FloatingToolbarLayout.scale(Number.NaN) === 1, 'invalid scale falls back to one');
  check(FloatingToolbarLayout.fontSize(16) === 16, 'minimum toolbar font size is retained');
  check(FloatingToolbarLayout.fontSize(40) === 24, 'out-of-range toolbar font size uses the Windows default');
  check(FloatingToolbarLayout.fontSize(Number.NaN) === 24, 'invalid font size uses Windows default');
  check(FloatingToolbarLayout.buttonWidthVp(1.5) === 63, 'button width follows toolbar scale');
  check(FloatingToolbarLayout.heightVp(0.75) === 33, 'toolbar height follows toolbar scale');
  check(FloatingToolbarLayout.widthVp(2) * 1.5 === 172.5,
    'host width arithmetic remains consistent with scaled content');
});

group('shows Japanese input mode in the Harmony toolbar', () => {
  const japaneseState = {
    english: false, temporaryEnglish: false, japanese: true, capsLock: false,
    chinesePunctuation: true, fullWidth: false, traditional: false
  };
  const englishState = {
    english: true, temporaryEnglish: false, japanese: true, capsLock: false,
    chinesePunctuation: true, fullWidth: false, traditional: false
  };
  check(FloatingToolbarLayout.face(ToolbarButton.INPUT_MODE, japaneseState) === '日',
    'Japanese mode has its own toolbar face');
  check(FloatingToolbarLayout.face(ToolbarButton.INPUT_MODE, englishState) === '英',
    'dedicated English mode takes precedence over the Japanese scheme');
  check(FloatingToolbarLayout.face(ToolbarButton.INPUT_MODE, FloatingToolbarLayout.idleState()) === '中',
    'the default Chinese mode remains unchanged');
  check(FloatingToolbarLayout.face(ToolbarButton.INPUT_MODE, {
    english: false, temporaryEnglish: false, japanese: true, capsLock: true, chinesePunctuation: true,
    fullWidth: false, traditional: false
  }) === 'A', 'Caps Lock takes precedence over the language mode face');
  check(FloatingToolbarLayout.face(ToolbarButton.INPUT_MODE, {
    english: false, temporaryEnglish: true, japanese: false, capsLock: false,
    chinesePunctuation: true, fullWidth: false, traditional: false
  }) === 'En', 'temporary English mode uses the Windows En toolbar face');
  check(FloatingToolbarLayout.face(ToolbarButton.INPUT_MODE, {
    english: true, temporaryEnglish: true, japanese: true, capsLock: false,
    chinesePunctuation: true, fullWidth: false, traditional: false
  }) === 'En', 'temporary English takes precedence over dedicated language faces');
});

group('keeps a dragged Harmony toolbar inside the display', () => {
  check(FloatingToolbarDragPolicy.position([100, 120], [20, -10], 2, 1000, 800, 200, 50)
    .join(',') === '140,100', 'pan offsets convert from vp to px');
  check(FloatingToolbarDragPolicy.position([100, 120], [1000, 1000], 2, 1000, 800, 200, 50)
    .join(',') === '800,750', 'dragging beyond the display clamps to the lower-right edge');
  check(FloatingToolbarDragPolicy.position([100, 120], [-1000, -1000], 2, 1000, 800, 200, 50)
    .join(',') === '0,0', 'dragging beyond the upper-left edge clamps to zero');
  check(FloatingToolbarDragPolicy.position([17, 19], [1, 1], 0, 1000, 800, 200, 50)
    .join(',') === '17,19', 'invalid density preserves the last known position');
});

group('sizes desktop candidate windows from bounded display estimates', () => {
  const short = CandidateWidthPolicy.widthVp([], 'ni', 18, 15);
  const wide = CandidateWidthPolicy.widthVp([
    { text: '这是一个足够长的候选词条用于展示', badge: '', hint: '', annotation: '' }
  ], '', 18, 15);
  const annotated = CandidateWidthPolicy.widthVp([
    { text: '候选', badge: '云', hint: 'houxuan', annotation: 'candidate'.repeat(10) }
  ], '', 18, 15);
  const plain = CandidateWidthPolicy.widthVp([
    { text: '候选', badge: '', hint: '', annotation: '' }
  ], '', 18, 15);
  check(short === CandidateWidthPolicy.MIN_WIDTH_VP, 'short candidates use the compact minimum');
  check(wide > short, 'wide CJK candidates receive more card width');
  check(annotated > plain, 'badges and annotations contribute to width');
  check(CandidateWidthPolicy.widthVp([
    { text: 'x'.repeat(200), badge: '', hint: '', annotation: '' }
  ], '', 18, 15) === CandidateWidthPolicy.MAX_WIDTH_VP,
  'provider text cannot grow the panel beyond the desktop bound');
  check(CandidateWidthPolicy.textWidthVp('😀', 18) === 18, 'emoji surrogate pairs count as one wide glyph');
  assertThrows(() => CandidateWidthPolicy.textWidthVp('x', 0), /font size/,
    'rejects invalid font sizes');
});

group('preserves the candidate skin selected-bar default while honoring an explicit disable', () => {
  check(selectedBarVisible(null), 'absent preference keeps the skin default');
  check(selectedBarVisible(true), 'explicit enable keeps the bar');
  check(!selectedBarVisible(false), 'explicit disable hides the bar');
});

group('keeps Engine candidate selection independent from row order', () => {
  const entries = [
    { text: 'first', hint: '', annotation: '', highlighted: false },
    { text: 'second', hint: '', annotation: '', highlighted: true }
  ];
  check(!entries[0].highlighted && entries[1].highlighted,
    'a highlighted candidate may be below the first row');
});

group('keeps candidate source badges bounded to known Engine sources', () => {
  check(CandidatePresentationPolicy.badge(2) === ' ☁️', 'cloud candidates get a cloud badge');
  check(CandidatePresentationPolicy.badge(3) === ' 🤖', 'AI candidates get a robot badge');
  check(CandidatePresentationPolicy.badge(0) === '', 'local candidates stay unbadged');
});

group('offers all fixed candidate slots and checks the active one', () => {
  const actions = CandidateManagementAction.actionsForFixedPosition(3);
  check(actions.length === 8, 'pin, five positions, clear and remove are exposed');
  check(actions[3].id === 'FIX_3' && actions[3].checked === true,
    'the current fixed slot is marked');
  check(actions[1].position === 1 && actions[5].position === 5,
    'positions keep their one-based slot numbers');
});

group('limits candidate dictionary mutations to supported sources', () => {
  check(CandidateManagementAction.candidateActionsAvailable('quanpin', 0),
    'local candidates are actionable');
  check(CandidateManagementAction.candidateActionsAvailable('quanpin', 1),
    'user dictionary candidates are actionable');
  check(!CandidateManagementAction.candidateActionsAvailable('quanpin', 2),
    'cloud candidates are read-only');
  check(!CandidateManagementAction.candidateActionsAvailable('japanese', 0),
    'Japanese candidates are read-only');
  const disabled = CandidateManagementAction.actionsForFixedPosition(2, false);
  check(disabled.every((action: ManagementAction) => action.available === false),
    'unsupported candidates expose disabled actions');
});

group('omits deletion for single-code-point candidates', () => {
  check(!CandidateManagementAction.hasMultipleCodePoints('你'),
    'one CJK code point cannot be deleted from the dictionary menu');
  check(!CandidateManagementAction.hasMultipleCodePoints('😀'),
    'one supplementary code point is counted as one');
  check(CandidateManagementAction.hasMultipleCodePoints('你好'),
    'multi-code-point words keep the deletion action');
  check(CandidateManagementAction.actionsForFixedPosition(0, true, false).length === 7,
    'the delete row is omitted rather than merely disabled');
});

group('keeps the candidate panel anchor when follow-cursor is disabled', () => {
  const anchor: CandidateAnchor = [100, 200, 20];
  const current: CandidateAnchor = [400, 500, 20];
  check(CandidateAnchorPolicy.position(false, anchor, current)[0] === 100,
    'disabled follow uses the composition anchor');
  check(CandidateAnchorPolicy.position(true, anchor, current)[0] === 400,
    'enabled follow uses the latest caret');
  check(CandidateAnchorPolicy.position(false, undefined, current)[1] === 500,
    'missing anchor falls back to the current caret');
});

group('maps desktop candidate wheel movement to page commands', () => {
  check(CandidateWheelPolicy.previousPage(1), 'positive wheel movement pages up');
  check(!CandidateWheelPolicy.nextPage(1), 'positive movement does not page down');
  check(CandidateWheelPolicy.nextPage(-1), 'negative wheel movement pages down');
  check(!CandidateWheelPolicy.previousPage(-1), 'negative movement does not page up');
  check(!CandidateWheelPolicy.previousPage(0) && !CandidateWheelPolicy.nextPage(0),
    'zero movement is ignored');
});

group('releases the candidate number row when the shared preference asks', () => {
  const key: HardwareKey = {
    keyCode: 0, unicodeChar: '2'.charCodeAt(0), ctrlKey: false,
    altKey: false, logoKey: false, shiftKey: false
  };
  check(HardwareKeyRouter.route(key, true, true).action === HardwareKeyAction.SELECT,
    'the default hardware route selects a candidate');
  check(HardwareKeyRouter.route(key, true, true, true).action === HardwareKeyAction.RELEASE,
    'the preference releases the digit to the focused editor');
});

group('maps hardware navigation according to the shared preferences', () => {
  const navigation = {
    minusEqual: true, commaPeriod: true, brackets: false,
    tab: true, pageUpDown: true, mouseWheel: false, arrows: true
  };
  const key = (keyCode: number, shiftKey: boolean = false): HardwareKey => ({
    keyCode, unicodeChar: 0, ctrlKey: false, altKey: false, logoKey: false, shiftKey
  });
  check(HardwareKeyRouter.route(key(2068), true, true, false, navigation).action ===
    HardwareKeyAction.PREVIOUS_PAGE, 'PageUp goes to the previous page');
  check(HardwareKeyRouter.route(key(2069), true, true, false, navigation).action ===
    HardwareKeyAction.NEXT_PAGE, 'PageDown goes to the next page');
  check(HardwareKeyRouter.route(key(2012), true, true, false, navigation).action ===
    HardwareKeyAction.PREVIOUS_CANDIDATE, 'Up goes to the previous candidate');
  check(HardwareKeyRouter.route(key(2013), true, true, false, navigation).action ===
    HardwareKeyAction.NEXT_CANDIDATE, 'Down goes to the next candidate');
  check(HardwareKeyRouter.route(key(2049, true), true, true, false, navigation).action ===
    HardwareKeyAction.PREVIOUS_PAGE, 'Shift+Tab goes to the previous page');
  check(HardwareKeyRouter.route(key(2049), true, true, false, navigation).action ===
    HardwareKeyAction.NEXT_PAGE, 'Tab goes to the next page');
  check(HardwareKeyRouter.route(key(2057), true, true, false, navigation).action ===
    HardwareKeyAction.PREVIOUS_PAGE, 'minus goes to the previous page');
  check(HardwareKeyRouter.route(key(2059), true, true, false, navigation).action ===
    HardwareKeyAction.IGNORED, 'disabled brackets are consumed without text input');
  check(HardwareKeyRouter.route({ ...key(2012), ctrlKey: true }, true, true, false, navigation).action ===
    HardwareKeyAction.RELEASE, 'modifier shortcuts remain with the editor');
});

group('maps Windows word-to-character bindings to highlighted candidate edges', () => {
  const key = (keyCode: number, shiftKey: boolean = false): HardwareKey => ({
    keyCode, unicodeChar: 0, ctrlKey: false, altKey: false, logoKey: false, shiftKey
  });
  check(HardwareKeyRouter.route(key(2059), true, true, false, undefined, false, false,
    'brackets', true).action === HardwareKeyAction.WORD_CHARACTER_FIRST,
  'left bracket selects the first Han character');
  check(HardwareKeyRouter.route(key(2060), true, true, false, undefined, false, false,
    'brackets', true).action === HardwareKeyAction.WORD_CHARACTER_LAST,
  'right bracket selects the last Han character');
  check(HardwareKeyRouter.route(key(2057), true, true, false, undefined, false, false,
    'minus_equal', true).action === HardwareKeyAction.WORD_CHARACTER_FIRST,
  'minus selects the first Han character');
  check(HardwareKeyRouter.route(key(2058), true, true, false, undefined, false, false,
    'minus_equal', true).action === HardwareKeyAction.WORD_CHARACTER_LAST,
  'equals selects the last Han character');
  check(HardwareKeyRouter.route(key(2059), true, true, false, undefined, false, false,
    'brackets', false).action !== HardwareKeyAction.WORD_CHARACTER_FIRST,
  'without a highlighted candidate the bracket remains navigation/editor input');
  check(HardwareKeyRouter.route(key(2059, true), true, true, false, undefined, false, false,
    'brackets', true).action !== HardwareKeyAction.WORD_CHARACTER_FIRST,
  'shifted brackets stay with the editor');
});

group('extracts Han characters for word-to-character fallback', () => {
  check(CandidateTextPolicy.extractHanCharacter('abc中b文', CandidateTextEdge.FIRST) === '中',
    'first Han character is selected');
  check(CandidateTextPolicy.extractHanCharacter('abc中b文', CandidateTextEdge.LAST) === '文',
    'last Han character is selected');
  check(CandidateTextPolicy.extractHanCharacter('𠀀a', CandidateTextEdge.FIRST) === '𠀀',
    'supplementary Han character is preserved');
  check(CandidateTextPolicy.extractHanCharacter('abc', CandidateTextEdge.FIRST) === null,
    'non-Han candidate has no fallback');
  check(CandidateTextPolicy.extractHanCharacter('', CandidateTextEdge.LAST) === null,
    'empty candidate has no fallback');
});

group('maps hardware composition editing commands like Windows', () => {
  const navigation = {
    minusEqual: true, commaPeriod: true, brackets: false,
    tab: true, pageUpDown: true, mouseWheel: false, arrows: true
  };
  const key = (keyCode: number, ctrlKey: boolean = false, shiftKey: boolean = false): HardwareKey => ({
    keyCode, unicodeChar: 0, ctrlKey, altKey: false, logoKey: false, shiftKey
  });
  check(HardwareKeyRouter.route(key(2014), true, true).action === HardwareKeyAction.MOVE_LEFT,
    'left moves within the composition');
  check(HardwareKeyRouter.route(key(2015), true, true).action === HardwareKeyAction.MOVE_RIGHT,
    'right moves within the composition');
  check(HardwareKeyRouter.route(key(2081), true, true).action === HardwareKeyAction.MOVE_HOME,
    'Home moves to the start');
  check(HardwareKeyRouter.route(key(2082), true, true).action === HardwareKeyAction.MOVE_END,
    'End moves to the end');
  check(HardwareKeyRouter.route(key(2071), true, true).action === HardwareKeyAction.DELETE_FORWARD,
    'Delete removes the next unit');
  check(HardwareKeyRouter.route(key(2055, true), true, true).action ===
    HardwareKeyAction.BACKSPACE_SEGMENT, 'Ctrl+Backspace removes one segment');
  check(HardwareKeyRouter.route(key(2014, true), true, true).action ===
    HardwareKeyAction.MOVE_LEFT_SEGMENT, 'Ctrl+Left moves one segment left');
  check(HardwareKeyRouter.route(key(2015, true), true, true).action ===
    HardwareKeyAction.MOVE_RIGHT_SEGMENT, 'Ctrl+Right moves one segment right');
  check(HardwareKeyRouter.route(key(2055, true, true), true, true).action ===
    HardwareKeyAction.RELEASE, 'Shift+Ctrl remains an editor shortcut');
  check(HardwareKeyRouter.route(key(2054, true), true, true, false, navigation, true).action ===
    HardwareKeyAction.COMMIT_TRANSLATION, 'Ctrl+Enter commits a highlighted candidate translation');
  check(HardwareKeyRouter.route(key(2054, true), true, true, false, navigation, false).action ===
    HardwareKeyAction.RELEASE, 'Ctrl+Enter remains with the editor without a translation');
  const japaneseMinus: HardwareKey = {
    keyCode: 2057, unicodeChar: '-'.charCodeAt(0), ctrlKey: false,
    altKey: false, logoKey: false, shiftKey: false
  };
  check(HardwareKeyRouter.route(japaneseMinus, false, true, false, navigation, false, true).action ===
    HardwareKeyAction.COMPOSE, 'Japanese minus starts a long-vowel composition');
  check(HardwareKeyRouter.route(japaneseMinus, false, true, false, navigation, false, true).character ===
    '-'.charCodeAt(0), 'Japanese minus reaches the Engine as a hyphen');
  check(HardwareKeyRouter.route(japaneseMinus, true, true, false, navigation, false, true).action ===
    HardwareKeyAction.COMPOSE, 'Japanese minus remains a long-vowel composition key');
  check(HardwareKeyRouter.route(key(2058), true, true, false, navigation, false, true).action ===
    HardwareKeyAction.RELEASE, 'Japanese equals stays ordinary editor punctuation');
  check(HardwareKeyRouter.route(key(2057, false, true), true, true, false, navigation, false, true).action ===
    HardwareKeyAction.RELEASE, 'Shift+minus stays ordinary editor punctuation in Japanese');
});

group('routes Chinese hardware punctuation without stealing editor navigation', () => {
  const key = (unicodeChar: number, keyCode: number = 0, modifiers: Partial<HardwareKey> = {}): HardwareKey => ({
    keyCode,
    unicodeChar,
    ctrlKey: false,
    altKey: false,
    logoKey: false,
    shiftKey: false,
    ...modifiers
  });
  check(HardwareKeyRouter.route(key(0x2c), false, true).action === HardwareKeyAction.PUNCTUATION,
    'Chinese hardware comma uses the shared punctuation route');
  check(HardwareKeyRouter.route(key(0x3f), false, true).character === 0x3f,
    'hardware punctuation preserves the ASCII key');
  check(HardwareKeyRouter.route(key(0x2c), false, false).action === HardwareKeyAction.RELEASE,
    'English punctuation remains application-owned');
  check(HardwareKeyRouter.route(key(0x2c), false, true, false, undefined, false, true).action ===
    HardwareKeyAction.RELEASE, 'Japanese punctuation remains application-owned');
  check(HardwareKeyRouter.route(key(0x2c, 2043), true, true).action === HardwareKeyAction.PREVIOUS_PAGE,
    'comma keeps candidate paging while composing');
  check(HardwareKeyRouter.route(key(0x2c, 2043, { ctrlKey: true }), false, true).action ===
    HardwareKeyAction.RELEASE, 'modified punctuation is left to the application');
});

group('splits candidate translation senses for Ctrl+Enter', () => {
  check(TranslationSensePolicy.split('你好；您好；喂').join('|') === '你好|您好|喂',
    'fullwidth semicolons become separate translation choices');
  check(TranslationSensePolicy.split('hello; greeting ; hello').join('|') === 'hello|greeting',
    'ASCII senses are trimmed and deduplicated');
  check(TranslationSensePolicy.split('； ; ').length === 0,
    'empty translation senses are ignored');
});

group('fullwidth conversion maps space to the ideographic form', () => {
  check(FullWidthInputPolicy.output('a', true) === 'ａ', 'a printable ASCII letter shifts by 0xfee0');
  check(FullWidthInputPolicy.output(' ', true) === '\u3000',
    'space becomes the ideographic space, not the fullwidth space');
  check(FullWidthInputPolicy.output('~', true) === '～', 'the top of the printable range converts');
  check(FullWidthInputPolicy.output('\n', true) === '\n', 'a control character is left alone');
  check(FullWidthInputPolicy.output('中', true) === '中', 'non-ASCII is left alone');
  check(FullWidthInputPolicy.output('a', false) === 'a', 'disabled means unchanged');
  check(FullWidthInputPolicy.output('', true) === '', 'empty stays empty');
  check(FullWidthInputPolicy.output('😀', true) === '😀',
    'an astral character survives rather than being split');
});

group('clipboard entries are bounded in characters and in UTF-8 bytes', () => {
  check(ClipboardHistoryPolicy.acceptable('hello') === true, 'ordinary text is kept');
  check(ClipboardHistoryPolicy.acceptable('   ') === false, 'whitespace only is not worth keeping');
  check(ClipboardHistoryPolicy.acceptable('') === false, 'empty is not worth keeping');
  check(ClipboardHistoryPolicy.acceptable(null) === false, 'null is safe');
  check(ClipboardHistoryPolicy.acceptable('a'.repeat(ClipboardHistoryPolicy.MAX_CHARS)) === true,
    'exactly at the character bound is accepted');
  check(ClipboardHistoryPolicy.acceptable('a'.repeat(ClipboardHistoryPolicy.MAX_CHARS + 1)) === false,
    'one character over is refused');
  // The byte bound is measured in UTF-8 and counts multi-byte characters accordingly.
  const wide = '中'.repeat(1000);
  check(wide.length === 1000, 'a thousand UTF-16 units');
  check(ClipboardHistoryPolicy.acceptable(wide) === true, 'three thousand bytes is well inside');
  // Worth recording: with MAX_CHARS at 10000 UTF-16 units, the worst case is 5000 astral characters
  // at four bytes each, or 20000 bytes. The byte bound of 40000 is therefore unreachable through the
  // character bound and is purely defensive. The Java original has the same property.
  const astral = '😀'.repeat(ClipboardHistoryPolicy.MAX_CHARS / 2);
  check(astral.length === ClipboardHistoryPolicy.MAX_CHARS, 'exactly at the character bound');
  check(ClipboardHistoryPolicy.acceptable(astral) === true,
    'the heaviest text the character bound allows is still inside the byte bound');
});

group('diagnostics are trimmed, bounded and elided', () => {
  check(InputDiagnosticPolicy.normalize('  hi  ') === 'hi', 'surrounding whitespace goes');
  check(InputDiagnosticPolicy.normalize('   ') === '', 'whitespace only becomes empty');
  check(InputDiagnosticPolicy.normalize(null) === '', 'null becomes empty');
  const long = 'x'.repeat(InputDiagnosticPolicy.MAX_LENGTH + 100);
  const bounded = InputDiagnosticPolicy.normalize(long);
  check(bounded.length === InputDiagnosticPolicy.MAX_LENGTH,
    'an overlong diagnostic is cut to the bound including the ellipsis');
  check(bounded.endsWith('…'), 'and says it was cut');
  check(InputDiagnosticPolicy.visible('hi') === true, 'a real diagnostic shows');
  check(InputDiagnosticPolicy.visible('   ') === false, 'an empty one does not');
});

group('traditional output never loses text when conversion fails', () => {
  const upper = (text: string): string => text.toUpperCase();
  check(ChineseOutputPolicy.output('ab', true, true, upper) === 'AB', 'a working converter is used');
  check(ChineseOutputPolicy.output('ab', false, true, upper) === 'ab', 'simplified output is untouched');
  check(ChineseOutputPolicy.output('ab', true, false, upper) === 'ab',
    'a context the policy does not apply to is untouched');
  check(ChineseOutputPolicy.output('ab', true, true, () => null) === 'ab',
    'a converter returning nothing falls back to the original');
  check(ChineseOutputPolicy.output('ab', true, true, () => { throw new Error('boom'); }) === 'ab',
    'a converter that throws must not lose the text');
  check(ChineseOutputPolicy.applies(false, 0, 'none') === true, 'quanpin converts');
  check(ChineseOutputPolicy.applies(true, 0, 'none') === false, 'dedicated English does not');
  check(ChineseOutputPolicy.applies(false, 3, 'none') === false, 'Japanese has nothing to convert');
  check(ChineseOutputPolicy.applies(false, 0, 'temporary_japanese') === false,
    'temporary Japanese has nothing to convert either');
});

group('local modes are addressable by trigger and by preference key', () => {
  check(LocalInputMode.MODES.length === 8, 'eight local modes');
  const unicode = LocalInputMode.fromTrigger('U');
  check(unicode !== null && unicode.preferenceKey === 'unicode', 'U enters Unicode code points');
  const emoji = LocalInputMode.fromPreferenceKey('emoji');
  check(emoji !== null && emoji.trigger === 'E', 'emoji is entered with E');
  check(LocalInputMode.fromTrigger('Z') === null, 'an unassigned letter enters nothing');
  const triggers = new Set(LocalInputMode.MODES.map((entry) => entry.trigger));
  check(triggers.size === LocalInputMode.MODES.length, 'no two modes share a trigger');
});

group('quick punctuation prints one glyph and sends another', () => {
  const chinese: PunctuationEntry[] = QuickPunctuationPolicy.entries(false, 0, 'none');
  check(chinese[0].face === '，' && chinese[0].input === ',',
    'the Chinese comma is drawn but an ASCII comma is sent');
  check(chinese[4].face === '、' && chinese[4].input === '\\',
    'the enumeration comma is reached through backslash');
  const japanese: PunctuationEntry[] = QuickPunctuationPolicy.entries(false, 3, 'none');
  check(japanese[0].face === '、', 'Japanese leads with the enumeration comma');
  check(japanese[4].face === '「' && japanese[4].input === '[', 'Japanese brackets come from [');
  const ascii: PunctuationEntry[] = QuickPunctuationPolicy.entries(true, 0, 'none');
  check(ascii[0].face === ',' && ascii[0].input === ',', 'dedicated English sends what it draws');
  check(QuickPunctuationPolicy.entries(false, 0, 'emoji')[0].face === ',',
    'a local mode falls back to ASCII');
});

group('bounds Harmony smart punctuation editor context', () => {
  check(SmartPunctuationContext.precedingCodePoint(null) === 0, 'missing context is unavailable');
  check(SmartPunctuationContext.precedingCodePoint('fixture7') === '7'.charCodeAt(0),
    'ASCII digit context is preserved');
  check(SmartPunctuationContext.precedingCodePoint('fixture中') === 0x4e2d,
    'CJK context is preserved for the shared policy');
  check(SmartPunctuationContext.precedingCodePoint('fixture🌲') === 0x1f332,
    'supplementary context is reduced to one scalar');
  check(SmartPunctuationContext.precedingCodePoint('fixture\ud800') === 0,
    'unpaired surrogate context is rejected');
});

group('replaces a repeated smart ASCII mark only in the same short-lived editor state', () => {
  const first: SmartPunctuationRepeatSnapshot | null = SmartPunctuationRepeatPolicy.snapshot(
    0x2c, ',', 1000, 4);
  check(first !== null, 'ASCII comma arms the repeat state');
  check(SmartPunctuationRepeatPolicy.shouldReplace(first, 0x2c, 0x2c, 2999, 4,
    true, true, false, 0), 'same mark and editor within two seconds replaces');
  check(!SmartPunctuationRepeatPolicy.shouldReplace(first, 0x2c, 0x2c, 3001, 4,
    true, true, false, 0), 'the repeat window expires');
  check(!SmartPunctuationRepeatPolicy.shouldReplace(first, 0x2e, 0x2c, 1500, 4,
    true, true, false, 0), 'a different mark does not replace');
  check(!SmartPunctuationRepeatPolicy.shouldReplace(first, 0x2c, 0x2c, 1500, 5,
    true, true, false, 0), 'a different editor does not replace');
  check(!SmartPunctuationRepeatPolicy.shouldReplace(first, 0x2c, 0x2c, 1500, 4,
    true, true, true, 0), 'composition blocks replacement');
  check(!SmartPunctuationRepeatPolicy.shouldReplace(first, 0x2c, 0x2c, 1500, 4,
    true, true, false, 1), 'candidates block replacement');
  check(!SmartPunctuationRepeatPolicy.shouldReplace(first, 0x2c, 0x2c, 1500, 4,
    false, true, false, 0), 'smart punctuation can disable replacement');
  check(SmartPunctuationRepeatPolicy.chineseMark(0x2e) === '。', 'period maps to ideographic full stop');
  check(SmartPunctuationRepeatPolicy.chineseMark(0x3a) === '：', 'colon maps to full-width colon');
  check(SmartPunctuationRepeatPolicy.snapshot(0x2c, '，', 1000, 4) !== null,
    'a full-width ASCII mark remains replaceable when full-width input is enabled');
});

group('completes Engine opening punctuation only when paired mode is enabled', () => {
  check(PairedPunctuationPolicy.completion('“', true)?.closing === '”',
    'double quote opens a Chinese pair');
  check(PairedPunctuationPolicy.completion('拟（', true)?.closing === '）',
    'a composition commit can end in an opening parenthesis');
  check(PairedPunctuationPolicy.completion('《', true)?.opening === 0x3c,
    'book title marks retain the balance input');
  check(PairedPunctuationPolicy.completion('”', true) === null,
    'a closing quote is not completed again');
  check(PairedPunctuationPolicy.completion('“', false) === null,
    'disabled paired punctuation leaves the editor to the Engine');
  check(PairedPunctuationPolicy.completion('', true) === null,
    'an empty commit cannot open a pair');
});

group('return performs an editor action only when nothing else claimed it', () => {
  const send = 4;
  check(ReturnKeyAction.performsEditorAction(send, false) === true, 'send is an editor action');
  check(ReturnKeyAction.performsEditorAction(0, false) === false, 'unspecified is not');
  check(ReturnKeyAction.performsEditorAction(1, false) === false, 'none is not');
  check(ReturnKeyAction.performsEditorAction(send, true) === false, 'a disabled action is not performed');
  check(ReturnKeyAction.shouldPerformEditorAction(send, false, true) === false,
    'a handled composition consumes Return first');
  check(ReturnKeyAction.shouldPerformEditorAction(send, false, false) === true,
    'otherwise the editor action runs');
  check(ReturnKeyAction.title(send, false) === '发送', 'the key says what it will do');
  check(ReturnKeyAction.title(send, true) === '换行', 'a disabled action falls back to newline');
  check(ReturnKeyAction.title(0, false) === '换行', 'an unspecified action is a newline');
});

group('the Japanese variant key needs kana already composing', () => {
  check(JapaneseVariantPolicy.enabled(true, false, true) === true, 'composing kana enables it');
  check(JapaneseVariantPolicy.enabled(true, false, false) === false, 'nothing composed, nothing to vary');
  check(JapaneseVariantPolicy.enabled(true, true, true) === false, 'the symbol layer has no variants');
  check(JapaneseVariantPolicy.enabled(false, false, true) === false, 'other schemes have no variant key');
  check(JapaneseVariantPolicy.accessibilityLabel(false).includes('请先输入假名'),
    'the disabled announcement says what to do first');
});

console.log('Candidate and cursor policies');

group('space drag accumulates whole steps and carries the remainder', () => {
  const drag = new SpaceCursorMovement();
  const document = {};
  check(drag.isActive() === false, 'inactive before it begins');
  drag.begin(100, document);
  check(drag.isActive() === true, 'active after begin');
  check(drag.advance(110, document, 20) === 0, 'half a step moves nothing yet');
  check(drag.advance(120, document, 20) === 1, 'the carried remainder completes the step');
  check(drag.advance(100, document, 20) === -1, 'dragging back moves back');
});

group('a drag against a different document is abandoned, not redirected', () => {
  const drag = new SpaceCursorMovement();
  const first = {};
  const second = {};
  drag.begin(100, first);
  check(drag.advance(200, second, 20) === 0, 'another editor gets no movement');
  check(drag.isActive() === false, 'and the drag is cancelled rather than transferred');
});

group('implausible input cancels the drag rather than clamping it', () => {
  const drag = new SpaceCursorMovement();
  const document = {};
  drag.begin(0, document);
  check(drag.advance(99999, document, 20) === 0, 'a jump beyond the bound yields nothing');
  check(drag.isActive() === false, 'and cancels: the gesture was already lost');

  const nan = new SpaceCursorMovement();
  nan.begin(Number.NaN, document);
  check(nan.isActive() === false, 'beginning at a non-finite position never starts');

  const zeroStep = new SpaceCursorMovement();
  zeroStep.begin(0, document);
  check(zeroStep.advance(100, document, 0) === 0, 'a step size below one pixel is refused');
  check(zeroStep.isActive() === false, 'and cancels');

  const noDocument = new SpaceCursorMovement();
  noDocument.begin(0, null);
  check(noDocument.isActive() === false, 'beginning without a document never starts');
});

group('menu ids follow declaration order and round-trip', () => {
  check(CandidateManagementAction.ACTIONS.length === 4, 'four management actions');
  for (const entry of CandidateManagementAction.ACTIONS) {
    const resolved: ManagementAction = CandidateManagementAction.fromMenuItemId(entry.menuItemId);
    check(resolved === entry, `${entry.id} round-trips through its menu id`);
  }
  check(CandidateManagementAction.REMOVE.confirmationRequired === true,
    'deleting an entry asks first');
  check(CandidateManagementAction.PROMOTE.confirmationRequired === false,
    'promoting one does not');
  assertThrows(() => CandidateManagementAction.fromMenuItemId(999), /Unknown candidate/,
    'rejects invalid input');
  assertThrows(() => CandidateManagementAction.fromMenuItemId(1004), /Unknown candidate/,
    'rejects invalid input');
  checks += 2;
});

group('only the fix-first action names a position', () => {
  check(CandidateManagementAction.fixedPosition(CandidateManagementAction.FIX_FIRST) === 1,
    'fixing means position one');
  assertThrows(() => CandidateManagementAction.fixedPosition(CandidateManagementAction.PROMOTE),
    /does not fix a position/, 'rejects invalid input');
  check(CandidateManagementAction.validatePosition(1) === 1, 'position one is valid');
  check(CandidateManagementAction.validatePosition(5) === 5, 'position five is valid');
  assertThrows(() => CandidateManagementAction.validatePosition(0), /between 1 and 5/,
    'rejects invalid input');
  assertThrows(() => CandidateManagementAction.validatePosition(6), /between 1 and 5/,
    'rejects invalid input');
  checks += 3;
});

group('a stale gloss is dropped rather than painted onto the current candidates', () => {
  const token: GlossToken = CandidateGlossPolicy.token(1, 5, 2);
  check(CandidateGlossPolicy.isCurrent(token, 1, 5, 2) === true, 'the matching state accepts it');
  check(CandidateGlossPolicy.isCurrent(token, 2, 5, 2) === false, 'another session rejects it');
  check(CandidateGlossPolicy.isCurrent(token, 1, 6, 2) === false, 'a newer generation rejects it');
  check(CandidateGlossPolicy.isCurrent(token, 1, 5, 3) === false, 'a newer epoch rejects it');
  assertThrows(() => CandidateGlossPolicy.token(0, 0, 0), /Invalid candidate gloss token/,
    'rejects invalid input');
  checks++;
});

group('an engine annotation outranks a gloss in the shared hint slot', () => {
  check(CandidateGlossPolicy.annotation('ggll', 'green', true) === 'ggll',
    'the wubi code wins the slot');
  check(CandidateGlossPolicy.annotation('', 'green', true) === 'green',
    'with no annotation the gloss shows');
  check(CandidateGlossPolicy.annotation(null, 'green', false) === '',
    'a disabled gloss shows nothing');
  check(CandidateGlossPolicy.annotation(null, null, true) === '', 'no gloss shows nothing');
  const long = 'x'.repeat(5000);
  check(CandidateGlossPolicy.annotation(null, long, true) === '',
    'an implausibly long gloss is refused rather than rendered');
  check(CandidateGlossPolicy.accessibilitySuffix('ggll', 'green', true) === '，提示：ggll',
    'the announcement calls an annotation a hint');
  check(CandidateGlossPolicy.accessibilitySuffix(null, 'green', true) === '，英文释义：green',
    'and calls a gloss a definition');
  check(CandidateGlossPolicy.accessibilitySuffix(null, null, true) === '',
    'with neither there is nothing to announce');
});

console.log('ShuangpinKeyHintPolicy');

group('hints appear only for a shuangpin composition', () => {
  check(ShuangpinKeyHintPolicy.visible(false, 1, 'none') === true, 'shuangpin shows hints');
  check(ShuangpinKeyHintPolicy.visible(false, 0, 'none') === false, 'quanpin has no key units');
  check(ShuangpinKeyHintPolicy.visible(true, 1, 'none') === false, 'dedicated English shows none');
  check(ShuangpinKeyHintPolicy.visible(false, 1, 'emoji') === false, 'a local mode owns the keys');
  check(ShuangpinKeyHintPolicy.hint('xiaohe', 'q', true, 1, 'none') === '',
    'an invisible context yields no hint');
  check(ShuangpinKeyHintPolicy.hint('xiaohe', null, false, 1, 'none') === '', 'a null key is safe');
  check(ShuangpinKeyHintPolicy.hint('nonsense', 'q', false, 1, 'none') === '',
    'an unknown profile yields no hint rather than a wrong one');
});

group('the key hint pairs the initial with the finals', () => {
  check(ShuangpinKeyHintPolicy.hint('xiaohe', 'U', false, 1, 'none') === 'sh / u',
    'u carries both an initial and a final, separated');
  check(ShuangpinKeyHintPolicy.hint('xiaohe', 'u', false, 1, 'none') === 'sh / u',
    'the lookup is case-insensitive');
  check(ShuangpinKeyHintPolicy.hint('xiaohe', 'W', false, 1, 'none') === 'ei',
    'a key with only a final shows just the final');
});

group('v is printed as u-umlaut, which is what the user is looking for', () => {
  const v = ShuangpinKeyHintPolicy.hint('xiaohe', 'V', false, 1, 'none');
  check(v.includes('ü'), `xiaohe v should print u-umlaut, got "${v}"`);
  check(!v.includes('v='), 'the raw table spelling never reaches the label');
  const t = ShuangpinKeyHintPolicy.hint('xiaohe', 'T', false, 1, 'none');
  check(t.includes('ü'), `xiaohe t carries ue and ve, so it shows u-umlaut too, got "${t}"`);
});

group('finals sharing a key are listed in a stable order', () => {
  const s = ShuangpinKeyHintPolicy.hint('xiaohe', 'S', false, 1, 'none');
  check(s === 'iong ong', `two finals sort rather than following table order, got "${s}"`);
  const l = ShuangpinKeyHintPolicy.hint('xiaohe', 'L', false, 1, 'none');
  check(l === 'iang uang', `and so do these, got "${l}"`);
});

group('each profile has its own table', () => {
  const xiaohe = ShuangpinKeyHintPolicy.hint('xiaohe', 'W', false, 1, 'none');
  const ziranma = ShuangpinKeyHintPolicy.hint('ziranma', 'W', false, 1, 'none');
  check(xiaohe !== ziranma, 'the same key means different things in different profiles');
  check(ziranma === 'ia ua', `ziranma w carries ia and ua, got "${ziranma}"`);
  check(ShuangpinKeyHintPolicy.hint('microsoft', ';', false, 1, 'none') === 'ing',
    'microsoft is the profile that uses the semicolon key');
  check(ShuangpinKeyHintPolicy.hint('xiaohe', ';', false, 1, 'none') === '',
    'xiaohe leaves the semicolon unassigned');
  check(ShuangpinKeyHintPolicy.hint('shoudao', 'E', false, 1, 'none') === 'sh / e',
    'shoudao puts sh on e rather than on u');
});

console.log('EditorPolicy');

function traits(text: boolean, password: boolean, uri: boolean, email: boolean,
                noSuggestions: boolean): EditorTraits {
  return { text: text, password: password, uri: uri, email: email, noSuggestions: noSuggestions };
}

const PLAIN: EditorTraits = traits(true, false, false, false, false);
const PASSWORD: EditorTraits = traits(true, true, false, false, false);
const URI: EditorTraits = traits(true, false, true, false, false);
const EMAIL: EditorTraits = traits(true, false, false, true, false);
const NO_SUGGESTIONS: EditorTraits = traits(true, false, false, false, true);
const NUMERIC: EditorTraits = traits(false, false, false, false, false);

group('a password field never sees a composition buffer', () => {
  check(EditorPolicy.useEngine(PLAIN) === true, 'prose composes through the Engine');
  check(EditorPolicy.useEngine(PASSWORD) === false, 'a password never does');
  check(EditorPolicy.useEngine(NO_SUGGESTIONS) === false,
    'a field that asked for no suggestions has said it does not want one');
  check(EditorPolicy.useEngine(NUMERIC) === false, 'a number field has nothing to compose');
  check(EditorPolicy.useEngine(URI) === true,
    'a URI still composes: it prefers Latin but is not forbidden the Engine');
});

group('Latin is preferred where Chinese would only be in the way', () => {
  check(EditorPolicy.prefersLatin(URI) === true, 'addresses are Latin');
  check(EditorPolicy.prefersLatin(EMAIL) === true, 'so are email addresses');
  check(EditorPolicy.prefersLatin(PASSWORD) === true, 'so are passwords');
  check(EditorPolicy.prefersLatin(NO_SUGGESTIONS) === true, 'so are one-time codes');
  check(EditorPolicy.prefersLatin(PLAIN) === false, 'prose is not');
});

group('an address is never capitalized, whatever the platform says', () => {
  check(EditorPolicy.capitalizationMode(URI, CapitalizationMode.SENTENCES)
    === CapitalizationMode.NONE, 'the first character of a URI is part of an address');
  check(EditorPolicy.capitalizationMode(EMAIL, CapitalizationMode.WORDS)
    === CapitalizationMode.NONE, 'and so is the first character of an email address');
  check(EditorPolicy.capitalizationMode(NUMERIC, CapitalizationMode.SENTENCES)
    === CapitalizationMode.NONE, 'a non-text field has nothing to capitalize');
  check(EditorPolicy.capitalizationMode(PLAIN, CapitalizationMode.SENTENCES)
    === CapitalizationMode.SENTENCES, 'otherwise the platform value is honoured');
  check(EditorPolicy.capitalizationMode(PLAIN, CapitalizationMode.NONE)
    === CapitalizationMode.NONE, 'including when it asks for none');
  check(EditorPolicy.capitalizationMode(PASSWORD, CapitalizationMode.WORDS)
    === CapitalizationMode.WORDS,
    'a password is not an address: the platform value stands, as in the Java');
});

console.log('KeyboardSkin');

group('the theme resolves keyboard first, then global, then the system', () => {
  check(KeyboardSkin.resolveDark('dark', 'light', false) === true, 'the keyboard theme wins');
  check(KeyboardSkin.resolveDark('light', 'dark', true) === false, 'in both directions');
  check(KeyboardSkin.resolveDark('system', 'dark', false) === true, 'then the global theme');
  check(KeyboardSkin.resolveDark('system', 'light', true) === false, 'in both directions');
  check(KeyboardSkin.resolveDark('system', 'system', true) === true, 'then the system');
  check(KeyboardSkin.resolveDark('system', 'system', false) === false, 'in both directions');
});

group('an unknown skin id falls back to forest rather than failing', () => {
  check(KeyboardSkin.from('nonsense', false).id === 'forest', 'an unknown id is forest');
  check(KeyboardSkin.from('', false).id === 'forest', 'so is an empty one');
  check(KeyboardSkin.from(null, false).id === 'forest', 'so is null');
  check(KeyboardSkin.builtIns(false).length === 8, 'eight built-in skins');
  check(KeyboardSkin.choices(false, null).length === 9, 'plus the custom one');
  check(KeyboardSkin.choices(false, null)[8].id === 'custom', 'custom comes last');
});

group('colours are formatted the way the Java formats them', () => {
  const forest = KeyboardSkin.from('forest', false);
  check(/^#[0-9A-F]{6}$/.test(forest.background), `six upper-case hex digits, got ${forest.background}`);
  check(forest.keyBackground === '#FFFFFF', 'the light forest key is pure white');
  check(forest.keyForeground === '#000000', 'and its label is black');
  const dark = KeyboardSkin.from('forest', true);
  check(dark.keyForeground === '#FFFFFF', 'the dark label is white');
  check(dark.background !== forest.background, 'dark mode changes the background');
  // rgb(.094, .36, .28) rounds to 24, 92, 71.
  check(forest.accent === '#185C47', `forest accent rounds to #185C47, got ${forest.accent}`);
});

group('the border colour carries an alpha byte in front', () => {
  const forest = KeyboardSkin.from('forest', false);
  check(/^#[0-9A-F]{8}$/.test(forest.borderColor),
    `an eight-digit ARGB value, got ${forest.borderColor}`);
  check(forest.borderColor.substring(3) === forest.accent.substring(1),
    'the RGB part is the accent');
  // 0.28 * 255 rounds to 71, which is 0x47.
  check(forest.borderColor.substring(1, 3) === '47', 'the alpha is 0.28 of full');
  const midnight = KeyboardSkin.from('midnight', true);
  check(midnight.borderColor.substring(1, 3) === 'A6',
    'midnight carries a neon edge at 0.65, which is 0xA6');
});

group('each built-in skin is distinct and self-consistent', () => {
  const skins = KeyboardSkin.builtIns(false);
  const ids = new Set(skins.map((skin) => skin.id));
  check(ids.size === skins.length, 'no duplicate ids');
  const keys = new Set(skins.map((skin) => skin.key()));
  check(keys.size === skins.length, 'no two skins share a cache key');
  for (const skin of skins) {
    check(skin.title.length > 0 && skin.description.length > 0, `${skin.id} is described`);
    check(skin.keyShape === 'rounded' && skin.keyMaterial === 'flat',
      `${skin.id} uses the built-in key treatment`);
    check(skin.photo === null, `${skin.id} carries no photo`);
  }
  check(KeyboardSkin.from('typewriter', false).monospaced === true, 'typewriter is monospaced');
  check(KeyboardSkin.from('blueprint', false).monospaced === true, 'so is blueprint');
  check(KeyboardSkin.from('forest', false).monospaced === false, 'forest is not');
});

group('the cache key separates light from dark and carries the design', () => {
  check(KeyboardSkin.from('forest', false).key() !== KeyboardSkin.from('forest', true).key(),
    'light and dark are different skins to the cache');
  const custom = KeyboardSkin.from('custom', false, CustomKeyboardSkin.defaults());
  check(custom.key().startsWith('custom:false:'), 'the custom key carries the design behind it');
});

console.log('CustomKeyboardSkin');

function document(fields: CustomSkinDocument): CustomSkinDocument {
  return fields;
}

group('out-of-range values are clamped, not rejected outright', () => {
  const wild = CustomKeyboardSkin.from(document({
    cornerRadius: 500, borderWidth: -3, shadow: 9, keyOpacity: 0, patternOpacity: 5,
    pattern: 99, photoShade: 9, photoPosition: -1
  }));
  check(wild.cornerRadius() === 20, 'corner radius clamps to 20');
  check(wild.borderWidth() === 0, 'border width clamps to 0');
  check(wild.shadow() === 0.4, 'shadow clamps to 0.4');
  check(wild.keyOpacity() === 0.25, 'key opacity clamps to a quarter, not to invisible');
  check(wild.patternOpacity() === 0.5, 'pattern opacity clamps to a half');
  check(wild.pattern() === 3, 'pattern clamps to the last one');
  check(wild.photoShade() === 0.8, 'photo shade clamps');
  check(wild.photoPosition() === 0, 'photo position clamps');
});

group('a non-finite value falls back rather than clamping', () => {
  const broken = CustomKeyboardSkin.from(document({ cornerRadius: Number.NaN, shadow: Number.NaN }));
  check(broken.cornerRadius() === 8, 'NaN takes the default corner radius');
  check(broken.shadow() === 0, 'and the default shadow');
});

group('an unknown enum value takes the first choice', () => {
  const odd = CustomKeyboardSkin.from(document({ keyShape: 'triangle', keyMaterial: 'velvet' }));
  check(odd.keyShape() === 'rounded', 'an unknown shape is rounded');
  check(odd.keyMaterial() === 'flat', 'an unknown material is flat');
  const valid = CustomKeyboardSkin.from(document({ keyShape: 'capsule', keyMaterial: 'glass' }));
  check(valid.keyShape() === 'capsule', 'a known shape is kept');
  check(valid.keyMaterial() === 'glass', 'a known material is kept');
});

group('the action label flips to black on a light action key', () => {
  const light = CustomKeyboardSkin.from(document({ actionBackground: 0xffffff }));
  check(light.actionForeground() === '#000000', 'white needs a black label');
  const dark = CustomKeyboardSkin.from(document({ actionBackground: 0x000000 }));
  check(dark.actionForeground() === '#FFFFFF', 'black needs a white label');
  const mid = CustomKeyboardSkin.from(document({ actionBackground: 0x185c47 }));
  check(mid.actionForeground() === '#FFFFFF', 'the default green is dark enough for white');
});

group('colours print as six upper-case hex digits with the high byte dropped', () => {
  const skin = CustomKeyboardSkin.from(document({ background: 0xff123456 }));
  check(skin.background() === '#123456', 'anything above the low three bytes is masked off');
  const small = CustomKeyboardSkin.from(document({ background: 0x0000ff }));
  check(small.background() === '#0000FF', 'a small value is padded to six digits');
});

group('the border colour falls back to the accent', () => {
  const inherited = CustomKeyboardSkin.from(document({ accent: 0x123456 }));
  check(inherited.borderColor() === '#123456', 'with no custom border, the accent is used');
  const explicit = CustomKeyboardSkin.from(document({ accent: 0x123456, customBorderColor: 0xabcdef }));
  check(explicit.borderColor() === '#ABCDEF', 'an explicit border colour wins');
});

group('only real image bytes are accepted as a photo', () => {
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0, 0]);
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 0]);
  const gif = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0]);
  const webp = new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
  check(supportedPhoto(jpeg) && supportedPhoto(png) && supportedPhoto(gif) && supportedPhoto(webp),
    'JPEG, PNG, GIF and WebP are recognised by magic number');
  check(!supportedPhoto(new Uint8Array([1, 2, 3, 4])), 'arbitrary bytes are not an image');
  check(!supportedPhoto(new Uint8Array([])), 'nothing is not an image');
  check(!supportedPhoto(new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 1, 2, 3, 4])),
    'a RIFF container that is not WebP is refused');
  const withPhoto = CustomKeyboardSkin.from(document({}), png);
  check(withPhoto.photo() !== null, 'a valid photo is kept');
  const bogus = CustomKeyboardSkin.from(document({}), new Uint8Array([1, 2, 3]));
  check(bogus.photo() === null, 'an invalid one is dropped');
  const huge = new Uint8Array(512001);
  huge.set(png.subarray(0, 8));
  check(CustomKeyboardSkin.from(document({}), huge).photo() === null,
    'an oversized photo is dropped even when it is a real PNG');
});

group('the design key changes whenever the drawing would', () => {
  const base = CustomKeyboardSkin.defaults().key();
  check(CustomKeyboardSkin.from(document({ accent: 0x123456 })).key() !== base,
    'a colour change changes the key');
  check(CustomKeyboardSkin.from(document({ cornerRadius: 12 })).key() !== base,
    'so does a geometry change');
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 42]);
  check(CustomKeyboardSkin.from(document({}), png).key() !== base, 'so does adding a photo');
  check(CustomKeyboardSkin.from(document({})).key() === base, 'an empty document is the default');
});

group('the panel is as tall as what the view stacks inside it', () => {
  const expected = KeyboardMetrics.COMPOSITION_ROW_HEIGHT_VP
    + KeyboardMetrics.CANDIDATE_ROW_HEIGHT_VP
    + KeyboardMetrics.ROW_HEIGHT_VP * KeyboardMetrics.KEY_ROWS
    + KeyboardMetrics.ROW_SPACING_VP * KeyboardMetrics.KEY_ROWS
    + KeyboardMetrics.ROOT_VERTICAL_PADDING_VP * 2;
  check(KeyboardMetrics.totalHeightVp() === expected,
    'the total counts the strip, every key row, the gaps between them and both paddings');
  // One gap per key row: one between the strip and the first row, then one before each of the rest.
  check(KeyboardMetrics.ROW_SPACING_VP * KeyboardMetrics.KEY_ROWS
    === KeyboardMetrics.ROW_SPACING_VP * 4, 'four rows are separated by four gaps, not three');
  check(KeyboardMetrics.totalHeightVp() > 0, 'a panel given a height of zero never appears');

  // The user's settings move both, and the panel has to move with them or the bottom row is clipped.
  check(KeyboardMetrics.totalHeightVp(70, 12) - KeyboardMetrics.totalHeightVp(70, 0) === 12,
    'a height adjustment lands on the total exactly once');
  check(KeyboardMetrics.totalHeightVp(100, 0) - KeyboardMetrics.totalHeightVp(70, 0)
    === 3 * KeyboardMetrics.KEY_ROWS, 'wider row spacing adds one gap per key row');
  check(KeyboardMetrics.totalHeightVp(70, -12) < KeyboardMetrics.totalHeightVp(70, 0),
    'a negative adjustment shortens it');
});

group('the height adjustment is spread across rows without losing a pixel', () => {
  const rows = KeyboardMetrics.KEY_ROWS;
  const base = KeyboardMetrics.ROW_HEIGHT_VP;
  for (const adjustment of [0, 1, 7, 12, -12, 48]) {
    let total = 0;
    for (let index = 0; index < rows; index++) {
      total += KeyboardGeometry.adjustedRowHeight(base, adjustment, rows, index);
    }
    check(total === base * rows + adjustment,
      `the rows still sum to the adjusted total at ${adjustment}`);
  }
  check(KeyboardGeometry.heightAdjustment(null) === KeyboardGeometry.DEFAULT_HEIGHT_ADJUSTMENT_VP,
    'an unset adjustment takes the default rather than clamping to the minimum');
  check(KeyboardGeometry.heightAdjustment(999) === KeyboardGeometry.MAX_HEIGHT_ADJUSTMENT_VP,
    'an out-of-range adjustment is clamped');
});

group('an emoji catalog page is checked before it is trusted', () => {
  const item: EmojiItem = EmojiCatalogModel.item('\u{1f600}', 'grinning', 'Smileys and emotion');
  check(item.text === '\u{1f600}', 'a valid entry survives intact');
  let rejected = false;
  try {
    EmojiCatalogModel.item('', 'empty', 'Smileys and emotion');
  } catch (error) {
    rejected = true;
  }
  check(rejected, 'an entry with no text is refused');
  // Code points, not UTF-16 units: a single emoji is routinely two units and a sequence is more.
  const long = '\u{1f600}'.repeat(MAX_TEXT_CODE_POINTS + 1);
  rejected = false;
  try {
    EmojiCatalogModel.item(long, '', 'Smileys and emotion');
  } catch (error) {
    rejected = true;
  }
  check(rejected, 'length is counted in code points, so a long sequence is still refused');

  const page = EmojiCatalogModel.validatePage([item], 0, EMOJI_PAGE_SIZE, 1, false);
  check(page.nextOffset === 1 && !page.complete, 'a page that advances is accepted');
  rejected = false;
  try {
    // The loop-forever case: not complete, yet the offset has not moved.
    EmojiCatalogModel.validatePage([item], 4, EMOJI_PAGE_SIZE, 4, false);
  } catch (error) {
    rejected = true;
  }
  check(rejected, 'an incomplete page that advances nowhere is refused rather than paged forever');
  rejected = false;
  try {
    EmojiCatalogModel.validatePage([item], 8, EMOJI_PAGE_SIZE, 4, true);
  } catch (error) {
    rejected = true;
  }
  check(rejected, 'an offset that goes backwards is refused');
});

group('recent emoji are most-recent first, deduplicated and bounded', () => {
  const recents = EmojiCatalogModel.recordRecent(['a', 'b'], 'c');
  check(recents[0] === 'c' && recents.length === 3, 'the newest goes to the front');
  const promoted = EmojiCatalogModel.recordRecent(['a', 'b', 'c'], 'b');
  check(promoted[0] === 'b' && promoted.length === 3,
    'choosing one already there promotes it rather than duplicating it');
  const many: string[] = [];
  for (let index = 0; index < EMOJI_RECENTS_LIMIT + 10; index++) {
    many.push(`e${index}`);
  }
  check(EmojiCatalogModel.normalizeRecents(many).length === EMOJI_RECENTS_LIMIT,
    'the stored list is bounded however long it grew');
  check(EmojiCatalogModel.normalizeRecents(null).length === 0, 'nothing stored is no recents');
  check(EmojiCatalogModel.normalizeRecents(['', 'a', 'a']).join(',') === 'a',
    'empty and repeated entries are dropped without discarding the rest');
  check(EmojiCatalogModel.parseRecents('["😀","😀","",42]').join(',') === '😀',
    'persisted recents keep only bounded strings and remove duplicates');
  check(EmojiCatalogModel.parseRecents('{"recent":[]}').length === 0,
    'a recents document with the wrong shape is treated as empty');
  check(EmojiCatalogModel.parseRecents('not json').length === 0,
    'malformed recents do not break the keyboard');
  check(JSON.parse(EmojiCatalogModel.serializeRecents(['b', 'a', 'b']))[0] === 'b',
    'serialization writes the normalized newest-first list');
});

group('engine catalog groups are bounded before reaching the touch panel', () => {
  const groups = normalizeGroups(['happy', '', 'happy', '  ', 42, 'sad']);
  check(groups.join(',') === 'happy,sad', 'kaomoji groups drop invalid and repeated values');
  check(normalizeGroups(['x'.repeat(129)]).length === 0,
    'an oversized group name is ignored');
  check(normalizeGroups(Array.from({ length: 65 }, (_unused, index) => `g${index}`)).length === 0,
    'an oversized group list is rejected as empty');
  check(normalizeGroups(null).length === 0, 'a malformed group response is empty');

  const symbols = normalizeSymbolGroups([
    { parent: 'math', title: '数学' },
    { parent: 'math', title: '数学' },
    { parent: 'math', title: '' },
    { parent: '  ', title: '空白' },
    { parent: 'arrows', title: '箭头' },
    'not an object'
  ]);
  check(symbols.length === 2 && symbols[1].parent === 'arrows',
    'symbol groups validate fields and remove duplicate pairs');
  check(normalizeSymbolGroups([{ parent: 'x'.repeat(129), title: '太长' }]).length === 0,
    'an oversized symbol parent is ignored');
  check(normalizeSymbolGroups(Array.from({ length: 65 }, (_unused, index) =>
    ({ parent: `p${index}`, title: `t${index}` }))).length === 0,
  'an oversized symbol list is rejected as empty');
  check(normalizeSymbolGroups(undefined).length === 0, 'a malformed symbol response is empty');
});

function clip(text: string, at: number, pinned = false): ClipboardHistoryItem {
  return { text, at, pinned };
}

function refuses(action: () => void, failure: ClipboardFailure): boolean {
  try {
    action();
    return false;
  } catch (error) {
    return error instanceof ClipboardHistoryError && error.failure === failure;
  }
}

group('clipboard history is ordered pinned first, then most recent', () => {
  const items = ClipboardHistoryStore.ordered([
    clip('old', 100), clip('new', 300), clip('kept', 200, true)
  ]);
  check(items[0].text === 'kept', 'a pinned entry sorts above an unpinned one however old it is');
  check(items[1].text === 'new' && items[2].text === 'old',
    'the rest are most recent first');
});

group('adding to the clipboard history', () => {
  const existing = [clip('a', 100)];
  const added = ClipboardHistoryStore.add(existing, 'b', 200);
  check(added[0].text === 'b' && added.length === 2, 'a new entry goes to the front');
  const again = ClipboardHistoryStore.add(added, 'a', 300);
  check(again.length === 2 && again[0].text === 'a',
    'text already present is moved rather than duplicated');
  check(refuses(() => ClipboardHistoryStore.add([], '   ', 1), ClipboardFailure.EMPTY),
    'whitespace alone is nothing worth saving');
  const long = 'x'.repeat(ClipboardHistoryStore.LIMIT > 0 ? 10001 : 0);
  check(refuses(() => ClipboardHistoryStore.add([], long, 1), ClipboardFailure.TOO_LONG),
    'an entry past the character bound is refused');

  const full: ClipboardHistoryItem[] = [];
  for (let index = 0; index < ClipboardHistoryStore.LIMIT; index++) {
    full.push(clip(`e${index}`, index));
  }
  const evicted = ClipboardHistoryStore.add(full, 'fresh', 1000);
  check(evicted.length === ClipboardHistoryStore.LIMIT, 'the list stays at its limit');
  check(!evicted.some((entry) => entry.text === 'e0'), 'the oldest unpinned entry made the room');

  const allPinned = full.map((entry) => clip(entry.text, entry.at, true));
  check(refuses(() => ClipboardHistoryStore.add(allPinned, 'fresh', 1000), ClipboardFailure.FULL),
    'with every entry pinned there is nothing to evict, so it refuses rather than dropping a pin');
});

group('a clipboard history document is not trusted because we wrote it', () => {
  check(ClipboardHistoryStore.parse(null).length === 0, 'no file is an empty history');
  check(ClipboardHistoryStore.parse('').length === 0, 'an empty file is an empty history');
  check(refuses(() => ClipboardHistoryStore.parse('{'), ClipboardFailure.INVALID_FILE),
    'a document that will not parse is reported, not silently emptied');
  check(refuses(() => ClipboardHistoryStore.parse('{"text":"a"}'), ClipboardFailure.INVALID_FILE),
    'a document that is not a list is refused');
  check(refuses(() => ClipboardHistoryStore.parse('[{"text":"","at":1,"pinned":false}]'),
    ClipboardFailure.INVALID_FILE), 'an entry the policy would not accept invalidates the file');
  check(refuses(() => ClipboardHistoryStore.parse('[{"text":"a","at":"soon","pinned":false}]'),
    ClipboardFailure.INVALID_FILE), 'a timestamp that is not a number invalidates the file');
  const tooMany = JSON.stringify(
    Array.from({ length: ClipboardHistoryStore.LIMIT + 1 },
      (_unused, index) => clip(`e${index}`, index)));
  check(refuses(() => ClipboardHistoryStore.parse(tooMany), ClipboardFailure.INVALID_FILE),
    'more entries than the limit invalidates the file');
  const good = ClipboardHistoryStore.parse('[{"text":"a","at":1,"pinned":false}]');
  check(good.length === 1 && good[0].text === 'a', 'a sound document round-trips');
});

group('pinning and removing', () => {
  const items = [clip('a', 100), clip('b', 200)];
  const pinned = ClipboardHistoryStore.togglePin(items, 'a');
  check(pinned[0].text === 'a' && pinned[0].pinned, 'pinning moves the entry to the top');
  check(!ClipboardHistoryStore.togglePin(pinned, 'a')[0].pinned
    || ClipboardHistoryStore.togglePin(pinned, 'a')[0].text === 'b',
    'pinning again releases it');
  check(ClipboardHistoryStore.remove(items, 'a').length === 1, 'removing takes one entry');
  check(ClipboardHistoryStore.remove(items, 'missing').length === 2,
    'removing something absent changes nothing');
});

group('account and cloud clipboard bridge keeps secrets native', () => {
  let stored: string | null = null;
  const store: AccountSessionStore = {
    load: () => stored,
    save: value => { stored = value; },
    clear: () => { stored = null; },
  };
  const calls: { method: string; path: string; token?: string; body?: Record<string, unknown> }[] = [];
  const transport: AccountTransport = {
    request: async (method, path, token, body) => {
      calls.push({ method, path, token, body });
      if (path === '/v1/auth/providers') return { status: 200, body: '{"providers":{"email":true,"phone":false}}' };
      if (path === '/v1/auth/challenges') return { status: 200, body: '{"challenge_id":"challenge","expires_in":60}' };
      if (path === '/v1/auth/login') return { status: 200, body: JSON.stringify({
        access_token: 'a'.repeat(64), refresh_token: 'b'.repeat(64), token_type: 'Bearer', expires_in: 3600,
        user: { id: 'u1', display_name: 'Test', created_at: '2026-01-01' }
      }) };
      if (path.includes('/dictionaries/pinyin')) return { status: 200, body: '{"entries":[],"has_more":false,"offset":0}' };
      if (path.includes('/clipboard')) return { status: 200, body: path.endsWith('/clipboard')
        ? '{"enabled":true,"items":[{"id":"1","text":"hello"}]}' : '{}' };
      return { status: 200, body: '{"user":{"id":"u1","display_name":"Test","created_at":"2026-01-01"},"identities":[]}' };
    },
  };
  const bridge = new AccountCloudBridge(transport, store);
  void bridge.handle('{"operation":"request_code","provider":"email","target":"user@example.com"}').then(result => {
    check(JSON.parse(result).ok === true, 'challenge response is structured');
  });
  void bridge.handle('{"operation":"login","challenge_id":"challenge","credential":"123456"}').then(result => {
    check(JSON.parse(result).ok === true && stored !== null, 'login stores a native session');
  });
  void bridge.handle('{"operation":"unknown"}').then(result => {
    check(JSON.parse(result).ok === false, 'unknown clipboard shape is rejected');
  });
  void bridge.handle(JSON.stringify({ operation: 'clipboard', clipboard_operation: 'add', text: '\u0000' })).then(result => {
    check(JSON.parse(result).error === 'account_invalid', 'control characters never reach transport');
  });
  void bridge.handle('{"operation":"profile"}').then(result => {
    check(JSON.parse(result).error === 'account_unauthorized', 'requests before login return unauthorized');
    check(calls.every(call => call.token === undefined), 'invalid requests do not carry a token');
  });
  void bridge.handle(JSON.stringify({ operation: 'dictionary', dictionary_operation: 'list', kind: 'pinyin', offset: 0, search: 'ni hao' })).then(result => {
    check(JSON.parse(result).error === 'account_unauthorized', 'dictionary requests require the native session');
  });
  void bridge.handle(JSON.stringify({ operation: 'dictionary', dictionary_operation: 'list', kind: 'pinyin', offset: -1, search: '' })).then(result => {
    check(JSON.parse(result).error === 'account_invalid', 'dictionary offsets are bounded before transport');
  });
});

// The account bridge deliberately models the asynchronous device HTTP API. Give its immediate
// mock responses one microtask turn before reporting the suite result.
setTimeout(() => {
  console.log('');
  if (failures > 0) {
    throw new Error(`${failures} group(s) failed`);
  }
  console.log(`all groups passed (${checks} assertions)`);
}, 0);
