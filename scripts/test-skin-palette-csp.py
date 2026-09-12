"""Read-only browser regression for skin-palette/skin-toolbar-css/toolbar-images.

Bundle with node scripts/build-skin-browser.mjs <temporary-directory>, serve it on loopback, then pass
--url, the desktop --csp, and optionally --executable for installed Chromium.
Requires Python Playwright. Does not launch the input method or touch user data.
"""
import argparse
import json
from pathlib import Path
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
    result = page.evaluate(r"""async fontBase64 => {
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
      first.setAttribute('data-root-label', ':root');
      first.classList.add('literal:root');
      const rootSelectors = installToolbarCss('card1', ':r\\6f ot { --root-label: ":root"; } [data-root-label=":root"] { padding-left:7px; } .literal\\:root { border-left:3px solid black; } @media screen { :root { --nested-label: ":root"; } } .sample::before {content:":root";}');
      if (rootSelectors.partial || getComputedStyle(first).getPropertyValue('--root-label').trim() !== '":root"' || getComputedStyle(first).getPropertyValue('--nested-label').trim() !== '":root"') throw Error('root selector mapping changed declaration values or lost conditional inheritance');
      if (getComputedStyle(first).paddingLeft !== '7px' || getComputedStyle(first).borderLeftWidth !== '3px' || getComputedStyle(first, '::before').content !== '":root"') throw Error('root mapping changed quoted attributes, escaped classes or content');
      if (getComputedStyle(second).getPropertyValue('--root-label')) throw Error('root variables escaped scope');
      rootSelectors.remove();
      first.removeAttribute('data-root-label');
      first.classList.remove('literal:root');
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
      const escapedSetRequests = [];
      const escapedSet = await prepareToolbarImages('.sample { --choices: image-set("images/\\61.svg" 1x, url(images/a\\.svg) 2x); background-image: var(--choices); &::before { background-image: -webkit-image-set("images/a\\\n.svg" 1x); } }', async name => { escapedSetRequests.push(name); return imageData; });
      if (escapedSet.partial || escapedSetRequests.join(',') !== 'images/a.svg') throw Error('escaped image-set resolution or dedup failed');
      const escapedSetSheet = installToolbarCss('card1', escapedSet.css);
      if (escapedSetSheet.partial || !getComputedStyle(first).backgroundImage.includes('data:image/svg+xml') || !getComputedStyle(first, '::before').backgroundImage.includes('data:image/svg+xml')) throw Error('escaped image-set did not render');
      if (getComputedStyle(second).backgroundImage !== 'none') throw Error('escaped image-set scope failed');
      escapedSetSheet.remove();
      let rejectedSetReads = 0;
      for (const option of ['"\\2e\\2e/a.svg"', '"\\68 ttps://invalid.example/a.svg"', '"images/a\\"(b).svg"', 'url(images/a\\).svg)']) {
        const rejected = await prepareToolbarImages('.sample { --bad-choice: image-set(' + option + ' 1x); color: rgb(3, 2, 1); }', async () => { rejectedSetReads++; return imageData; });
        if (!rejected.partial || rejected.css.includes('--bad-choice:') || !rejected.css.includes('rgb(3, 2, 1)')) throw Error('unsafe escaped image-set survived or lost other styles');
      }
      if (rejectedSetReads) throw Error('unsafe escaped image-set reached reader');
      const remoteSet = await prepareToolbarImages('.sample { background-image: image-set("https://invalid.example/a.svg" 1x); }', async () => { throw Error('remote image-set must not reach reader'); });
      if (!remoteSet.partial || remoteSet.css.includes('invalid.example')) throw Error('remote image-set retained');
      const directSet = installToolbarCss('card1', '.sample { --remote: image-set("https://invalid.example/a.svg" 1x); background-image: var(--remote); }');
      if (!directSet.partial || getComputedStyle(first).backgroundImage !== 'none') throw Error('unprepared image-set bypassed validation');
      directSet.remove();
      const motionA = installToolbarCss('card1', '@supports (display: block) { @keyframes pulse { from { opacity: .2; } to { opacity: .8; } } } .sample { animation: pulse 1s linear both paused !important; }');
      const motionB = installToolbarCss('card2', '@-webkit-keyframes pulse { from { opacity: .4; } to { opacity: 1; } } .sample { animation: pulse 1s linear both paused; }');
      if (motionA.partial || motionB.partial) throw Error('supported animations reported partial');
      const firstMotion = first.getAnimations()[0], secondMotion = second.getAnimations()[0];
      if (!firstMotion || !secondMotion || firstMotion.animationName === secondMotion.animationName) throw Error('animation names not isolated');
      firstMotion.currentTime = 500; secondMotion.currentTime = 500;
      if (Math.abs(Number(getComputedStyle(first).opacity) - .5) > .01 || Math.abs(Number(getComputedStyle(second).opacity) - .7) > .01) throw Error('keyframe playback or timing lost');
      motionA.remove();
      if (first.getAnimations().length || !second.getAnimations().length) throw Error('animation cleanup affected another card');
      motionB.remove();
      const quotedMotion = installToolbarCss('card1', '@keyframes "skin,pulse" { from { opacity: .2; } to { opacity: .8; } } .sample { animation: "skin,pulse" 1s linear both paused; }');
      if (quotedMotion.partial || first.getAnimations().length !== 1) throw Error('quoted comma animation name lost');
      quotedMotion.remove();
      const escapedMotion = await prepareToolbarImages('@keyframes "skin pulse" { from { opacity: .2; } to { opacity: .8; } } .sample { animation: "skin pulse" 1s linear both paused; }', async () => { throw Error('animation name is not a resource'); });
      const escapedMotionSheet = installToolbarCss('card1', escapedMotion.css);
      if (escapedMotion.partial || escapedMotionSheet.partial || first.getAnimations().length !== 1) throw Error('escaped animation name lost during image preparation');
      escapedMotionSheet.remove();
      const nestedMotion = installToolbarCss('card1', '@keyframes pulse { from { opacity: .2; } to { opacity: .8; } } .sample { @media screen { animation: pulse 1s linear both paused; } }');
      if (nestedMotion.partial || first.getAnimations().length !== 1) throw Error('nested animation declarations lost');
      nestedMotion.remove();
      const orderedMotion = installToolbarCss('card1', '@keyframes pulse { from { opacity: 0; } to { opacity: .2; } } @media screen { @keyframes pulse { from { opacity: .4; } to { opacity: 1; } } } .sample { animation: pulse 1s linear both paused; }');
      if (orderedMotion.partial || first.getAnimations().length !== 1) throw Error('duplicate conditional keyframes lost');
      first.getAnimations()[0].currentTime = 500;
      if (Math.abs(Number(getComputedStyle(first).opacity) - .7) > .01) throw Error('duplicate keyframe definition order changed');
      orderedMotion.remove();
      let frameReads = 0;
      const preparedFrames = await prepareToolbarImages('@keyframes images { from { background-image: url(images/a.svg); opacity: .2; } to { background-image: url(images/a.svg); opacity: .8; } } .sample { animation: images 1s linear both paused; }', async () => { frameReads++; return imageData; });
      const frameSheet = installToolbarCss('card1', preparedFrames.css);
      if (preparedFrames.partial || frameSheet.partial || frameReads !== 1 || !first.getAnimations()[0]?.effect.getKeyframes()[0].backgroundImage.includes('data:image/svg+xml')) throw Error('keyframe image preparation failed');
      frameSheet.remove();
      const unpreparedFrames = installToolbarCss('card1', '@keyframes images { from { background-image: url(https://invalid.example/frame.png); opacity: .2; } to { opacity: .8; } } .sample { animation: images 1s linear both paused; }');
      if (!unpreparedFrames.partial || !first.getAnimations().length || first.getAnimations()[0].effect.getKeyframes().some(frame => frame.backgroundImage?.includes('invalid.example'))) throw Error('keyframe filtering retained unsafe resource or dropped valid motion');
      unpreparedFrames.remove();
      const variableMotion = installToolbarCss('card1', '@keyframes pulse { from {opacity:0} to {opacity:1} } .sample { --motion: pulse 1s; animation: var(--motion); }');
      if (variableMotion.partial || first.getAnimations().length !== 1 || getComputedStyle(first).getPropertyValue('--motion').trim() !== 'pulse 1s') throw Error('variable animation failed or changed original variable');
      variableMotion.remove();
      const variableNames = installToolbarCss('card1', '@keyframes pulse { from {opacity:0} to {opacity:1} } :root { --motion: pulse; } .sample { animation-name: var(--motion); animation-duration: 1s; animation-timing-function: linear; animation-fill-mode: both; animation-play-state: paused; }');
      if (variableNames.partial || first.getAnimations().length !== 1) throw Error('inherited animation-name variable failed');
      first.getAnimations()[0].currentTime = 500;
      if (Math.abs(Number(getComputedStyle(first).opacity) - .5) > .01) throw Error('variable name changed timing');
      variableNames.remove();
      const fallbackMotion = installToolbarCss('card1', '@keyframes pulse { from {opacity:0} to {opacity:1} } .sample { --a: var(--b); --b: var(--a); animation: var(--a, var(--missing, pulse 1s linear both paused)); }');
      if (fallbackMotion.partial || first.getAnimations().length !== 1) throw Error('cyclic variable fallback failed');
      fallbackMotion.remove();
      const conditionalMotion = installToolbarCss('card1', '@keyframes pulse { from {opacity:0} to {opacity:1} } .sample { --motion: none; @media screen { --motion: pulse 2s linear both paused !important; } animation: var(--motion); }');
      if (conditionalMotion.partial || first.getAnimations().length !== 1 || getComputedStyle(first).animationDuration !== '2s') throw Error('conditional variable cascade failed');
      conditionalMotion.remove();
      const sharedVariableA = installToolbarCss('card1', '@keyframes pulse { from {opacity:0} to {opacity:1} } .sample { --motion: pulse 1s linear both paused; animation: var(--motion); }');
      const sharedVariableB = installToolbarCss('card2', '@keyframes pulse { from {opacity:.4} to {opacity:1} } .sample { --motion: pulse 1s linear both paused; animation: var(--motion); }');
      if (sharedVariableA.partial || sharedVariableB.partial || first.getAnimations()[0]?.animationName === second.getAnimations()[0]?.animationName) throw Error('variable animation crossed card boundary');
      sharedVariableA.remove();
      if (first.getAnimations().length || second.getAnimations().length !== 1) throw Error('variable cleanup affected another card');
      sharedVariableB.remove();
      const preparedVariable = await prepareToolbarImages('@keyframes pulse {from{opacity:0}to{opacity:1}} .sample {--motion:pulse 1s linear both paused; animation:var(--motion)}', async () => { throw Error('motion is not a resource'); });
      const preparedVariableSheet = installToolbarCss('card1', preparedVariable.css);
      if (preparedVariable.partial || preparedVariableSheet.partial || first.getAnimations().length !== 1) throw Error('image preparation lost variable shorthand');
      preparedVariableSheet.remove();
      const overrideCss = '@keyframes pulse { from {opacity:0} to {opacity:1} } .sample { --motion: pulse 1s linear both; animation: var(--motion); animation-duration: 2s; animation-play-state: paused; }';
      for (const source of [overrideCss, (await prepareToolbarImages(overrideCss, async () => { throw Error('must not read'); })).css]) {
        const overrides = installToolbarCss('card1', source);
        if (overrides.partial || first.getAnimations().length !== 1 || getComputedStyle(first).animationDuration !== '2s' || getComputedStyle(first).animationPlayState !== 'paused') throw Error('pending shorthand longhand overrides lost');
        first.getAnimations()[0].currentTime = 1000;
        if (Math.abs(Number(getComputedStyle(first).opacity) - .5) > .01) throw Error('overridden animation timing incorrect');
        overrides.remove();
      }
      const importantOverride = installToolbarCss('card1', '@keyframes pulse {from{opacity:0}to{opacity:1}} .sample {--motion:pulse 1s linear both paused; animation-duration:3s!important; animation:var(--motion); animation-duration:2s; content:"animation:var(--untouched);";}');
      if (importantOverride.partial || getComputedStyle(first).animationDuration !== '3s' || !getComputedStyle(first).content.includes('--untouched')) throw Error('shorthand rewrite changed priority or quoted content');
      importantOverride.remove();
      const lateShorthand = installToolbarCss('card1', '@keyframes pulse {from{opacity:0}to{opacity:1}} .sample {--motion:pulse 1s linear both paused; animation-duration:2s; animation:var(--motion); }');
      if (lateShorthand.partial || getComputedStyle(first).animationDuration !== '1s') throw Error('later shorthand failed to reset prior longhand');
      lateShorthand.remove();
      for (const [definition, reference, functionName = 'var'] of [['--动画', '--动画'], ['--\\61', '--a'], ['--a', '--\\61'], ['--a\\,b', '--a\\,b'], ['--upper', '--upper', 'VAR']]) {
        const namedCss = '@keyframes pulse {from{opacity:0}to{opacity:1}} .sample {' + definition + ':pulse 1s linear both paused; animation:' + functionName + '(' + reference + '); animation-duration:2s;}';
        const preparedNamed = await prepareToolbarImages(namedCss, async () => { throw Error('variable name is not a resource'); });
        const namedSheet = installToolbarCss('card1', preparedNamed.css);
        if (preparedNamed.partial || namedSheet.partial || first.getAnimations().length !== 1 || getComputedStyle(first).animationDuration !== '2s') throw Error('Unicode/escaped animation variable failed: ' + definition + '/' + reference);
        first.getAnimations()[0].currentTime = 1000;
        if (Math.abs(Number(getComputedStyle(first).opacity) - .5) > .01) throw Error('named variable timing lost');
        namedSheet.remove();
      }
      const escapedNameOnly = await prepareToolbarImages('@keyframes pulse {from{opacity:0}to{opacity:1}} .sample {--动画:pulse;animation-name:var(--\\52a8\\753b);animation-duration:1s;animation-play-state:paused;}', async () => { throw Error('must not read'); });
      const escapedNameSheet = installToolbarCss('card1', escapedNameOnly.css);
      if (escapedNameOnly.partial || escapedNameSheet.partial || first.getAnimations().length !== 1) throw Error('escaped animation-name variable removed by resource preparation');
      escapedNameSheet.remove();
      let escapedFallbackReads = 0;
      const unsafeVariableFallback = await prepareToolbarImages('.sample { background-image:var(--\\61,url(https://invalid.example/a.png)); color:rgb(3,2,1); }', async () => { escapedFallbackReads++; return imageData; });
      if (!unsafeVariableFallback.partial || escapedFallbackReads || unsafeVariableFallback.css.includes('invalid.example')) throw Error('escaped variable concealed unsafe fallback');
      if (document.adoptedStyleSheets.length) throw Error('image stylesheet leaked');
      const {prepareToolbarFonts} = await import('/toolbar-fonts.js');
      const fontBytes = Uint8Array.from(atob(fontBase64), character => character.charCodeAt(0)).buffer;
      const initialFonts = document.fonts.size;
      const fontRequests = [];
      const fontCss = '@font-face {font-family:"Synthetic Font";src:url(fonts/test.ttf) format("truetype");font-weight:400;} .sample {--skin-family:"Synthetic Font",serif; font-family:var(--skin-family);font-size:20px;}';
      const fontA = await prepareToolbarFonts(fontCss, async name => { fontRequests.push(name); return fontBytes; });
      const fontB = await prepareToolbarFonts(fontCss, async () => fontBytes);
      if (fontA.partial || fontB.partial || document.fonts.size !== initialFonts || fontRequests.join(',') !== 'fonts/test.ttf') throw Error('font preparation failed or installed too early');
      const removeFontA = fontA.install(), removeFontB = fontB.install();
      const fontStyleA = installToolbarCss('card1', fontA.css), fontStyleB = installToolbarCss('card2', fontB.css);
      if (fontStyleA.partial || fontStyleB.partial || document.fonts.size !== initialFonts + 2 || getComputedStyle(first).fontFamily === getComputedStyle(second).fontFamily) throw Error('font names not isolated');
      const canvas = document.createElement('canvas'), context = canvas.getContext('2d');
      context.font = '20px ' + getComputedStyle(first).fontFamily;
      if (Math.abs(context.measureText('A').width - 20) > .01) throw Error('binary font did not render under CSP');
      fontStyleA.remove(); removeFontA();
      if (document.fonts.size !== initialFonts + 1) throw Error('font cleanup affected another card');
      fontStyleB.remove(); removeFontB();
      if (document.fonts.size !== initialFonts) throw Error('font leaked');
      let unsafeFontReads = 0;
      const unsafeFont = await prepareToolbarFonts('@font-face{font-family:Bad;src:url(https://invalid.example/font.woff2)}.sample{font-family:Bad,serif}', async () => { unsafeFontReads++; return fontBytes; });
      if (!unsafeFont.partial || unsafeFontReads || unsafeFont.css.includes('invalid.example')) throw Error('remote font reached reader or survived');
      const badFont = await prepareToolbarFonts('@font-face{font-family:Bad;src:url(fonts/bad.ttf)}.sample{color:red;font-family:Bad,serif}', async () => new Uint8Array([0, 1]).buffer);
      if (!badFont.partial || !badFont.css.includes('red')) throw Error('failed font decode lost valid styles');
      let cappedFontReads = 0;
      const cappedFonts = await prepareToolbarFonts(Array.from({length:9}, (_, index) => '@font-face{font-family:Cap' + index + ';src:url(fonts/test.ttf)}').join(''), async () => { cappedFontReads++; return fontBytes; });
      const removeCapped = cappedFonts.install();
      if (!cappedFonts.partial || cappedFontReads !== 1 || document.fonts.size !== initialFonts + 8) throw Error('font face limit or shared read failed');
      removeCapped();
      if (document.fonts.size !== initialFonts) throw Error('capped fonts leaked');
      return {inlineBlocked:true, scopedPalette:true, lightOverride:true, cleanup:true, toolbarScope:true, toolbarConditions:true, nestedOrder:true, nestedPseudo:true, nestedFiltering:true, cssImages:true, imageDedup:true, imageDecode:true, escapedImages:true, escapedContent:true, escapedTraversalBlocked:true, imageSet:true, imageSetVariables:true, imageSetRemoteBlocked:true, escapedImageSets:true, unsafeEscapedSetsBlocked:true, isolatedAnimations:true, animationPlayback:true, animationNames:true, animationImages:true, animationCleanup:true, animationVariables:true, animationVariableFallback:true, animationVariableIsolation:true, animationLonghandOverrides:true, animationPriority:true, fontRendering:true, fontIsolation:true, fontCleanup:true, fontLimits:true};
    }""", json.loads(Path(__file__).with_name("skin-font-fixture.json").read_text())["base64"])
    print(result)
    browser.close()
