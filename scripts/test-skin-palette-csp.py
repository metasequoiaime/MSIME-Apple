"""Read-only browser regression for the compiled skin-palette.ts module.

Compile that module to a temporary directory, serve it on loopback, then pass
--url, the desktop --csp, and optionally --executable for installed Chromium.
Requires Python Playwright. Does not launch the input method or touch user data.
"""
import argparse
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument("--url", required=True)
parser.add_argument("--csp", required=True)
parser.add_argument("--executable")
args = parser.parse_args()
assert args.url.startswith("http://127.0.0.1:"), "use a loopback fixture server"

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, executable_path=args.executable)
    page = browser.new_page()
    page.route(args.url + "/fixture", lambda route: route.fulfill(
        body='<html><head></head><body><div class="card1"><span class="sample">synthetic</span></div><div class="card2"><span class="sample">synthetic</span></div></body></html>',
        content_type="text/html", headers={"Content-Security-Policy": args.csp}))
    page.goto(args.url + "/fixture")
    result = page.evaluate("""async () => {
      const {installSkinPalette} = await import('/skin-palette.js');
      const first = document.querySelector('.card1 .sample');
      const second = document.querySelector('.card2 .sample');
      const baseline = getComputedStyle(first).color;
      const blocked = document.createElement('style');
      blocked.textContent = '.card1 .sample { color: rgb(1, 2, 3) !important }';
      document.head.append(blocked);
      if (blocked.sheet || getComputedStyle(first).color !== baseline) throw Error('fixture CSP did not block inline style');
      blocked.remove();
      const removeFirst = installSkinPalette(['.card1 .sample { color: rgb(1, 2, 3) !important }']);
      const removeSecond = installSkinPalette(['.card2 .sample { color: rgb(4, 5, 6) !important }']);
      if (getComputedStyle(first).color !== 'rgb(1, 2, 3)' || getComputedStyle(second).color !== 'rgb(4, 5, 6)') throw Error('scoped palette not applied');
      removeFirst();
      if (getComputedStyle(first).color !== baseline || getComputedStyle(second).color !== 'rgb(4, 5, 6)') throw Error('cleanup changed another card');
      const removeLight = installSkinPalette(['.card1 .sample { color: rgb(1, 2, 3) !important }', '.card1 .sample { color: rgb(7, 8, 9) !important }']);
      if (getComputedStyle(first).color !== 'rgb(7, 8, 9)') throw Error('light override lost');
      removeLight(); removeLight(); removeSecond();
      if (document.adoptedStyleSheets.length !== 0 || getComputedStyle(first).color !== baseline) throw Error('stylesheet leak');
      return {inlineBlocked:true, scopedPalette:true, lightOverride:true, cleanup:true};
    }""")
    print(result)
    browser.close()
