/**
 * Turning a routed hardware key into the thing the session does about it.
 *
 * The router decides what a key means and the session knows how to do it; this is the mapping
 * between them, which used to live as a twenty-five case switch inside the extension ability where
 * nothing could reach it. Both ends were covered and the join was not, so a case wired to the wrong
 * method — a left arrow calling moveRight, a page key calling the candidate one — would have looked
 * exactly like working code until someone typed on a 2in1.
 *
 * It is a pure function over an interface rather than over the session itself because ArkTS has no
 * structural typing: naming what the hardware path needs is what lets a test stand in for it.
 */
import { CandidateTextEdge } from "./input/CandidateTextPolicy";
import { HardwareKeyAction, HardwareKeyDecision } from "./HardwareKeyRouter";

/** Everything a routed hardware key can ask of the keyboard. */
export interface HardwareKeyTarget {
  /** Whether the key did anything; a letter the Engine declines goes back to the application. */
  press(character: number, shifted: boolean): boolean;
  punctuation(character: number): void;
  backspace(): void;
  cancel(): void;
  moveLeft(): void;
  moveRight(): void;
  moveHome(): void;
  moveEnd(): void;
  deleteForward(): void;
  backspaceSegment(): void;
  moveLeftSegment(): void;
  moveRightSegment(): void;
  commitHighlighted(): void;
  commitRaw(): void;
  commitTranslation(): void;
  choose(index: number): void;
  resetCache(): void;
  removeManagedCandidate(index: number): boolean;
  selectEdge(edge: CandidateTextEdge): void;
  nextPage(): void;
  previousPage(): void;
  nextCandidate(): void;
  previousCandidate(): void;
  convertJapanese(): boolean;
  commitJapanese(): boolean;
}

export class HardwareKeyDispatch {
  /**
   * Do what the decision says.
   *
   * RELEASE never arrives here — the caller hands the key back to the application before this is
   * reached — and IGNORED is a key deliberately consumed without an effect, which is how a disabled
   * navigation binding stops being text rather than becoming a stray character.
   *
   * Returns whether the key was consumed. Only a letter can come back unconsumed: the Engine declines an upper-case letter with nothing composed, and a key that was claimed and then did nothing is a character the user typed and never saw.
   */
  static apply(
    decision: HardwareKeyDecision,
    shifted: boolean,
    target: HardwareKeyTarget,
  ): boolean {
    switch (decision.action) {
      case HardwareKeyAction.COMPOSE:
        return target.press(decision.character, shifted);
      case HardwareKeyAction.PUNCTUATION:
        target.punctuation(decision.character);
        break;
      case HardwareKeyAction.BACKSPACE:
        target.backspace();
        break;
      case HardwareKeyAction.CANCEL:
        target.cancel();
        break;
      case HardwareKeyAction.MOVE_LEFT:
        target.moveLeft();
        break;
      case HardwareKeyAction.MOVE_RIGHT:
        target.moveRight();
        break;
      case HardwareKeyAction.MOVE_HOME:
        target.moveHome();
        break;
      case HardwareKeyAction.MOVE_END:
        target.moveEnd();
        break;
      case HardwareKeyAction.DELETE_FORWARD:
        target.deleteForward();
        break;
      case HardwareKeyAction.BACKSPACE_SEGMENT:
        target.backspaceSegment();
        break;
      case HardwareKeyAction.MOVE_LEFT_SEGMENT:
        target.moveLeftSegment();
        break;
      case HardwareKeyAction.MOVE_RIGHT_SEGMENT:
        target.moveRightSegment();
        break;
      case HardwareKeyAction.COMMIT:
        target.commitHighlighted();
        break;
      case HardwareKeyAction.COMMIT_RAW:
        target.commitRaw();
        break;
      case HardwareKeyAction.COMMIT_TRANSLATION:
        target.commitTranslation();
        break;
      case HardwareKeyAction.SELECT:
        target.choose(decision.index);
        break;
      case HardwareKeyAction.RESET_CACHE:
        target.resetCache();
        break;
      case HardwareKeyAction.REMOVE_CANDIDATE:
        target.removeManagedCandidate(decision.index);
        break;
      case HardwareKeyAction.WORD_CHARACTER_FIRST:
        target.selectEdge(CandidateTextEdge.FIRST);
        break;
      case HardwareKeyAction.WORD_CHARACTER_LAST:
        target.selectEdge(CandidateTextEdge.LAST);
        break;
      case HardwareKeyAction.NEXT_PAGE:
        target.nextPage();
        break;
      case HardwareKeyAction.PREVIOUS_PAGE:
        target.previousPage();
        break;
      case HardwareKeyAction.NEXT_CANDIDATE:
        target.nextCandidate();
        break;
      case HardwareKeyAction.PREVIOUS_CANDIDATE:
        target.previousCandidate();
        break;
      case HardwareKeyAction.JAPANESE_CONVERT:
        // Space the conversion does not claim (a lone Fallback row, which is the raw composition) commits the way Space does outside Japanese.
        if (!target.convertJapanese()) {
          target.commitHighlighted();
        }
        break;
      case HardwareKeyAction.JAPANESE_COMMIT:
        target.commitJapanese();
        break;
      default:
        break;
    }
    return true;
  }
}
