/**
 * Candidate-management menu order and host operation metadata, ported from
 * platforms/android/java/app/msime/client/CandidateManagementAction.java.
 *
 * The menu item ids are derived from the declaration order, so the order is part of the contract with
 * whatever renders the menu.
 */
const MENU_ITEM_BASE: number = 1000;

export interface ManagementAction {
  readonly id: string;
  readonly title: string;
  readonly announcement: string;
  readonly confirmationRequired: boolean;
  readonly menuItemId: number;
  readonly position?: number;
  readonly checked?: boolean;
  readonly available?: boolean;
}

function action(index: number, id: string, title: string, announcement: string,
                confirmationRequired: boolean): ManagementAction {
  return {
    id: id, title: title, announcement: announcement,
    confirmationRequired: confirmationRequired, menuItemId: MENU_ITEM_BASE + index
  };
}

const ACTIONS: ManagementAction[] = [
  action(0, 'PROMOTE', '优先显示', '已优先显示', false),
  action(1, 'FIX_FIRST', '固定到首位', '已固定到首位', false),
  action(2, 'CLEAR_POSITION', '取消固定', '已取消固定', false),
  action(3, 'REMOVE', '删除词条…', '已删除词条', true)
];

export class CandidateManagementAction {
  static readonly ACTIONS: ManagementAction[] = ACTIONS;
  static readonly PROMOTE: ManagementAction = ACTIONS[0];
  static readonly FIX_FIRST: ManagementAction = ACTIONS[1];
  static readonly CLEAR_POSITION: ManagementAction = ACTIONS[2];
  static readonly REMOVE: ManagementAction = ACTIONS[3];

  /** Windows exposes all five fixed slots and marks the currently held slot. */
  static actionsForFixedPosition(fixedPosition: number, available: boolean = true,
                                  includeRemove: boolean = true): ManagementAction[] {
    const actions: ManagementAction[] = [{ ...CandidateManagementAction.PROMOTE, available: available }];
    for (let position: number = 1; position <= 5; position++) {
      actions.push({
        id: `FIX_${position}`,
        title: `第 ${position} 位`,
        announcement: `已固定到第 ${position} 位`,
        confirmationRequired: false,
        menuItemId: MENU_ITEM_BASE + position,
        position: position,
        checked: fixedPosition === position,
        available: available
      });
    }
    actions.push({
      ...CandidateManagementAction.CLEAR_POSITION,
      menuItemId: MENU_ITEM_BASE + 6,
      available: available && fixedPosition > 0
    });
    if (includeRemove) {
      actions.push({
        ...CandidateManagementAction.REMOVE,
        menuItemId: MENU_ITEM_BASE + 7,
        available: available
      });
    }
    return actions;
  }

  /** Windows omits deletion for a single Unicode code point. */
  static hasMultipleCodePoints(text: string): boolean {
    return Array.from(text).length !== 1;
  }

  /** Dictionary mutations are only valid for local/user-dictionary candidates. */
  static candidateActionsAvailable(scheme: string, source: number): boolean {
    if (scheme === 'japanese') {
      return false;
    }
    return source === 0 || source === 1 || source === 4;
  }

  static fromMenuItemId(itemId: number): ManagementAction {
    const index: number = itemId - MENU_ITEM_BASE;
    if (index < 0 || index >= ACTIONS.length) {
      throw new Error('Unknown candidate management action');
    }
    return ACTIONS[index];
  }

  static fixedPosition(entry: ManagementAction): number {
    if (entry !== CandidateManagementAction.FIX_FIRST) {
      throw new Error('Action does not fix a position');
    }
    return 1;
  }

  static validatePosition(position: number): number {
    if (position < 1 || position > 5) {
      throw new Error('Candidate position must be between 1 and 5');
    }
    return position;
  }
}
