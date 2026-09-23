/**
 * What to do with a key that came from a real keyboard.
 *
 * On a phone every keystroke is a tap on a key this app drew, so it arrives already decided. On a
 * 2in1 the keys belong to the machine and reach the input method as hardware events, which have to
 * be claimed one at a time: anything not claimed is delivered to the application as if no input
 * method were running.
 *
 * Claiming too much is the failure that matters. An input method that swallows every key makes
 * shortcuts, arrows and passwords stop working, so the rule here is to claim a key only when there
 * is a composition it belongs to, or when it is the letter that would start one.
 *
 * Pure decision, no side effects, so it can be tested without a device or a session.
 */

/** The subset of the multimodal key event this decision needs. */
export interface HardwareKey {
  readonly keyCode: number;
  /** Resolved by the system, except that a letter's case is not to be trusted: see normalizeLetterCase. */
  readonly unicodeChar: number;
  readonly ctrlKey: boolean;
  readonly altKey: boolean;
  readonly logoKey: boolean;
  readonly shiftKey: boolean;
}

/** What the host should do with the key. Anything but Release is also a claim on the key. */
export enum HardwareKeyAction {
  /** Not ours: hand it to the application untouched. */
  RELEASE,
  /** A letter or digit for the Engine to spell with. */
  COMPOSE,
  /** An ASCII punctuation mark to resolve with the editor-context policy. */
  PUNCTUATION,
  /** Take back the last letter of the composition. */
  BACKSPACE,
  /** Throw the composition away. */
  CANCEL,
  /** Commit the highlighted candidate. */
  COMMIT,
  /** Commit the letters as typed, without choosing a candidate. */
  COMMIT_RAW,
  /** Commit the highlighted candidate's translation when Ctrl+Enter requests it. */
  COMMIT_TRANSLATION,
  /** Choose the candidate at `index`. */
  SELECT,
  /** Commit the first Han character from the highlighted candidate. */
  WORD_CHARACTER_FIRST,
  /** Commit the last Han character from the highlighted candidate. */
  WORD_CHARACTER_LAST,
  /** Consume a disabled navigation binding without turning it into text. */
  IGNORED,
  NEXT_PAGE,
  PREVIOUS_PAGE,
  NEXT_CANDIDATE,
  PREVIOUS_CANDIDATE,
  MOVE_LEFT,
  MOVE_RIGHT,
  MOVE_HOME,
  MOVE_END,
  DELETE_FORWARD,
  BACKSPACE_SEGMENT,
  MOVE_LEFT_SEGMENT,
  MOVE_RIGHT_SEGMENT,
  /** Delete the candidate at `index` from the user dictionary, the Windows maintenance chord. */
  REMOVE_CANDIDATE,
  /** Throw away the Engine's candidate cache for this session, the other Windows maintenance key. */
  RESET_CACHE,
  /** Start or advance Japanese conversion without committing it. */
  JAPANESE_CONVERT,
  /** Commit converted Japanese, or the kana reading when conversion never started. */
  JAPANESE_COMMIT,
  /** Type the printable ASCII `character` as its fullwidth form, the Windows double-byte mode. */
  WIDEN,
  /** Finish the composition, then type `character` after it: a key that carries text but means nothing to the composition. */
  COMMIT_THEN_TYPE,
}

export interface HardwareKeyDecision {
  readonly action: HardwareKeyAction;
  /** The character to compose with, for COMPOSE. */
  readonly character: number;
  /** Which candidate to take, for SELECT. */
  readonly index: number;
}

/** The shared Windows-compatible candidate navigation bindings. */
export interface HardwareNavigationPreferences {
  readonly minusEqual: boolean;
  readonly commaPeriod: boolean;
  readonly brackets: boolean;
  readonly tab: boolean;
  readonly pageUpDown: boolean;
  readonly mouseWheel: boolean;
  readonly arrows: boolean;
}

/**
 * What is being spelled, for the keys whose meaning depends on it.
 *
 * `'`, `;`, the digits and `+` are punctuation or candidate picks for most compositions and part of the spelling for a few. The Windows host decides per key (`IsManualPinyinSeparatorKey`, `IsMicrosoftShuangpinIngKey`, the U-mode digits), and so does the Linux host's `candidate_input`; the rules below are theirs.
 */
