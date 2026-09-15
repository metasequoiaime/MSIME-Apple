/**
 * One place for the keyboard's diagnostics.
 *
 * An InputMethodExtensionAbility is started by the framework and has no console, so a failure during
 * startup is otherwise silent: the panel simply never appears and there is nothing to read. Every
 * refusal path logs why.
 *
 * The domain is what hilog filters on, and the tag is what `hdc shell hilog | grep MSIME` finds.
 */
import hilog from '@ohos.hilog';

const DOMAIN: number = 0x0051;
const TAG: string = 'MSIME';

/** OHOS rejects with a BusinessError carrying code and message; it is not an Error instance. */
export function describeError(error: unknown): string {
  if (error instanceof Error) {
    // The message alone rarely says which of several native calls threw, and an extension ability
    // has no debugger attached, so the stack travels with it.
    return error.stack === undefined ? error.message : `${error.message} | ${error.stack}`;
  }
  if (typeof error === 'object' && error !== null) {
    const record = error as Record<string, unknown>;
    const code = record.code === undefined ? '?' : String(record.code);
    const message = record.message === undefined ? JSON.stringify(error) : String(record.message);
    return `code ${code}: ${message}`;
  }
  return String(error);
}

export class KeyboardLog {
  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message);
  }

  static error(message: string): void {
    // Two channels on purpose: hilog's app domain is easy to filter but easy to lose to buffer
    // rotation, while console reaches the JSAPP domain. A startup failure is worth saying twice.
    hilog.error(DOMAIN, TAG, '%{public}s', message);
    console.error(`${TAG} ${message}`);
  }
}
