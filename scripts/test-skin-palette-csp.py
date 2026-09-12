"""Read-only browser regression for skin-palette/skin-toolbar-css/toolbar-images.

Compile these modules to a temporary directory, serve it on loopback, then pass
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
    result = page.evaluate(r"""async () => {
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
      const {installToolbarCss} = await import('/skin-toolbar-css.js');
      const toolbar = installToolbarCss('card1', ':root { --skin-test: 7; } .sample { color: rgb(9, 8, 7); background-image: url(https://invalid.example/image.png); } @media screen { .sample { border-top: 3px solid rgb(1, 2, 3); } } @supports (display: block) { .sample { padding-left: 4px; } } @keyframes unsafe-global { from { opacity: 0; } to { opacity: 1; } } } body { display:none }');
      if (!toolbar.partial || getComputedStyle(first).color !== 'rgb(9, 8, 7)' || getComputedStyle(second).color !== baseline) throw Error('toolbar scope failed');
      if (getComputedStyle(first).borderTopWidth !== '3px' || getComputedStyle(first).paddingLeft !== '4px') throw Error('conditional toolbar rules lost');
      if (getComputedStyle(document.querySelector('.card1')).getPropertyValue('--skin-test').trim() !== '7') throw Error('root mapping failed');
      if (getComputedStyle(document.body).display === 'none' || getComputedStyle(first).backgroundImage !== 'none') throw Error('toolbar escape or resource rule retained');
      toolbar.remove();
      if (document.adoptedStyleSheets.length || getComputedStyle(first).color !== baseline) throw Error('toolbar cleanup failed');
      const nested = installToolbarCss('card1', '.sample { color: rgb(10, 20, 30); & { color: rgb(30, 40, 50); } color: rgb(50, 60, 70); @media screen { & { border-left: 5px solid black; } } @supports (display: block) { padding-right: 6px; } }');
      if (nested.partial || getComputedStyle(first).color !== 'rgb(50, 60, 70)') throw Error('nested declaration order lost');
      if (getComputedStyle(first).borderLeftWidth !== '5px' || getComputedStyle(first).paddingRight !== '6px') throw Error('nested conditional rules lost');
      if (getComputedStyle(second).color !== baseline) throw Error('nesting escaped scope');
      nested.remove();
      const pseudo = installToolbarCss('card1', '.sample::before { content: "synthetic"; color: rgb(1, 2, 3); @media screen { color: rgb(4, 5, 6); } color: rgb(7, 8, 9); }');
      if (pseudo.partial || getComputedStyle(first, '::before').color !== 'rgb(7, 8, 9)') throw Error('nested pseudo-element declarations lost');
      pseudo.remove();
      const filtered = installToolbarCss('card1', '.sample { color: rgb(10, 20, 30); & { background: url(https://invalid.example/nested.png); } @media screen { background-image: url(https://invalid.example/group.png); } @keyframes unsafe-nested { from { opacity: 0; } to { opacity: 1; } } }');
      if (!filtered.partial || getComputedStyle(first).color !== 'rgb(10, 20, 30)' || getComputedStyle(first).backgroundImage !== 'none') throw Error('nested filtering lost parent or retained resource');
      const serialized = document.adoptedStyleSheets.flatMap(sheet => Array.from(sheet.cssRules).map(rule => rule.cssText)).join('');
      if (serialized.includes('unsafe-nested') || serialized.includes('invalid.example')) throw Error('nested unsupported rules retained');
      filtered.remove();
      if (document.adoptedStyleSheets.length || getComputedStyle(first).color !== baseline) throw Error('nested cleanup failed');
      const {prepareToolbarImages} = await import('/toolbar-images.js');
      const imageData = 'data:image/svg+xml;base64,' + btoa('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><rect width="1" height="1" fill="red"/></svg>');
      const requested = [];
      const prepared = await prepareToolbarImages('.sample { background-image: url(images/a.svg); &::before { content: ""; background-image: url(images/a.svg); } @media screen { border-image-source: url(images/a.svg); } }', async name => { requested.push(name); return imageData; });
      if (prepared.partial || requested.length !== 1 || requested[0] !== 'images/a.svg') throw Error('image resolution/deduplication failed');
      const images = installToolbarCss('card1', prepared.css);
      if (images.partial || !getComputedStyle(first).backgroundImage.includes('data:image/svg+xml;base64,')) throw Error('resolved background missing');
      if (getComputedStyle(second).backgroundImage !== 'none') throw Error('background escaped card');
      const decoded = new Image(); decoded.src = imageData; await decoded.decode();
      if (decoded.naturalWidth !== 1) throw Error('image decoding failed under CSP');
      images.remove();
      const escapeRequests = [];
      const escapedImages = await prepareToolbarImages('.sample { --escaped: url("images/\\61.svg"); background-image: var(--escaped); &::before { content: "\\e101"; } }', async name => { escapeRequests.push(name); return imageData; });
      if (escapedImages.partial || escapeRequests.join(',') !== 'images/a.svg') throw Error('escaped image resolution failed');
      const escapedSheet = installToolbarCss('card1', escapedImages.css);
      if (escapedSheet.partial || !getComputedStyle(first).backgroundImage.includes('data:image/svg+xml') || !getComputedStyle(first, '::before').content.includes('\ue101')) throw Error('escaped URL or content lost');
      if (getComputedStyle(second).backgroundImage !== 'none') throw Error('escaped image scope failed');
      escapedSheet.remove();
      let unsafeReads = 0;
      const escapedTraversal = await prepareToolbarImages('.sample { --unsafe: url("\\2e\\2e/a.svg"); background-image: var(--unsafe); }', async () => { unsafeReads++; return imageData; });
      if (!escapedTraversal.partial || unsafeReads || escapedTraversal.css.includes('--unsafe:')) throw Error('escaped traversal reached reader or survived');
      const failedImages = await prepareToolbarImages('.sample { color: rgb(3, 2, 1); background-image: url(../escape.png); }', async () => { throw Error('must not read'); });
      if (!failedImages.partial || failedImages.css.includes('escape.png') || !failedImages.css.includes('rgb(3, 2, 1)')) throw Error('resource failure lost valid styles');
      let resourceCount = 0;
      const manyImages = await prepareToolbarImages('.sample {' + Array.from({length:33}, (_, index) => '--image-' + index + ':url(images/' + index + '.svg);').join('') + '}', async () => { resourceCount++; return imageData; });
      if (!manyImages.partial || resourceCount !== 32 || manyImages.css.includes('--image-32')) throw Error('resource count cap failed');
      const setRequests = [];
      const preparedSet = await prepareToolbarImages('.sample { --choices: image-set("images/a.svg" 1x, "images/b.svg" 2x type("image/svg+xml")); background-image: var(--choices); &::before { background-image: -webkit-image-set(url(images/a.svg) 1x, url(images/b.svg) 2x); } }', async name => { setRequests.push(name); return imageData; });
      if (preparedSet.partial || setRequests.join(',') !== 'images/a.svg,images/b.svg' || !preparedSet.css.includes('2x')) throw Error('image-set rewrite or deduplication failed');
      const imageSet = installToolbarCss('card1', preparedSet.css);
      if (imageSet.partial || !getComputedStyle(first).backgroundImage.includes('image-set(') || !getComputedStyle(first).backgroundImage.includes('data:image/svg+xml')) throw Error('image-set variable did not render');
      if (getComputedStyle(second).backgroundImage !== 'none') throw Error('image-set scope escape');
      imageSet.remove();
      const remoteSet = await prepareToolbarImages('.sample { background-image: image-set("https://invalid.example/a.svg" 1x); }', async () => { throw Error('remote image-set must not reach reader'); });
      if (!remoteSet.partial || remoteSet.css.includes('invalid.example')) throw Error('remote image-set retained');
      const directSet = installToolbarCss('card1', '.sample { --remote: image-set("https://invalid.example/a.svg" 1x); background-image: var(--remote); }');
      if (!directSet.partial || getComputedStyle(first).backgroundImage !== 'none') throw Error('unprepared image-set bypassed validation');
      directSet.remove();
      if (document.adoptedStyleSheets.length) throw Error('image stylesheet leaked');
      return {inlineBlocked:true, scopedPalette:true, lightOverride:true, cleanup:true, toolbarScope:true, toolbarConditions:true, nestedOrder:true, nestedPseudo:true, nestedFiltering:true, cssImages:true, imageDedup:true, imageDecode:true, escapedImages:true, escapedContent:true, escapedTraversalBlocked:true, imageSet:true, imageSetVariables:true, imageSetRemoteBlocked:true};
    }""")
    print(result)
    browser.close()
