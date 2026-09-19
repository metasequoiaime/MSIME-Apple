/**
 * Whether the machine currently has keys the user can compose pinyin on.
 *
 * The panel a device gets is decided by what the device *is*: a phone draws a soft keyboard, a 2in1
 * draws only a candidate window because its keys are already under the user's hands. Which physical
 * keys reach the Engine is a different question, and bundling the two cost the phone every external
 * keyboard: with no `keyEvent` subscription the framework hands the key straight to the editor, so a
 * tablet or phone with a keyboard attached types raw latin letters and composes nothing at all. The
 * form factor answers "draw keys?"; this answers "route keys?", and they are only the same answer on
 * a machine with no ports.
 *
 * A device's own buttons are not a keyboard. Every phone enumerates a `keyboard` source for volume
 * and power, so testing `sources` would report a full keyboard on hardware that has none — the
 * keyboard *type* is what separates them, and only ALPHABETIC_KEYBOARD can produce the letters a
 * composition is built from. A keypad, a stylus and a remote control are all real input devices and
 * none of them can type `nihao`.
 */

/** The subset of `inputDevice.KeyboardType` this policy decides on. Mirrors the SDK's numbering. */
export enum AttachedKeyboardType {
  NONE = 0,
  UNKNOWN = 1,
  ALPHABETIC = 2,
  DIGITAL = 3,
  HANDWRITING_PEN = 4,
  REMOTE_CONTROL = 5,
}

/** One enumerated input device, reduced to what the decision depends on. */
export interface AttachedInputDevice {
  readonly deviceId: number;
  readonly keyboardType: AttachedKeyboardType;
}

export class HardwareKeyboardPolicy {
  /**
   * Whether physical keys should be routed through the Engine.
   *
   * A desktop is always yes and never consults the enumeration: its keys are the only way anything
   * reaches the Engine at all, and a machine that draws no keys must not be left inert because a
   * device query failed or returned nothing. Elsewhere it takes one attached alphabetic keyboard.
   */
  static routes(desktop: boolean, devices: readonly AttachedInputDevice[] | null): boolean {
    if (desktop) {
      return true;
    }
    return HardwareKeyboardPolicy.alphabetic(devices).length > 0;
  }

  /** The attached devices that can actually type letters, in enumeration order, de-duplicated. */
  static alphabetic(devices: readonly AttachedInputDevice[] | null): number[] {
    if (devices === null || devices === undefined) {
      return [];
    }
    const found: number[] = [];
    for (const device of devices) {
      if (device === null || device === undefined) {
        continue;
      }
      if (!Number.isInteger(device.deviceId) || device.deviceId < 0) {
        continue;
      }
      if (device.keyboardType !== AttachedKeyboardType.ALPHABETIC) {
        continue;
      }
      if (found.indexOf(device.deviceId) < 0) {
        found.push(device.deviceId);
      }
    }
    return found;
  }

  /**
   * The enumeration after a hot-plug notification.
   *
   * A keyboard unplugged mid-composition is the case worth being careful about: the device is gone
   * before its key-up arrives, so removal is keyed on the id alone and never on the type, which the
   * service can no longer be asked for.
   */
  static applyChange(
    devices: readonly AttachedInputDevice[] | null,
    change: DeviceChange | null,
  ): AttachedInputDevice[] {
    const current: AttachedInputDevice[] = [];
    if (devices !== null && devices !== undefined) {
      for (const device of devices) {
        if (device !== null && device !== undefined) {
          current.push(device);
        }
      }
    }
    if (change === null || change === undefined || !Number.isInteger(change.deviceId)) {
      return current;
    }
    const remaining: AttachedInputDevice[] = current.filter(
      (device: AttachedInputDevice): boolean => device.deviceId !== change.deviceId,
    );
    if (change.type !== "add") {
      return remaining;
    }
    remaining.push({ deviceId: change.deviceId, keyboardType: change.keyboardType });
    return remaining;
  }

  /**
   * Whether the subscription has to change, given what is already subscribed.
   *
   * Subscribing twice would route every key twice — one keystroke, two characters — and the
   * framework will not de-duplicate a second `on('keyEvent')` for you. Returns null when the current
   * state is already right, so a hot-plug that changes nothing touches nothing.
   */
  static transition(subscribed: boolean, shouldRoute: boolean): KeyRoutingTransition | null {
    if (subscribed === shouldRoute) {
      return null;
    }
    return shouldRoute ? KeyRoutingTransition.SUBSCRIBE : KeyRoutingTransition.UNSUBSCRIBE;
  }
}

/** A hot-plug notification, with the type resolved while the device is still present. */
export interface DeviceChange {
  readonly type: string;
  readonly deviceId: number;
  readonly keyboardType: AttachedKeyboardType;
}

export enum KeyRoutingTransition {
  SUBSCRIBE = "subscribe",
  UNSUBSCRIBE = "unsubscribe",
}
