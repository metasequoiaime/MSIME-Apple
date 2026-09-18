// Input is a browser-parsed selector, not a whole stylesheet. Strings, comments
// and escapes are opaque; an escaped colon in a class is not a pseudo-class.
export function scopeRootSelector(selector: string): string {
  return selector.replace(/"(?:[^"\\]|\\[\s\S])*"|'(?:[^'\\]|\\[\s\S])*'|\/\*[\s\S]*?\*\/|\\(?:[0-9a-f]{1,6}(?:\r\n|[ \t\r\n\f])?|[\s\S])|:root(?![-_a-zA-Z0-9\\\u0080-\uffff])/gi,
    token => /^:root$/i.test(token) ? ":scope" : token);
}
