"""Local synthetic settings UI regression; never loads a native host or user data."""
import argparse
from playwright.sync_api import sync_playwright, expect

parser = argparse.ArgumentParser()
parser.add_argument("--url", required=True)
parser.add_argument("--csp", required=True)
parser.add_argument("--executable")
parser.add_argument("--screenshot")
args = parser.parse_args()
assert args.url.startswith("http://127.0.0.1:"), "use a loopback fixture server"
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, executable_path=args.executable)
    page = browser.new_page(viewport={"width": 1000, "height": 850})
    page.on("dialog", lambda dialog: dialog.accept())
    page.route(args.url + "/fixture", lambda route: route.fulfill(
        body='<html><head><link rel="stylesheet" href="/settings.css"></head><body><div id="root"></div></body></html>',
        content_type="text/html", headers={"Content-Security-Policy": args.csp}))
    page.goto(args.url + "/fixture")
    page.evaluate("async () => { const {mount} = await import('/settings.js'); window.removeFixture = mount(); }")
    preview = page.get_by_role("region", name="候选窗口预览")
    expect(preview.locator(".cand")).to_have_count(6)
    expect(preview.locator(".candidate")).to_have_css("font-size", "18px")
    page.get_by_label("候选布局", exact=True).select_option("horizontal")
    page.get_by_label("候选字号", exact=True).select_option("20")
    page.get_by_label("每页候选数量", exact=True).select_option("9")
    expect(preview.locator(".cand")).to_have_count(9)
    expect(preview.locator(".wnd-h")).to_have_css("font-size", "20px")
    page.get_by_label("候选窗预编辑", exact=True).select_option("empty")
    expect(preview.locator(".pinyin")).to_have_count(0)
    page.get_by_role("button", name="皮肤", exact=True).click()
    page.get_by_role("switch", name="微信绿", exact=True).click()
    page.get_by_role("button", name="外观", exact=True).click()
    expect(preview.locator(".container")).to_have_css("background-color", "rgb(21, 21, 21)")
    page.get_by_label("候选布局", exact=True).select_option("vertical")
    expect(preview.locator(".wnd-v")).to_have_css("font-size", "20px")
    if args.screenshot:
        page.screenshot(path=args.screenshot)
    page.get_by_role("button", name="重新读取", exact=True).click()
    expect(preview.locator(".cand")).to_have_count(6)
    expect(preview.locator(".candidate")).to_have_css("font-size", "18px")
    expect(preview.locator(".pinyin")).to_have_count(1)
    page.evaluate("window.removeFixture()")
    expect(page.locator("#root")).to_be_empty()
    print({"appearanceDraftPreview": True, "fontSize": True, "skinPalette": True, "reload": True, "cleanup": True})
    browser.close()
