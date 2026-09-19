/**
 * The keyboards currently attached to this machine.
 *
 * Enumeration is synchronous per device but the list itself is not, so the first answer arrives
 * after the extension is already running. That ordering is why the caller subscribes from the
 * callback rather than deciding once at creation: a keyboard attached before the keyboard started
 * and one attached a minute later arrive by the same path, and only the hot-plug listener is
 * registered eagerly.
 *
 * A query that fails is reported as no keyboards rather than as an error, because on the machines
 * this matters for — a phone or tablet with nothing plugged in — no keyboards is also the correct
 * answer, and a desktop never consults this at all.
 */
import inputDevice from '@ohos.multimodalInput.inputDevice';
import { KeyboardLog, describeError } from '../KeyboardLog';
import { BusinessErrorPolicy } from '../BusinessErrorPolicy';
import { AttachedInputDevice, AttachedKeyboardType, DeviceChange } from './HardwareKeyboardPolicy';

export class HarmonyHardwareKeyboards {
  private static listener: ((event: inputDevice.DeviceListener) => void) | undefined = undefined;

  /** Every attached device, reduced to the id and keyboard type the policy decides on. */
  static list(received: (devices: AttachedInputDevice[]) => void): void {
    try {
      inputDevice.getDeviceList((error: Object, ids: number[]): void => {
        if (BusinessErrorPolicy.failed(error)) {
          KeyboardLog.error(`input devices unavailable: ${BusinessErrorPolicy.describe(error)}`);
          received([]);
          return;
        }
        received(HarmonyHardwareKeyboards.describe(ids));
      });
    } catch (error) {
      KeyboardLog.error(`input device list refused: ${describeError(error)}`);
      received([]);
    }
  }

  /**
   * Watches for a keyboard being plugged in or unplugged.
   *
   * The type is resolved here, while the device is still attached: an `add` that arrives before the
   * service can describe the device would otherwise be indistinguishable from a keypad, and a
   * `remove` cannot be described at all, so it carries NONE and is matched on its id alone.
   */
  static watch(changed: (change: DeviceChange) => void): void {
    HarmonyHardwareKeyboards.unwatch();
    const listener: (event: inputDevice.DeviceListener) => void =
      (event: inputDevice.DeviceListener): void => {
        const adding: boolean = event.type === 'add';
        changed({
          type: event.type,
          deviceId: event.deviceId,
          keyboardType: adding
            ? HarmonyHardwareKeyboards.keyboardType(event.deviceId) : AttachedKeyboardType.NONE
        });
      };
    try {
      inputDevice.on('change', listener);
      HarmonyHardwareKeyboards.listener = listener;
    } catch (error) {
      KeyboardLog.error(`input device watch refused: ${describeError(error)}`);
    }
  }

  /**
   * Stops watching, with the reference `on` was given.
   *
   * `off` accepts no listener at all, which would remove every subscription in the process rather
   * than this one — harmless while this is the only caller and wrong the moment it is not.
   */
  static unwatch(): void {
    const listener: ((event: inputDevice.DeviceListener) => void) | undefined =
      HarmonyHardwareKeyboards.listener;
    if (listener === undefined) {
      return;
    }
    HarmonyHardwareKeyboards.listener = undefined;
    try {
      inputDevice.off('change', listener);
    } catch (error) {
      KeyboardLog.error(`input device unwatch refused: ${describeError(error)}`);
    }
  }

  private static describe(ids: number[]): AttachedInputDevice[] {
    const devices: AttachedInputDevice[] = [];
    for (const id of ids) {
      devices.push({ deviceId: id, keyboardType: HarmonyHardwareKeyboards.keyboardType(id) });
    }
    return devices;
  }

  private static keyboardType(deviceId: number): AttachedKeyboardType {
    try {
      const type: number = inputDevice.getKeyboardTypeSync(deviceId);
      return type as AttachedKeyboardType;
    } catch (error) {
      KeyboardLog.error(`keyboard type unavailable for ${deviceId}: ${describeError(error)}`);
      return AttachedKeyboardType.UNKNOWN;
    }
  }
}
