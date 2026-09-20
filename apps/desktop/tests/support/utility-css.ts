import styles from "../../../../packages/ui/src/styles.css?raw";

/**
 * The body of one `@utility` block from the shared stylesheet, as plain CSS a jsdom `CSSStyleSheet`
 * can parse.
 *
 * The preview rules used to sit in stylesheets of their own, which these tests imported with `?raw`.
 * They are nested inside a utility now, so `&` has to become the class the utility defines before the
 * text is valid on its own. Nothing else is rewritten: the descendants stay exactly as authored.
 */
export function utilityCss(name: string): string {
  const opening = `@utility ${name} {`;
  const at = styles.indexOf(opening);
  if (at < 0) throw new Error(`no @utility ${name} in styles.css`);
  let depth = 0;
  let end = at + opening.length - 1;
  for (let i = end; i < styles.length; i += 1) {
    if (styles[i] === "{") depth += 1;
    else if (styles[i] === "}") {
      depth -= 1;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  return styles.slice(at + opening.length, end).replaceAll("&", `.${name}`);
}
