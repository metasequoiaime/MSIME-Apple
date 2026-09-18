// @vitest-environment jsdom
import { afterEach, expect, test } from "vitest";
import { cleanup, render } from "@testing-library/react";
import { SkinCandidatePreview } from "../../../packages/ui/src/skin-candidate-preview";
import decorations from "../../../packages/ui/src/skin-candidate-decorations.css?raw";

afterEach(cleanup);

for (const orientation of ["horizontal", "vertical"] as const) {
  for (const appearance of ["dark", "light"] as const) {
    test(`${orientation}/${appearance}: theme decoration selectors match real preview markup`, () => {
      const mounted = render(<>
        <style>{decorations}</style>
        {["wechat", "graphite", "willow_green"].map(skin =>
          <div key={skin} className={`skin-card-preview skin-${skin}`} data-preview-theme={appearance}>
            <SkinCandidatePreview orientation={orientation} />
          </div>)}
        <div className="unrelated"><SkinCandidatePreview orientation={orientation} /></div>
      </>);
      const style = (skin: string, selector: string) => getComputedStyle(mounted.container.querySelector(`.skin-${skin} ${selector}`)!);
      for (const selector of [".first .text", orientation === "horizontal" ? ".first .num" : ".first .cand-no"]) {
        expect(style("wechat", selector).color).toBe("rgb(255, 255, 255)");
        expect(style("willow_green", selector).color).toBe("rgb(255, 255, 255)");
        expect(style("graphite", selector).color).toBe(appearance === "dark" ? "rgb(241, 243, 245)" : "rgb(17, 24, 39)");
      }
      expect(style("wechat", ".container").borderRadius).toBe("5px");
      expect(style("graphite", ".container").padding).toBe("3px 5px");
      expect(style("graphite", ".first").borderRadius).toBe("2px");
      expect(style("willow_green", ".container").borderRadius).toBe("9px");
      expect(style("willow_green", ".container").overflow).toBe("hidden");
      expect(style("willow_green", ".container").getPropertyValue("--wg-surface")).toBe(appearance === "dark" ? "#2d2f2e" : "#f4f5f3");
      expect(style("willow_green", ".row.cand").padding).toBe(orientation === "horizontal" ? "6px 8px" : "4px 14px 4px 8px");
      expect(getComputedStyle(mounted.container.querySelector(".unrelated .container")!).borderRadius).not.toBe("9px");
    });
  }
}

test("all migrated decoration rules stay scoped to skin cards", () => {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(decorations);
  expect(sheet.cssRules.length).toBe(32);
  for (const rule of Array.from(sheet.cssRules)) {
    const selector = (rule as CSSStyleRule).selectorText;
    for (const part of selector.split(",")) expect(part.trim()).toMatch(/^\.skin-card-preview\.skin-/);
  }
});
