// Names are decoded by the browser using the same grammar as @keyframes.
// A sticky token scan keeps quoted/escaped commas inside their name.
export function rewriteAnimationNames(value: string, names: ReadonlyMap<string, string>): { value: string; partial: boolean } {
  const token = /"(?:[^"\\]|\\[\s\S])*"|'(?:[^'\\]|\\[\s\S])*'|(?:\\(?:[0-9a-f]{1,6}(?:\r\n|[ \t\r\n\f])?|[\s\S])|[^\s,'"()\\])+/giy;
  const output: string[] = [];
  const parser = new CSSStyleSheet();
  let offset = 0, partial = false;
  while (offset < value.length) {
    while (/\s/.test(value[offset] ?? "")) offset++;
    token.lastIndex = offset;
    const match = token.exec(value);
    if (!match) return { value: "none", partial: true };
    offset = token.lastIndex;
    if (/^(none|initial|unset)$/i.test(match[0])) output.push("none");
    else {
      parser.replaceSync("@keyframes " + match[0] + " {}");
      const rule = parser.cssRules[0] as CSSKeyframesRule | undefined;
      const replacement = parser.cssRules.length === 1 && rule?.type === CSSRule.KEYFRAMES_RULE ? names.get(rule.name) : undefined;
      output.push(replacement ?? "none");
      if (!replacement) partial = true;
    }
    while (/\s/.test(value[offset] ?? "")) offset++;
    if (offset === value.length) break;
    if (value[offset++] !== "," || offset === value.length) return { value: "none", partial: true };
  }
  return { value: output.join(", ") || "none", partial: partial || !output.length };
}

let generation = 0;
export function isolateToolbarAnimations(sheet: CSSStyleSheet): boolean {
  const prefix = "msime-skin-animation-" + ++generation + "-";
  const names = new Map<string, string>();
  function visit(rules: CSSRuleList, action: (rule: CSSRule) => void) {
    for (const rule of Array.from(rules)) {
      action(rule);
      if (rule.type === CSSRule.STYLE_RULE || rule.type === CSSRule.MEDIA_RULE || rule.type === CSSRule.SUPPORTS_RULE) {
        const nested = (rule as CSSGroupingRule).cssRules;
        if (nested) visit(nested, action);
      }
    }
  }
  visit(sheet.cssRules, rule => {
    if (rule.type !== CSSRule.KEYFRAMES_RULE) return;
    const frames = rule as CSSKeyframesRule;
    if (!names.has(frames.name)) names.set(frames.name, prefix + names.size);
    frames.name = names.get(frames.name)!;
  });
  let partial = false;
  visit(sheet.cssRules, rule => {
    if (rule.type !== CSSRule.STYLE_RULE && rule.constructor.name !== "CSSNestedDeclarations") return;
    const style = (rule as CSSStyleRule).style;
    if (!Array.from(style).includes("animation-name")) return;
    const rewritten = rewriteAnimationNames(style.getPropertyValue("animation-name"), names);
    partial ||= rewritten.partial;
    // Setting only the longhand preserves duration, delay, easing and priority.
    // Unresolved var() shorthand/name is disabled until it can be isolated.
    style.setProperty("animation-name", rewritten.value, style.getPropertyPriority("animation-name"));
  });
  return partial;
}