export interface HardwareSpelling {
  /** The Engine's `local_mode`, 'none' outside a local utility mode. */
  readonly localMode: string;
  /** The Engine's `editing_text`. */
  readonly editing: string;
  /** Index into `editing`, which is ASCII. */
  readonly caret: number;
  readonly wubi: boolean;
  readonly microsoftShuangpin: boolean;
  /** Ctrl+Shift+E's English candidate mode, where the Engine spells letters only. */
  readonly englishCandidates: boolean;
}

export const PLAIN_SPELLING: HardwareSpelling = {
  localMode: "none",
  editing: "",
  caret: 0,
  wubi: false,
  microsoftShuangpin: false,
  englishCandidates: false,
};

const KEYCODE_SPACE: number = 2050;
const KEYCODE_ENTER: number = 2054;
const KEYCODE_DEL: number = 2055;
const KEYCODE_ESCAPE: number = 2070;
const KEYCODE_NUMPAD_ENTER: number = 2119;
const KEYCODE_DPAD_UP: number = 2012;
const KEYCODE_DPAD_DOWN: number = 2013;
const KEYCODE_DPAD_LEFT: number = 2014;
const KEYCODE_DPAD_RIGHT: number = 2015;
const KEYCODE_TAB: number = 2049;
const KEYCODE_COMMA: number = 2043;
const KEYCODE_PERIOD: number = 2044;
const KEYCODE_MINUS: number = 2057;
const KEYCODE_EQUALS: number = 2058;
const KEYCODE_LEFT_BRACKET: number = 2059;
const KEYCODE_RIGHT_BRACKET: number = 2060;
const KEYCODE_PAGE_UP: number = 2068;
const KEYCODE_PAGE_DOWN: number = 2069;
const KEYCODE_FORWARD_DEL: number = 2071;
const KEYCODE_MOVE_HOME: number = 2081;
const KEYCODE_MOVE_END: number = 2082;
// The number row. Matched by key rather than by the resolved character: with Ctrl+Shift+Alt held
// the system resolves nothing useful, and Shift alone would already have turned 1 into '!'.
const KEYCODE_1: number = 2001;
const KEYCODE_8: number = 2008;
const KEYCODE_9: number = 2009;
const KEYCODE_C: number = 2019;
// The numeric keypad. A keypad digit is the same digit, and a 2in1 keyboard that has one is exactly
// the machine whose user reaches for it: the digits are the whole point of these shortcuts, and
// someone with a keypad should not be told the feature is missing. Windows normalises the keypad in
// one place (`normalize_numpad_digit_key`) so every digit path gets it at once; this is that place.
const KEYCODE_NUMPAD_0: number = 2103;
const KEYCODE_NUMPAD_9: number = 2112;
const KEYCODE_NUMPAD_DOT: number = 2114;
const FULL_STOP: number = 0x2e;
const KEYCODE_0: number = 2000;
const DIGIT_ZERO: number = 0x30;
const KEYCODE_SEMICOLON: number = 2062;
const KEYCODE_APOSTROPHE: number = 2063;
const PLUS: number = 0x2b;
const SEMICOLON: number = 0x3b;
const APOSTROPHE: number = 0x27;
// Local modes whose own spellings are split with `'`, as the Linux host's `accepted_apostrophe` lists them.
const APOSTROPHE_LOCAL_MODES: string[] = ["emoji", "kaomoji", "temporary_japanese"];

const RELEASE: HardwareKeyDecision = {
  action: HardwareKeyAction.RELEASE,
  character: 0,
  index: 0,
};

function decision(
  action: HardwareKeyAction,
  character: number = 0,
  index: number = 0,
): HardwareKeyDecision {
  return { action: action, character: character, index: index };
}

function isAsciiPunctuation(value: number): boolean {
  return (
    (value >= 0x21 && value <= 0x2f) ||
    (value >= 0x3a && value <= 0x40) ||
    (value >= 0x5b && value <= 0x60) ||
    (value >= 0x7b && value <= 0x7e)
  );
}

export class HardwareKeyRouter {
  /**
   * A keypad digit read as the number-row digit it is.
   *
   * Converted unconditionally, which is what the source does with `normalize_numpad_digit_key` and
   * rests on the same assumption: a keypad reports its digit codes only while NumLock is on, and
   * reports navigation codes otherwise, so there is no state in which a digit code means Home. If a
   * device disagreed the digit would win, which is the same way the source would be wrong.
   */
  static normalizeNumpad(key: HardwareKey): HardwareKey {
    if (key.keyCode < KEYCODE_NUMPAD_0 || key.keyCode > KEYCODE_NUMPAD_9) {
      return key;
    }
    const digit: number = key.keyCode - KEYCODE_NUMPAD_0;
    return {
      keyCode: KEYCODE_0 + digit,
      unicodeChar: key.unicodeChar === 0 ? DIGIT_ZERO + digit : key.unicodeChar,
      ctrlKey: key.ctrlKey,
      altKey: key.altKey,
      shiftKey: key.shiftKey,
      logoKey: key.logoKey,
    };
  }

