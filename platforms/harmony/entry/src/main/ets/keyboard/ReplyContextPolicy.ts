/** Generation-only identity for asynchronous reply requests; it never stores editor text. */
export class ReplyContextPolicy {
  static matches(expectedEditor: number, actualEditor: number,
                  expectedContext: number, actualContext: number): boolean {
    return Number.isSafeInteger(expectedEditor) && Number.isSafeInteger(actualEditor)
      && Number.isSafeInteger(expectedContext) && Number.isSafeInteger(actualContext)
      && expectedEditor >= 0 && actualEditor >= 0 && expectedContext >= 0 && actualContext >= 0
      && expectedEditor === actualEditor && expectedContext === actualContext;
  }
}
