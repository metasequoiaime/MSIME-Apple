// Parse first, then insert rules into a browser-created scope. Concatenating an
// untrusted stylesheet inside @scope would let an unmatched brace escape it.
export function installToolbarCss(scope: string, css: string): { remove: () => void; partial: boolean } {
  if (!/^[a-zA-Z][a-zA-Z0-9_-]*$/.test(scope) || !("adoptedStyleSheets" in document)) throw new Error("unsupported scope");
  const parsed = new CSSStyleSheet();
  parsed.replaceSync(css.replace(/:root\b/g, ":scope"));
  const sheet = new CSSStyleSheet();
  sheet.insertRule(`@scope (.${scope}) {}`, 0);
  const target = sheet.cssRules[0] as CSSGroupingRule;
  if (!target.cssRules || !target.insertRule) throw new Error("scope unavailable");
  let partial = /@import\b/i.test(css); // Constructed sheets discard imports.
  function copy(rules: CSSRuleList, into: CSSGroupingRule) {
    for (const rule of Array.from(rules)) {
      if (rule.type === CSSRule.STYLE_RULE) {
        const styleRule = rule as CSSStyleRule;
        // Resource rewriting is a separate migration step. Do not resolve skin
        // URLs relative to the settings page or permit escaped resource syntax.
        for (const name of Array.from(styleRule.style)) {
          if (/url\s*\(|image-set\s*\(|src\s*\(|\\/i.test(styleRule.style.getPropertyValue(name))) {
            styleRule.style.removeProperty(name); partial = true;
          }
        }
        if (styleRule.cssRules?.length) { partial = true; continue; }
        into.insertRule(styleRule.cssText, into.cssRules.length);
      } else if (rule.type === CSSRule.MEDIA_RULE || rule.type === CSSRule.SUPPORTS_RULE) {
        const grouping = rule as CSSConditionRule;
        const prefix = rule.type === CSSRule.MEDIA_RULE ? "@media" : "@supports";
        const index = into.insertRule(`${prefix} ${grouping.conditionText} {}`, into.cssRules.length);
        copy(grouping.cssRules, into.cssRules[index] as CSSGroupingRule);
      } else {
        // Fonts, keyframes and other globally named rules need their own
        // resource/name isolation; do not leak them into the settings document.
        partial = true;
      }
    }
  }
  copy(parsed.cssRules, target);
  document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
  return { partial, remove: () => { document.adoptedStyleSheets = document.adoptedStyleSheets.filter(existing => existing !== sheet); } };
}
