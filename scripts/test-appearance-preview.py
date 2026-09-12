"""Local synthetic settings UI regression; never loads a native host or user data."""
import argparse
import json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

parser = argparse.ArgumentParser()
parser.add_argument("--url", required=True)
parser.add_argument("--csp", required=True)
parser.add_argument("--executable")
parser.add_argument("--screenshot")
args = parser.parse_args()
assert args.url.startswith("http://127.0.0.1:"), "use a loopback fixture server"

def verify_font_sizes(page, preview):
    for orientation in ["horizontal", "vertical"]:
        page.get_by_label("候选布局", exact=True).select_option(orientation)
        for size in range(12, 33):
            page.get_by_label("候选字号", exact=True).select_option(str(size))
            page.get_by_label("候选窗预编辑字号", exact=True).select_option(str(44 - size))
            expect(preview.locator(".cand .text").first).to_have_css("font-size", f"{size}px")
            expect(preview.locator(".pinyin .text")).to_have_css("font-size", f"{44 - size}px")

def verify_helpcode_display(page, preview):
    count = preview.locator(".cand").count()
    expect(preview.locator(".cand-helpcode")).to_have_count(count)
    page.get_by_role("button", name="辅助码", exact=True).click()
    # Settings order is shuangpin then quanpin; the fixture uses quanpin.
    display = page.get_by_role("checkbox", name="在候选窗口显示辅助码", exact=True).nth(1)
    display.uncheck()
    page.get_by_role("button", name="外观", exact=True).click()
    expect(preview.locator(".cand-helpcode")).to_have_count(0)
    expect(preview.locator(".cand")).to_have_count(count)
    page.get_by_role("button", name="辅助码", exact=True).click()
    display.check()
    page.get_by_role("button", name="外观", exact=True).click()
    expect(preview.locator(".cand-helpcode")).to_have_count(count)

def verify_text_color(page, preview, selected_white=False):
    text = preview.locator(".cand:not(.first) .text").first
    number = preview.locator(".cand:not(.first) .num, .cand:not(.first) .cand-no").first
    original = text.evaluate("el => getComputedStyle(el).color")
    original_number = number.evaluate("el => getComputedStyle(el).color")
    page.get_by_label("候选文字颜色", exact=True).fill("#ab1234")
    expect(page.get_by_label("候选文字颜色", exact=True)).to_have_css("width", "36px")
    expect(page.get_by_label("候选文字颜色", exact=True)).to_have_css("height", "28px")
    expect(page.get_by_role("button", name="跟随主题", exact=True)).to_have_attribute("aria-pressed", "false")
    expect(text).to_have_css("color", "rgb(171, 18, 52)")
    expect(number).to_have_css("color", "rgba(171, 18, 52, 0.616)")
    if selected_white:
        expect(preview.locator(".first .text")).to_have_css("color", "rgb(255, 255, 255)")
    page.get_by_role("button", name="跟随主题", exact=True).click()
    expect(page.get_by_role("button", name="跟随主题", exact=True)).to_have_attribute("aria-pressed", "true")
    expect(text).to_have_css("color", original)
    expect(number).to_have_css("color", original_number)