  /**
   * A letter's case decided by the modifiers rather than by `unicodeChar`.
   *
   * A 2in1 reports an upper-case `unicodeChar` for a plain letter key, with neither shift nor caps lock down. The Engine reads an upper-case letter as a help code, which only means something mid-composition, so every first letter typed on a hardware keyboard was declined and the composition never started. Shift and caps lock are both on the event, so the case is rebuilt from them, as the Windows host does from the virtual key and the keyboard state.
   */
  static normalizeLetterCase(key: HardwareKey, capsLock: boolean): HardwareKey {
    const lower: number = key.unicodeChar | 0x20;
    if (lower < 0x61 || lower > 0x7a) {
      return key;
    }
    return {
      keyCode: key.keyCode,
      unicodeChar: key.shiftKey !== capsLock ? lower - 0x20 : lower,
      ctrlKey: key.ctrlKey,
      altKey: key.altKey,
      shiftKey: key.shiftKey,
      logoKey: key.logoKey,
    };
  }

  /**
   * @param composing whether the Engine is holding a composition right now
   * @param chinese whether the Engine would spell with a letter rather than pass it through
   * @param chinesePunctuationInEnglish whether punctuation is still the keyboard's in English mode, which the Windows host does when `punctuation_lock` is Chinese (`ResolvePunctuationOpen`)
   */
  static route(
    key: HardwareKey,
    composing: boolean,
    chinese: boolean,
    releaseNumberRow: boolean = false,
    navigation: HardwareNavigationPreferences = {
      minusEqual: true,
      commaPeriod: true,
      brackets: false,
      tab: true,
      pageUpDown: true,
      mouseWheel: false,
      arrows: true,
    },
    hasHighlightedTranslation: boolean = false,
    japanese: boolean = false,
    wordCharacter: string = "disabled",
    hasHighlightedCandidate: boolean = false,
    spelling: HardwareSpelling = PLAIN_SPELLING,
    fullWidth: boolean = false,
    chinesePunctuationInEnglish: boolean = false,
  ): HardwareKeyDecision {
    // Applied once, before anything reads the key, so no digit path can be left out of it. The
    // resolved character is filled in as well as the code: with Ctrl+Shift+Alt held the system
    // resolves nothing, which is why the chord matches on the code, but candidate selection reads
    // the character and a keypad digit does not always carry one.
    key = HardwareKeyRouter.normalizeNumpad(key);
    // Japanese romaji reserves an unmodified minus for the long-vowel mark. It is a composition key even before the first kana exists. '=' and shifted '-' are never paging keys in Japanese (`IsJapaneseDisabledPagingKey` on Windows): mid-composition they are punctuation that commits the highlighted candidate first, and with nothing composed they are the application's.
    if (
      japanese &&
      !key.ctrlKey &&
      !key.altKey &&
      !key.logoKey &&
      key.keyCode === KEYCODE_MINUS &&
      !key.shiftKey &&
      key.unicodeChar === 0x2d
    ) {
      return decision(HardwareKeyAction.COMPOSE, 0x2d);
    }
    // The Windows maintenance chord: Ctrl+Shift+Alt+1..8 deletes the candidate in that slot from
    // the user dictionary. On a 2in1 it is the only way to reach that action, the long press the
    // touch keyboard uses being a gesture a hardware keyboard has no equivalent for. Whether the
    // slot exists and whether its candidate may be deleted at all are the caller's to check; this
    // only says which key was pressed.
    if (
      composing &&
      key.ctrlKey &&
      key.shiftKey &&
      key.altKey &&
      !key.logoKey &&
      key.keyCode >= KEYCODE_1 &&
      key.keyCode <= KEYCODE_8
    ) {
      return decision(HardwareKeyAction.REMOVE_CANDIDATE, 0, key.keyCode - KEYCODE_1);
    }
    // The cache belongs to the session rather than to a composition, so unlike the slot keys this
    // one answers whether or not something is being spelled — which is also when a stale candidate
    // list is most likely to be what the user is staring at.
    if (key.ctrlKey && key.shiftKey && key.altKey && !key.logoKey && key.keyCode === KEYCODE_C) {
      return decision(HardwareKeyAction.RESET_CACHE);
    }
    // Windows reserves Ctrl+Backspace/Left/Right for editing one Engine segment at a time. Other
    // modifier chords belong to the application, even in the middle of a composition.
    if (composing && key.ctrlKey && !key.altKey && !key.logoKey && !key.shiftKey) {
      // The Windows host claims Ctrl+Enter whenever candidates are up and answers `NavigationIgnored` when there is no translation to commit (`HandleTranslationCommitKey`), so the key is eaten rather than reaching an application that sends a message on it with the spelling still open.
      if (key.keyCode === KEYCODE_ENTER || key.keyCode === KEYCODE_NUMPAD_ENTER) {
        return decision(
          hasHighlightedTranslation
            ? HardwareKeyAction.COMMIT_TRANSLATION
            : HardwareKeyAction.IGNORED,
        );
      }
      if (key.keyCode === KEYCODE_DEL) {
        return decision(HardwareKeyAction.BACKSPACE_SEGMENT);
      }
      if (key.keyCode === KEYCODE_DPAD_LEFT) {
        return decision(HardwareKeyAction.MOVE_LEFT_SEGMENT);
      }
      if (key.keyCode === KEYCODE_DPAD_RIGHT) {
        return decision(HardwareKeyAction.MOVE_RIGHT_SEGMENT);
      }
    }
    if (key.ctrlKey || key.altKey || key.logoKey) {
      return RELEASE;
    }
    // The keypad's decimal point is always an ASCII '.', which is what the Windows host does with `VK_DECIMAL` (`KeyHandler.cpp`, "Numpad decimal should always commit ASCII '.'"): someone typing a number on the keypad wants 3.14, not 3。14. Mid-composition it finishes the composition first, as that host does.
    if (key.keyCode === KEYCODE_NUMPAD_DOT) {
      return composing ? decision(HardwareKeyAction.COMMIT_THEN_TYPE, FULL_STOP) : RELEASE;
    }
    if (composing) {
      if (japanese && key.keyCode === KEYCODE_SPACE) {
        return decision(HardwareKeyAction.JAPANESE_CONVERT);
      }
      if (japanese && (key.keyCode === KEYCODE_ENTER || key.keyCode === KEYCODE_NUMPAD_ENTER)) {
        return decision(HardwareKeyAction.JAPANESE_COMMIT);
      }
      if (key.keyCode === KEYCODE_DEL) {
        return decision(HardwareKeyAction.BACKSPACE);
      }
      if (key.keyCode === KEYCODE_FORWARD_DEL) {
        return decision(HardwareKeyAction.DELETE_FORWARD);
      }
      if (key.keyCode === KEYCODE_MOVE_HOME) {
        return decision(HardwareKeyAction.MOVE_HOME);
      }
      if (key.keyCode === KEYCODE_MOVE_END) {
        return decision(HardwareKeyAction.MOVE_END);
      }
      if (key.keyCode === KEYCODE_DPAD_LEFT) {
        return decision(HardwareKeyAction.MOVE_LEFT);
      }
      if (key.keyCode === KEYCODE_DPAD_RIGHT) {
        return decision(HardwareKeyAction.MOVE_RIGHT);
      }
      if (key.keyCode === KEYCODE_ESCAPE) {
        return decision(HardwareKeyAction.CANCEL);
      }
      if (hasHighlightedCandidate && !key.shiftKey && wordCharacter === "brackets") {
        if (key.keyCode === KEYCODE_LEFT_BRACKET) {
          return decision(HardwareKeyAction.WORD_CHARACTER_FIRST);
        }
        if (key.keyCode === KEYCODE_RIGHT_BRACKET) {
          return decision(HardwareKeyAction.WORD_CHARACTER_LAST);
        }
      }
      if (hasHighlightedCandidate && !key.shiftKey && wordCharacter === "minus_equal") {
        if (key.keyCode === KEYCODE_MINUS) {
          return decision(HardwareKeyAction.WORD_CHARACTER_FIRST);
        }
        if (key.keyCode === KEYCODE_EQUALS) {
          return decision(HardwareKeyAction.WORD_CHARACTER_LAST);
        }
      }
      if (key.keyCode === KEYCODE_SPACE) {
        return decision(HardwareKeyAction.COMMIT);
      }
      if (key.keyCode === KEYCODE_ENTER || key.keyCode === KEYCODE_NUMPAD_ENTER) {
        // Enter on an open composition means "these letters, as I typed them" — the same thing the
        // 重输-adjacent raw commit means on the touch keyboard. The editor's own return action is
        // what Enter does when nothing is being composed, and that is the untouched path below.
        return decision(HardwareKeyAction.COMMIT_RAW);
      }
      // Ahead of navigation and of the number row, both of which would otherwise claim these keys: Shift+= is the `+` of `U+`, and a digit in U mode is part of the code point rather than a pick.
      const spellingDecision: HardwareKeyDecision | undefined = HardwareKeyRouter.spellingKey(
        key,
        spelling,
      );
      if (spellingDecision !== undefined) {
        return spellingDecision;
      }
      const japanesePunctuation: boolean =
        japanese && (key.keyCode === KEYCODE_MINUS || key.keyCode === KEYCODE_EQUALS);
      const navigationDecision: HardwareKeyDecision | undefined = japanesePunctuation
        ? undefined
        : HardwareKeyRouter.navigation(key, navigation);
      if (navigationDecision !== undefined) {
        return navigationDecision;
      }
      // 1 through 9 pick a candidate off the strip while something is being spelled, which is what
      // the number row is for on every desktop input method.
      if (key.unicodeChar >= 0x31 && key.unicodeChar <= 0x39) {
        if (releaseNumberRow) {
          return decision(HardwareKeyAction.COMMIT_THEN_TYPE, key.unicodeChar);
        }
        return decision(HardwareKeyAction.SELECT, 0, key.unicodeChar - 0x31);
      }
    }
    // Only letters start a composition. A digit or a punctuation mark on an empty composition is
    // just that character, and the application can insert it without us in the way.
    const letter: boolean =
      (key.unicodeChar >= 0x61 && key.unicodeChar <= 0x7a) ||
      (key.unicodeChar >= 0x41 && key.unicodeChar <= 0x5a);
    if (!letter) {
      // A Chinese hardware keyboard owns punctuation, composing or not, just as the touch keyboard does. Mid-composition the mark ends it: the shared runtime finishes with the highlighted candidate before translating the mark, which is what the source does in `IsCommitWithHighlightedCandidatePunctuationInCandidateMode`. Releasing it instead left the composition open and dropped the mark into the editor ahead of the letters still being spelled. Navigation punctuation has already been consumed above while composing, so the keys a preference turned into paging keys still page; modifiers remain application-owned. Japanese punctuation is the application's only while nothing is composed: mid-composition it commits the highlighted candidate first, as the source's list of such marks includes Japanese '=', '_' and '+'.
      if (
        (((chinese || chinesePunctuationInEnglish) && !japanese) || (japanese && composing)) &&
        isAsciiPunctuation(key.unicodeChar)
      ) {
        return decision(HardwareKeyAction.PUNCTUATION, key.unicodeChar);
      }
      // Any other character the composition has no use for — a 0, a digit when the number row does not pick — still ends it first. Released as it was, the application inserted the digit while the letters were still open and the commit that followed landed after it: nihao then 0 gave 0你好. The Windows host finalizes the composition before the key goes on (`FUNCTION_FINALIZE_TEXTSTORE` in `IsVirtualKeyNeed`).
      if (composing && key.unicodeChar >= 0x20 && key.unicodeChar <= 0x7e) {
        return decision(HardwareKeyAction.COMMIT_THEN_TYPE, key.unicodeChar);
      }
      return HardwareKeyRouter.passThrough(key, composing, fullWidth);
    }
    // English mode spells nothing the application could not spell itself, so its letters are left
    // alone; the Engine is only worth interrupting for when it turns letters into something else.
    if (!composing && !chinese) {
      return HardwareKeyRouter.passThrough(key, composing, fullWidth);
    }
    return decision(HardwareKeyAction.COMPOSE, key.unicodeChar);
  }

