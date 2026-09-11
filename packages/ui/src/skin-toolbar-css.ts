import { hasUnresolvedCssResource } from "./css-image-value.js";
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
  function sanitize(container: CSSStyleSheet | CSSGroupingRule | CSSStyleRule) {
    // Edit the parsed tree in place so declarations after a nested rule retain
    // their native CSSNestedDeclarations ordering and pseudo-element semantics.
    for (let index = container.cssRules.length - 1; index >= 0; index--) {
      const rule = container.cssRules[index];
      const nestedDeclarations = rule.constructor.name === "CSSNestedDeclarations";
      if (rule.type === CSSRule.STYLE_RULE || nestedDeclarations) {
        const styleRule = rule as CSSStyleRule;
        // Resource rewriting is a separate migration step. Do not resolve skin
        // URLs relative to the settings page or permit escaped resource syntax.
        for (const name of Array.from(styleRule.style)) {
          if (hasUnresolvedCssResource(styleRule.style.getPropertyValue(name))) {
            styleRule.style.removeProperty(name); partial = true;
          }
        }
        if (!nestedDeclarations && styleRule.cssRules?.length) sanitize(styleRule);
      } else if (rule.type === CSSRule.MEDIA_RULE || rule.type === CSSRule.SUPPORTS_RULE) {
        sanitize(rule as CSSGroupingRule);
      } else {
        // Fonts, keyframes and other globally named rules need their own
        // resource/name isolation; do not leak them into the settings document.
        partial = true;
        container.deleteRule(index);
      }
    }
  }
  sanitize(parsed);
  for (const rule of Array.from(parsed.cssRules)) target.insertRule(rule.cssText, target.cssRules.length);
  document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
  return { partial, remove: () => { document.adoptedStyleSheets = document.adoptedStyleSheets.filter(existing => existing !== sheet); } };
}