def verify_font_families(page, preview):
    page.get_by_label("候选窗主字体", exact=True).fill("缺字示例")
    page.get_by_role("button", name="添加补充字体", exact=True).click()
    page.get_by_label("补充字体 1", exact=True).fill("示例字体")
    page.get_by_role("button", name="添加补充字体", exact=True).click()
    page.get_by_label("补充字体 2", exact=True).fill("加倍示例")
    def width():
        return preview.locator(".candidate").evaluate("""el => {
          const ctx = document.createElement('canvas').getContext('2d');
          ctx.font = '20px ' + getComputedStyle(el).fontFamily;
          return ctx.measureText('A').width;
        }""")
    assert abs(width() - 20) < .01
    page.get_by_role("button", name="上移补充字体 2", exact=True).click()
    assert abs(width() - 40) < .01
    page.get_by_role("button", name="移除补充字体 1", exact=True).click()
    assert abs(width() - 20) < .01
    page.get_by_role("button", name="移除补充字体 1", exact=True).click()
    text = preview.locator(".cand .text").first
    original_color = text.evaluate("el => getComputedStyle(el).color")
    page.get_by_label("候选窗主字体", exact=True).fill('示例";color:red;/*')
    family = preview.locator(".candidate").evaluate("el => getComputedStyle(el).fontFamily")
    assert family.endswith("sans-serif") and "color:red;" in family
    expect(text).to_have_css("color", original_color)
    page.get_by_label("候选窗主字体", exact=True).fill("Segoe UI")

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, executable_path=args.executable)
    page = browser.new_page(viewport={"width": 1000, "height": 850})
    page.on("dialog", lambda dialog: dialog.accept())
    page.route(args.url + "/fixture", lambda route: route.fulfill(
        body='<html><head><link rel="stylesheet" href="/settings.css"></head><body><div id="root"></div></body></html>',
        content_type="text/html", headers={"Content-Security-Policy": args.csp}))
    page.goto(args.url + "/fixture")
    page.evaluate("""async base64 => {
      const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0)).buffer;
      window.fixtureFonts = [new FontFace('缺字示例', bytes, {unicodeRange:'U+0042'}), new FontFace('示例字体', bytes), new FontFace('加倍示例', bytes, {sizeAdjust:'200%'})];
      for (const face of window.fixtureFonts) { await face.load(); document.fonts.add(face); }
    }""", json.loads(Path(__file__).with_name("skin-font-fixture.json").read_text())["base64"])
    page.evaluate("async () => { const {mount} = await import('/settings.js'); window.removeFixture = mount(); }")
    preview = page.get_by_role("region", name="候选窗口预览")
    expect(preview.locator(".cand")).to_have_count(6)
    expect(preview.locator(".candidate")).to_have_css("font-size", "16px")
    verify_helpcode_display(page, preview)
    page.get_by_label("全局主题", exact=True).select_option("light")
    expect(page.get_by_label("候选文字颜色", exact=True)).to_have_value("#1a1a1a")
    expect(preview.locator(".appearance-candidate-preview")).to_have_attribute("data-preview-theme", "light")
    light_surface = preview.locator(".container").evaluate("el => getComputedStyle(el).backgroundColor")
    page.get_by_label("设置窗口主题", exact=True).select_option("dark")
    expect(preview.locator(".container")).to_have_css("background-color", light_surface)
    page.get_by_label("候选窗主题", exact=True).select_option("dark")
    assert preview.locator(".container").evaluate("el => getComputedStyle(el).backgroundColor") != light_surface
    page.get_by_label("全局主题", exact=True).select_option("system")
    page.get_by_label("候选窗主题", exact=True).select_option("follow")
    page.emulate_media(color_scheme="light")
    expect(page.get_by_label("候选文字颜色", exact=True)).to_have_value("#1a1a1a")
    expect(preview.locator(".container")).to_have_css("background-color", light_surface)
    page.emulate_media(color_scheme="dark")
    expect(page.get_by_label("候选文字颜色", exact=True)).to_have_value("#e9e8e8")
    expect(preview.locator(".appearance-candidate-preview")).to_have_attribute("data-preview-theme", "dark")
    page.get_by_label("全局主题", exact=True).select_option("dark")
    page.get_by_label("设置窗口主题", exact=True).select_option("follow")
    primary = page.get_by_label("候选窗主字体", exact=True)
    primary.click()
    expect(page.get_by_role("option", name="示例字体", exact=True)).to_be_visible()
    primary.fill("加倍")
    expect(page.get_by_role("listbox", name="候选窗主字体可用字体").get_by_role("option")).to_have_count(1)
    primary.press("ArrowDown")
    primary.press("Enter")
    expect(primary).to_have_value("加倍示例")
    expect(primary).to_have_attribute("aria-expanded", "false")
    primary.fill("Segoe UI")
    primary.press("Escape")
    page.get_by_label("设置窗口主题", exact=True).select_option("light")
    primary.click()
    expect(page.locator(".font-family-menu")).to_have_css("background-color", "rgb(255, 255, 255)")
    expect(page.locator(".font-family-menu")).to_have_css("color", "rgb(36, 36, 36)")
    primary.press("Escape")
    page.get_by_label("设置窗口主题", exact=True).select_option("follow")
    expect(preview.locator(".pinyin")).to_have_css("font-size", "16px")
    verify_font_sizes(page, preview)
    verify_text_color(page, preview)
    verify_font_families(page, preview)
    page.get_by_label("候选布局", exact=True).select_option("horizontal")
    page.get_by_label("候选字号", exact=True).select_option("20")
    page.get_by_label("每页候选数量", exact=True).select_option("9")
    expect(preview.locator(".cand")).to_have_count(9)
    expect(preview.locator(".wnd-h")).to_have_css("font-size", "20px")
    page.get_by_label("候选窗预编辑", exact=True).select_option("empty")
    expect(preview.locator(".pinyin")).to_be_hidden()
    expect(preview.locator(".container.preedit-hidden > .pinyin + .row-wrapper > .first")).to_have_count(1)
    page.get_by_role("button", name="皮肤", exact=True).click()
    page.get_by_role("switch", name="微信绿", exact=True).click()
    page.get_by_role("button", name="外观", exact=True).click()
    expect(preview.locator(".container")).to_have_css("background-color", "rgb(21, 21, 21)")
    verify_text_color(page, preview, selected_white=True)
    expect(preview.locator(".first .text")).to_have_css("color", "rgb(255, 255, 255)")
    page.get_by_label("候选布局", exact=True).select_option("vertical")
    expect(preview.locator(".wnd-v")).to_have_css("font-size", "20px")
    if args.screenshot:
        page.screenshot(path=args.screenshot)
    page.get_by_role("button", name="重新读取", exact=True).click()
    expect(preview.locator(".cand")).to_have_count(6)
    expect(preview.locator(".candidate")).to_have_css("font-size", "16px")
    expect(preview.locator(".pinyin")).to_have_count(1)
    expect(preview.locator(".pinyin")).to_be_visible()
    page.get_by_role("button", name="皮肤", exact=True).click()
    page.get_by_role("switch", name="杨柳青 Willow green", exact=True).click()
    page.get_by_role("button", name="外观", exact=True).click()
    page.get_by_label("候选窗预编辑", exact=True).select_option("empty")
    expect(preview.locator(".pinyin")).to_be_hidden()
    expect(preview.locator(".wnd-v .first")).to_have_css("padding-top", "7px")
    assert "linear-gradient" in preview.locator(".container").evaluate("el => getComputedStyle(el).backgroundImage")
    page.get_by_label("候选布局", exact=True).select_option("horizontal")
    assert "to right" in preview.locator(".container").evaluate("el => getComputedStyle(el).backgroundImage")
    page.get_by_label("每页候选数量", exact=True).select_option("1")
    expect(preview.locator(".cand")).to_have_count(1)
    expect(preview.locator(".container")).to_have_css("background-image", "none")
    expect(preview.locator(".container")).to_have_css("background-color", "rgb(101, 201, 141)")
    page.get_by_label("候选窗预编辑", exact=True).select_option("pinyin")
    expect(preview.locator(".pinyin")).to_be_visible()
    expect(preview.locator(".preedit-hidden")).to_have_count(0)
    page.get_by_label("每页候选数量", exact=True).select_option("6")
    page.get_by_label("候选布局", exact=True).select_option("vertical")
    expect(preview.locator(".container")).to_have_css("background-image", "none")
    page.get_by_role("button", name="皮肤", exact=True).click()
    page.get_by_role("button", name="刷新皮肤", exact=True).click()
    page.get_by_role("switch", name="Synthetic external", exact=True).click()
    page.get_by_role("button", name="外观", exact=True).click()
    expect(preview.locator(".container")).to_have_css("background-color", "rgb(18, 52, 86)")
    expect(preview.locator(".containerParent")).to_have_css("padding-top", "24px")
    verify_helpcode_display(page, preview)
    page.get_by_label("候选窗主题", exact=True).select_option("light")
    expect(preview.locator(".container")).to_have_css("background-color", "rgb(171, 205, 239)")
    page.get_by_label("候选窗主题", exact=True).select_option("dark")
    expect(preview.locator(".container")).to_have_css("background-color", "rgb(18, 52, 86)")
    expect(preview.locator("img.skin-decoration-image")).to_be_visible()
    assert preview.locator("img").evaluate("img => img.complete && img.naturalWidth > 0")
    page.get_by_role("button", name="刷新预览", exact=True).click()
    expect(preview.locator(".container")).to_have_css("background-color", "rgb(18, 52, 86)")
    page.get_by_label("候选布局", exact=True).select_option("horizontal")
    expect(preview.locator(".wnd-h .cand")).to_have_count(6)
    verify_font_sizes(page, preview)
    verify_text_color(page, preview)
    verify_font_families(page, preview)
    if args.screenshot:
        page.screenshot(path=args.screenshot)
    page.evaluate("window.removeFixture()")
    page.evaluate("() => {for (const face of window.fixtureFonts) document.fonts.delete(face); delete window.fixtureFonts;}")
    expect(page.locator("#root")).to_be_empty()
    assert page.evaluate("document.adoptedStyleSheets.length") == 0
    print({"appearanceDraftPreview": True, "fontCatalogSearch": True, "fontFamilyFallbackOrder": True, "fullFontSizeRange": True, "independentPreeditFontSize": True, "textColorAndReset": True, "skinPalette": True, "reload": True, "willowHiddenPreedit": True, "externalPalette": True, "externalDecoration": True, "cleanup": True})
    browser.close()