  /**
   * A key nothing above wants: the application's, unless fullwidth is on. Windows eats every printable ASCII key while the double-byte mode is on and there is no candidate list, and inserts its fullwidth form instead (`KeyEventSink.cpp` `IsDoubleSingleByte`, `' '` to `'~'`). Space becomes the ideographic space, as it does everywhere else fullwidth applies. Modifier chords were released before this is reached, so a Ctrl+C still copies.
   */
  private static passThrough(
    key: HardwareKey,
    composing: boolean,
    fullWidth: boolean,
  ): HardwareKeyDecision {
    if (fullWidth && !composing && key.unicodeChar >= 0x20 && key.unicodeChar <= 0x7e) {
      return decision(HardwareKeyAction.WIDEN, key.unicodeChar);
    }
    return RELEASE;
  }

  private static spellingKey(
    key: HardwareKey,
    spelling: HardwareSpelling,
  ): HardwareKeyDecision | undefined {
    // An English word has no syllables, code points or shuangpin finals; the Engine takes letters only there, so these keys stay punctuation.
    if (spelling.englishCandidates) {
      return undefined;
    }
    if (spelling.localMode === "unicode") {
      // U mode spells a hexadecimal code point, so the plain digits are input and Shift+1..9 picks, as on Windows.
      if (!key.shiftKey && key.unicodeChar >= DIGIT_ZERO && key.unicodeChar <= DIGIT_ZERO + 9) {
        return decision(HardwareKeyAction.COMPOSE, key.unicodeChar);
      }
      if (key.shiftKey && key.keyCode >= KEYCODE_1 && key.keyCode <= KEYCODE_9) {
        return decision(HardwareKeyAction.SELECT, 0, key.keyCode - KEYCODE_1);
      }
      // `U+1F600` as well as `u1f600`: the plus is only part of the spelling straight after the U.
      if (key.unicodeChar === PLUS && spelling.editing === "U") {
        return decision(HardwareKeyAction.COMPOSE, PLUS);
      }
      return undefined;
    }
    if (key.shiftKey) {
      return undefined;
    }
    // The manual syllable separator, `xi'an` rather than `xian`. Wubi codes have no syllables to separate, and at the very start there is nothing to separate yet.
    if (
      key.keyCode === KEYCODE_APOSTROPHE &&
      key.unicodeChar === APOSTROPHE &&
      spelling.caret > 0 &&
      ((spelling.localMode === "none" && !spelling.wubi) ||
        APOSTROPHE_LOCAL_MODES.indexOf(spelling.localMode) >= 0)
    ) {
      return decision(HardwareKeyAction.COMPOSE, APOSTROPHE);
    }
    // Microsoft shuangpin puts the `ing` final on `;`, so it is a letter exactly when it would be the second key of a syllable: an odd number of keys since the last separator.
    if (
      spelling.microsoftShuangpin &&
      key.keyCode === KEYCODE_SEMICOLON &&
      key.unicodeChar === SEMICOLON
    ) {
      const caret: number = Math.min(spelling.caret, spelling.editing.length);
      const separator: number = caret === 0 ? -1 : spelling.editing.lastIndexOf("'", caret - 1);
      if ((caret - (separator + 1)) % 2 === 1) {
        return decision(HardwareKeyAction.COMPOSE, SEMICOLON);
      }
    }
    return undefined;
  }

