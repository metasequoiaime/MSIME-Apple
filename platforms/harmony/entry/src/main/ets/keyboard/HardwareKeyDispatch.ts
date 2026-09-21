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
  press(character: number, shifted: boolean): void;
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
   */
  static apply(decision: HardwareKeyDecision, shifted: boolean, target: HardwareKeyTarget): void {
    switch (decision.action) {
      case HardwareKeyAction.COMPOSE:
        target.press(decision.character, shifted);
        return;
      case HardwareKeyAction.PUNCTUATION:
        target.punctuation(decision.character);
        return;
      case HardwareKeyAction.BACKSPACE:
        target.backspace();
        return;
      case HardwareKeyAction.CANCEL:
        target.cancel();
        return;
      case HardwareKeyAction.MOVE_LEFT:
        target.moveLeft();
        return;
      case HardwareKeyAction.MOVE_RIGHT:
        target.moveRight();
        return;
      case HardwareKeyAction.MOVE_HOME:
        target.moveHome();
        return;
      case HardwareKeyAction.MOVE_END:
        target.moveEnd();
        return;
      case HardwareKeyAction.DELETE_FORWARD:
        target.deleteForward();
        return;
      case HardwareKeyAction.BACKSPACE_SEGMENT:
        target.backspaceSegment();
        return;
      case HardwareKeyAction.MOVE_LEFT_SEGMENT:
        target.moveLeftSegment();
        return;
      case HardwareKeyAction.MOVE_RIGHT_SEGMENT:
        target.moveRightSegment();
        return;
      case HardwareKeyAction.COMMIT:
        target.commitHighlighted();
        return;
      case HardwareKeyAction.COMMIT_RAW:
        target.commitRaw();
        return;
      case HardwareKeyAction.COMMIT_TRANSLATION:
        target.commitTranslation();
        return;
      case HardwareKeyAction.SELECT:
        target.choose(decision.index);
        return;
      case HardwareKeyAction.RESET_CACHE:
        target.resetCache();
        return;
      case HardwareKeyAction.REMOVE_CANDIDATE:
        target.removeManagedCandidate(decision.index);
        return;
      case HardwareKeyAction.WORD_CHARACTER_FIRST:
        target.selectEdge(CandidateTextEdge.FIRST);
        return;
      case HardwareKeyAction.WORD_CHARACTER_LAST:
        target.selectEdge(CandidateTextEdge.LAST);
        return;
      case HardwareKeyAction.NEXT_PAGE:
        target.nextPage();
        return;
      case HardwareKeyAction.PREVIOUS_PAGE:
        target.previousPage();
        return;
      case HardwareKeyAction.NEXT_CANDIDATE:
        target.nextCandidate();
        return;
      case HardwareKeyAction.PREVIOUS_CANDIDATE:
        target.previousCandidate();
        return;
      case HardwareKeyAction.JAPANESE_CONVERT:
        target.convertJapanese();
        return;
      case HardwareKeyAction.JAPANESE_COMMIT:
        target.commitJapanese();
        return;
      default:
        return;
    }
  }
}