  private static navigation(
    key: HardwareKey,
    preferences: HardwareNavigationPreferences,
  ): HardwareKeyDecision | undefined {
    let previous: boolean = false;
    let enabled: boolean;
    if (key.keyCode === KEYCODE_DPAD_UP || key.keyCode === KEYCODE_DPAD_DOWN) {
      if (preferences.arrows) {
        return decision(
          key.keyCode === KEYCODE_DPAD_UP
            ? HardwareKeyAction.PREVIOUS_CANDIDATE
            : HardwareKeyAction.NEXT_CANDIDATE,
        );
      }
      enabled = false;
    } else if (key.keyCode === KEYCODE_PAGE_UP || key.keyCode === KEYCODE_PAGE_DOWN) {
      previous = key.keyCode === KEYCODE_PAGE_UP;
      enabled = preferences.pageUpDown;
    } else if (key.keyCode === KEYCODE_TAB) {
      previous = key.shiftKey;
      enabled = preferences.tab;
    } else if (key.keyCode === KEYCODE_MINUS || key.keyCode === KEYCODE_EQUALS) {
      previous = key.keyCode === KEYCODE_MINUS;
      enabled = preferences.minusEqual;
    } else if (key.keyCode === KEYCODE_COMMA || key.keyCode === KEYCODE_PERIOD) {
      previous = key.keyCode === KEYCODE_COMMA;
      enabled = preferences.commaPeriod;
    } else if (key.keyCode === KEYCODE_LEFT_BRACKET || key.keyCode === KEYCODE_RIGHT_BRACKET) {
      previous = key.keyCode === KEYCODE_LEFT_BRACKET;
      enabled = preferences.brackets;
    } else {
      return undefined;
    }
    return decision(
      enabled
        ? previous
          ? HardwareKeyAction.PREVIOUS_PAGE
          : HardwareKeyAction.NEXT_PAGE
        : HardwareKeyAction.IGNORED,
    );
  }
}
