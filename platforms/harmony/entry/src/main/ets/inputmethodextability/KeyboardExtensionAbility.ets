import InputMethodExtensionAbility from '@ohos.InputMethodExtensionAbility';
import inputMethodEngine from '@ohos.inputMethodEngine';
import Want from '@ohos.app.ability.Want';
import { KeyboardSession, KeyboardPreferences } from '../keyboard/KeyboardSession';
import { KeyboardLog, describeError } from '../keyboard/KeyboardLog';
import fs from '@ohos.file.fs';
import display from '@ohos.display';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { KeyboardMetrics } from '../keyboard/KeyboardMetrics';
import { KeyboardFormFactor } from '../keyboard/KeyboardFormFactor';
import { HardwareKeyRouter, HardwareKey, HardwareKeyAction, HardwareKeyDecision }
  from '../keyboard/HardwareKeyRouter';
import { InputModeRouting, ModeGesture, ModeKey } from '../keyboard/InputModeRouting';
import { FloatingToolbarLayout } from '../keyboard/FloatingToolbarLayout';
import { DesktopSurface } from '../keyboard/DesktopSurface';
import type { KeyEvent as InputKeyEvent } from '@ohos.multimodalInput.keyEvent';
import { Action as KeyAction } from '@ohos.multimodalInput.keyEvent';

// The badge's own geometry, from platforms/macos/src/InputModeHUDPanel.mm: a capsule that carries
// the logo and one character side by side, shown long enough to read and gone before the next word.
const HUD_WIDTH_VP: number = 100;
const HUD_HEIGHT_VP: number = 56;
const HUD_SCREEN_MARGIN_VP: number = 8;
const HUD_CARET_GAP_VP: number = 10;
const HUD_VISIBLE_MS: number = 780;
const BUNDLE_NAME: string = 'app.msime.client';
const TOOLBAR_MARGIN_VP: number = 20;
// Wide enough for the key rows to keep the proportions they have on a phone, rather than stretching
// a ten-key row across a desktop.
const DESKTOP_SURFACE_WIDTH_VP: number = 520;

KeyboardLog.error('module loaded');
const engine: inputMethodEngine.InputMethodAbility = inputMethodEngine.getInputMethodAbility();

/**
 * The HarmonyOS input method host. The system starts it when an editor takes focus, so the panel is
 * created here rather than by opening a window of our own.
 *
 * The same host serves every form factor rather than being duplicated per device. What it creates
 * differs: a phone gets a soft keyboard fixed to the bottom of the screen, a 2in1 gets a candidate
 * window, because there the keys are already under the user's hands.
 */
export default class KeyboardExtensionAbility extends InputMethodExtensionAbility {
  private panel: inputMethodEngine.Panel | undefined = undefined;
  // The editor that already has focus when the panel finishes being created. The system sends
  // inputStart as soon as the ability is up, which is well before createPanel and setUiContent have
  // resolved, so an editor that arrives in that window is remembered and served once there is a panel
  // to show. Subscribing after the awaits instead would simply drop it, and the keyboard would sit
  // there visible but inert until the user focused something else.
  private pending: inputMethodEngine.InputClient | undefined = undefined;
  // Where the caret last was, in px, so the candidate window can be put under it. Kept here because
  // the panel is here: the view has no handle on the window it is drawn into.
  private caret: [number, number, number] = [0, 0, 0];
  private density: number = 1;
  // The badge that says which mode a switch landed in. Its own window, because it has to be able to
  // appear when the candidate window is not up: a mode is switched between words, not during one.
  private hud: inputMethodEngine.Panel | undefined = undefined;
  private hudTimer: number = -1;
  private readonly modeKeys: InputModeRouting = new InputModeRouting();
  // The bar that says what mode the keyboard is in. Another window of its own, because it outlives
  // every composition and every editor: it is on screen whenever the keyboard is running at all.
  private toolbar: inputMethodEngine.Panel | undefined = undefined;
  private screenWidth: number = 0;
  private screenHeight: number = 0;

  /** The editor moved its caret; the candidate window goes with it if it is up. */
  private readonly caretMoved: (x: number, y: number, height: number) => void =
    (x: number, y: number, height: number): void => {
      this.caret = [x, y, height];
      // When follow-cursor is disabled, the first composition position is the anchor for the
      // whole candidate window lifetime. Keep recording the latest caret while idle so the next
      // composition still starts beside the newly focused text.
      if (KeyboardSession.shared.composing()
        && KeyboardSession.shared.preferences().candidateFollowCursor) {
        this.placeCandidateWindow();
      }
    };

  /**
   * As wide as the buttons the user left on, scaled by what they asked for.
   *
   * The width is computed from the same layout the page draws with, so a hidden button narrows the
   * bar rather than leaving a gap where it was.
   */
  private async resizeToolbar(density: number): Promise<void> {
    if (this.toolbar === undefined) {
      return;
    }
    const session: KeyboardSession = KeyboardSession.shared;
    const count: number = FloatingToolbarLayout.buttons(session.toolbarComponents()).length;
    const scale: number = session.toolbarScale();
    await this.toolbar.resize(
      Math.round(FloatingToolbarLayout.widthVp(count) * scale * density),
      Math.round(FloatingToolbarLayout.heightVp() * scale * density));
  }

  /**
   * Open, close or swap the surface the candidate window is carrying.
   *
   * The same window, because there is one: a keyboard and a grid of emoji are both too big to sit
   * where the candidates do, so it is resized and moved rather than duplicated. Closing puts it back
   * to the size a candidate list needs, so the next composition does not open a keyboard-sized hole.
   */
  private showDesktopSurface(surface: DesktopSurface): void {
    const panel: inputMethodEngine.Panel | undefined = this.panel;
    if (panel === undefined) {
      return;
    }
    if (surface === DesktopSurface.NONE) {
      this.resizeCandidateWindow(surface).then((): void => {
        if (!KeyboardSession.shared.composing()) {
          panel.hide();
        }
      }).catch((error: Object): void => {
        KeyboardLog.error(`surface would not close: ${describeError(error)}`);
      });
      return;
    }
    // Shown before it is sized, not after: a panel that is not on screen takes a resize without
    // complaint and then appears at whatever size it had before, which on screen is a candidate
    // strip where a keyboard was asked for.
    panel.show().then((): Promise<void> => this.resizeCandidateWindow(surface)).then((): void => {
      this.centreCandidateWindow(surface);
    }).catch((error: Object): void => {
      KeyboardLog.error(`surface would not open: ${describeError(error)}`);
    });
  }

  /** A candidate list is one strip; the other two are as tall as the keyboard they stand in for. */
  private async resizeCandidateWindow(surface: DesktopSurface): Promise<void> {
    if (this.panel === undefined) {
      return;
    }
    const settings: KeyboardPreferences = KeyboardSession.shared.preferences();
    const tall: boolean = surface !== DesktopSurface.NONE;
    const heightVp: number = tall
      ? KeyboardMetrics.totalHeightVp(settings.rowSpacingTenths, settings.heightAdjustment)
      : KeyboardMetrics.candidateHeightVp();
    const widthVp: number = tall
      ? DESKTOP_SURFACE_WIDTH_VP : KeyboardMetrics.CANDIDATE_WINDOW_WIDTH_VP;
    await this.panel.resize(Math.round(widthVp * this.density),
      Math.round(heightVp * this.density));
  }

  /**
   * A surface that was asked for goes where it can be seen rather than where the caret is.
   *
   * The caret is the right place for candidates, which belong to the word being typed. A keyboard or
   * a grid of emoji belongs to the session, so it sits at the bottom of the screen the way one does
   * on a phone, out of the way of the text above it.
   */
  private centreCandidateWindow(surface: DesktopSurface): void {
    if (this.panel === undefined || this.screenWidth === 0) {
      return;
    }
    const settings: KeyboardPreferences = KeyboardSession.shared.preferences();
    const height: number = KeyboardMetrics.totalHeightVp(
      settings.rowSpacingTenths, settings.heightAdjustment) * this.density;
    const width: number = DESKTOP_SURFACE_WIDTH_VP * this.density;
    this.panel.moveTo(Math.round((this.screenWidth - width) / 2),
      Math.round(this.screenHeight - height - TOOLBAR_MARGIN_VP * this.density))
      .catch((error: Object): void => {
        KeyboardLog.error(`surface would not move: ${describeError(error)}`);
      });
  }

  /** The gear opens the application, which is where everything that is not a keystroke lives. */
  private openSettings(): void {
    // Named rather than read off the context: an extension context carries no ability info, and the
    // bundle is this one by construction — the panel and the settings window are the same app.
    this.context.startAbility({
      bundleName: BUNDLE_NAME, abilityName: 'EntryAbility'
    }).catch((error: Object): void => {
      KeyboardLog.error(`settings would not open: ${describeError(error)}`);
    });
  }

  /**
   * Flip the composing language and say so.
   *
   * The badge is the only feedback there is on a machine with no keyboard on screen to change shape:
   * nothing else on a desktop tells the user which mode the next letter will be in.
   */
  private switchInputMode(): void {
    this.modeKeys.disarm();
    const english: boolean = KeyboardSession.shared.toggleLanguage();
    KeyboardLog.info(`input mode switched: english=${english}`);
    KeyboardSession.shared.refreshToolbar();
    this.showModeBadge(english);
  }

  /**
   * Show the badge, then take it away again.
   *
   * Long enough to be read at a glance, short enough that it is gone before the next word is typed.
   * A switch arriving while one is still up restarts the wait rather than stacking a second timer.
   */
  private showModeBadge(english: boolean): void {
    if (this.hud === undefined) {
      return;
    }
    const panel: inputMethodEngine.Panel = this.hud;
    KeyboardSession.shared.setModeBadge(english);
    this.placeModeBadge();
    panel.show().catch((error: Object): void => {
      KeyboardLog.error(`mode badge would not show: ${describeError(error)}`);
    });
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout((): void => {
      this.hudTimer = -1;
      panel.hide().catch((error: Object): void => {
        KeyboardLog.error(`mode badge would not hide: ${describeError(error)}`);
      });
    }, HUD_VISIBLE_MS);
  }

  /** Under the caret, clamped inside the screen; centred low when the editor reports no caret. */
  private placeModeBadge(): void {
    if (this.hud === undefined) {
      return;
    }
    const width: number = HUD_WIDTH_VP * this.density;
    const height: number = HUD_HEIGHT_VP * this.density;
    const margin: number = HUD_SCREEN_MARGIN_VP * this.density;
    let x: number = this.caret[2] > 0
      ? this.caret[0] + this.caret[2] / 2 - width / 2
      : this.screenWidth / 2 - width / 2;
    let y: number = this.caret[2] > 0
      ? this.caret[1] + this.caret[2] + HUD_CARET_GAP_VP * this.density
      : this.screenHeight * 2 / 3;
    x = Math.min(Math.max(margin, x), Math.max(margin, this.screenWidth - margin - width));
    y = Math.min(Math.max(margin, y), Math.max(margin, this.screenHeight - margin - height));
    this.hud.moveTo(Math.round(x), Math.round(y)).catch((error: Object): void => {
      KeyboardLog.error(`mode badge would not move: ${describeError(error)}`);
    });
  }

  /**
   * Put the candidate window just below the caret, kept inside the screen.
   *
   * Below by default, because that is where the eye goes next; above when there is no room beneath,
   * so the window never hangs off the bottom edge. The same clamp on the other axis keeps a caret
   * near the right edge from pushing the window off the side.
   */
  private placeCandidateWindow(): void {
    if (this.panel === undefined) {
      return;
    }
    const width: number = KeyboardMetrics.CANDIDATE_WINDOW_WIDTH_VP * this.density;
    const height: number = KeyboardMetrics.candidateHeightVp() * this.density;
    const gap: number = KeyboardMetrics.CANDIDATE_WINDOW_GAP_VP * this.density;
    // A caret of no height is one that was never reported: a web view mid-layout, a client that
    // answers with zeroes, or simply an editor that has not sent one yet. Believing it puts the
    // window in the top-left corner of the screen, which is where this went. Low and centred is
    // where a desktop input method puts a candidate list it cannot place precisely.
    if (this.caret[2] <= 0) {
      this.panel.moveTo(Math.round(Math.max(0, (this.screenWidth - width) / 2)),
        Math.round(Math.max(0, this.screenHeight * 2 / 3)))
        .catch((error: Object): void => {
          KeyboardLog.error(`candidate window would not move: ${describeError(error)}`);
        });
      return;
    }
    let x: number = this.caret[0];
    if (this.screenWidth > 0 && x + width > this.screenWidth) {
      x = this.screenWidth - width;
    }
    let y: number = this.caret[1] + this.caret[2] + gap;
    if (this.screenHeight > 0 && y + height > this.screenHeight) {
      y = this.caret[1] - height - gap;
    }
    this.panel.moveTo(Math.round(Math.max(0, x)), Math.round(Math.max(0, y)))
      .catch((error: Object): void => {
        KeyboardLog.error(`candidate window would not move: ${describeError(error)}`);
      });
  }

  // off('inputStop') requires the same callback reference that on() received, unlike off('inputStart')
  // where it is optional. Holding both as fields keeps unsubscribing honest.
  private readonly started: (kbController: inputMethodEngine.KeyboardController,
                             inputClient: inputMethodEngine.InputClient) => void =
    (kbController: inputMethodEngine.KeyboardController,
     inputClient: inputMethodEngine.InputClient): void => {
      if (this.panel === undefined) {
        this.pending = inputClient;
        return;
      }
      // A caret belongs to the editor that reported it. Carrying one across a focus change puts the
      // next composition beside the last editor's text, which is worse than not knowing at all.
      this.caret = [0, 0, 0];
      KeyboardSession.shared.attach(inputClient);
      // A keyboard belongs on screen the moment an editor takes focus; a candidate window has
      // nothing to offer until something is being spelled, and waits for onComposition to say so.
      if (!KeyboardFormFactor.isDesktop()) {
        this.panel.show();
      }
    };

  private readonly stopped: () => void = (): void => {
    KeyboardSession.shared.detach();
    if (this.panel !== undefined) {
      this.panel.hide();
    }
  };

  /**
   * A key from a real keyboard, on a machine that has one.
   *
   * Returning false hands the key to the application untouched, which is what happens to everything
   * the router does not claim. Only key-down is acted on: a key that was claimed going down must be
   * claimed coming up too, or the application sees half of it.
   */
  private readonly typed: (event: InputKeyEvent) => boolean = (event: InputKeyEvent): boolean => {
    const key: HardwareKey = {
      keyCode: event.key.code, unicodeChar: event.unicodeChar, ctrlKey: event.ctrlKey,
      altKey: event.altKey, logoKey: event.logoKey, shiftKey: event.shiftKey
    };
    const session: KeyboardSession = KeyboardSession.shared;
    const mode: ModeKey = {
      keyCode: event.key.code, down: event.action === KeyAction.DOWN, shiftKey: event.shiftKey,
      ctrlKey: event.ctrlKey, altKey: event.altKey, logoKey: event.logoKey,
      timestamp: Date.now()
    };
    // Switching mode is the one thing worth claiming in an editor this keyboard will not compose
    // for: the mode outlives the field, and a password box is exactly where one notices being in the
    // wrong one. Checked before anything else, so a chord meant for the mode never reaches the
    // Engine as the letter it is built on.
    const gesture: ModeGesture = this.modeKeys.accept(mode);
    if (gesture === ModeGesture.SWITCH_LANGUAGE) {
      this.switchInputMode();
      return true;
    }
    if (gesture === ModeGesture.TOGGLE_CHARACTER_SET) {
      session.toggleCharacterWidth();
      return true;
    }
    if (!session.composes()) {
      return false;
    }
    const decision: HardwareKeyDecision =
      HardwareKeyRouter.route(key, session.composing(), !session.isEnglish());
    if (decision.action === HardwareKeyAction.RELEASE) {
      return false;
    }
    if (event.action !== KeyAction.DOWN) {
      return true;
    }
    switch (decision.action) {
      case HardwareKeyAction.COMPOSE:
        session.press(decision.character, key.shiftKey);
        break;
      case HardwareKeyAction.BACKSPACE:
        session.backspace();
        break;
      case HardwareKeyAction.CANCEL:
        session.cancel();
        break;
      case HardwareKeyAction.COMMIT:
        session.commitHighlighted();
        break;
      case HardwareKeyAction.COMMIT_RAW:
        session.commitRaw();
        break;
      case HardwareKeyAction.SELECT:
        session.choose(decision.index);
        break;
      default:
        return false;
    }
    return true;
  };

  /**
   * Copies the packaged dictionary into the sandbox once, and only once.
   *
   * stage-resources.sh puts the pinned release under resfile/engine, which OpenHarmony extracts to
   * resourceDir at install time, and reading those files with @ohos.file.fs works. SQLite does not:
   * opening a database on that read-only bundle mount fails even for a read-only connection, because
   * the mount does not carry the advisory locks SQLite takes, and the Engine reports it as "Unable to
   * copy runtime dictionary". So the databases are copied to filesDir, where SQLite is on ordinary
   * storage, and the Engine derives its generation from there.
   *
   * The marker sits beside the directory rather than inside it: prepare_host verifies the resource
   * directory against the pinned lock and rejects any file the lock does not name.
   */
  private stageResources(packaged: string, destination: string, marker: string): void {
    if (fs.accessSync(marker)) {
      return;
    }
    // A partial copy left by a kill mid-staging must not be mistaken for a complete one; the marker
    // is written last, so anything already there is suspect and goes.
    if (fs.accessSync(destination)) {
      fs.rmdirSync(destination);
    }
    fs.mkdirSync(destination, true);
    for (const name of fs.listFileSync(packaged)) {
      fs.copyFileSync(`${packaged}/${name}`, `${destination}/${name}`);
    }
    fs.writeSync(fs.openSync(marker, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY).fd, 'ready');
    KeyboardLog.info(`staged ${destination}`);
  }

  async onCreate(want: Want): Promise<void> {
    const files: string = this.context.filesDir;
    const resources: string = `${files}/engine`;
    const state: string = `${files}/state`;
    if (!fs.accessSync(state)) {
      fs.mkdirSync(state, true);
    }
    try {
      this.stageResources(`${this.context.resourceDir}/engine`, resources, `${files}/engine.ready`);
    } catch (error) {
      KeyboardLog.error(`staging failed: ${describeError(error)}`);
      return;
    }
    // The extension context knows the system colour mode; the view has no context of its own to ask.
    const systemDark: boolean =
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const started: boolean = KeyboardSession.shared.start(resources, state, systemDark);
    if (!started) {
      // Without a session there is nothing to show. Leaving the panel uncreated keeps the framework
      // from presenting an inert keyboard.
      KeyboardLog.error('onCreate: no session, panel not created');
      return;
    }
    engine.on('inputStart', this.started);
    engine.on('inputStop', this.stopped);
    if (KeyboardFormFactor.isDesktop()) {
      // Where the keys are the machine's, this is the only way anything reaches the Engine at all:
      // nothing is ever tapped on a panel that draws no keys.
      inputMethodEngine.getKeyboardDelegate().on('keyEvent', this.typed);
      // Which gestures are bound is the document's business, so the keyboard and the settings page
      // cannot disagree about what a key does.
      this.modeKeys.use(KeyboardSession.shared.modeBindings());
      // A candidate window belongs beside the text it is offering candidates for, not at a fixed
      // place on the screen, so it follows the caret the editor reports.
      inputMethodEngine.getKeyboardDelegate().on('cursorContextChange', this.caretMoved);
    }
    // A machine with its own keys gets a candidate window rather than a keyboard. The framework does
    // not show or hide a FLAG_CANDIDATE panel for you, which costs nothing here: this host has always
    // driven show and hide itself from inputStart and inputStop rather than leaving it to the
    // framework. The flag is chosen at creation instead of switched afterwards with changeFlag, which
    // requires hiding the panel first and would only be worth that if a device could change what it
    // is while running.
    const desktop: boolean = KeyboardFormFactor.isDesktop();
    const info: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: desktop ? inputMethodEngine.PanelFlag.FLAG_CANDIDATE
        : inputMethodEngine.PanelFlag.FLG_FIXED
    };
    try {
      this.panel = await engine.createPanel(this.context, info);
      await this.panel.setUiContent('keyboard/KeyboardView');
      // A panel has no size until it is given one, and a zero-height panel never appears. The height
      // is the candidate row plus four key rows, or the strip alone where the keys are not drawn; the
      // width is the display width, which the panel reports through its own window rather than being
      // assumed here.
      // vp2px is a UI-context global and an extension ability has no UI context here, so the
      // conversion is done from the display's own density rather than borrowed from the environment.
      const screen: display.Display = display.getDefaultDisplaySync();
      // The same numbers the view lays itself out with; a panel that disagrees clips its bottom row.
      const settings: KeyboardPreferences = KeyboardSession.shared.preferences();
      const heightVp: number = desktop ? KeyboardMetrics.candidateHeightVp()
        : KeyboardMetrics.totalHeightVp(settings.rowSpacingTenths, settings.heightAdjustment);
      // A soft keyboard is as wide as the screen because it has to be; a candidate window is as wide
      // as its content, and covering the width of a desktop with one would hide the very text the
      // candidates are for.
      const widthPx: number = desktop
        ? Math.round(KeyboardMetrics.CANDIDATE_WINDOW_WIDTH_VP * screen.densityPixels)
        : screen.width;
      this.density = screen.densityPixels;
      this.screenWidth = screen.width;
      this.screenHeight = screen.height;
      await this.panel.resize(widthPx, Math.round(heightVp * screen.densityPixels));
      // The view asks; only the ability holds the panel.
      const panel: inputMethodEngine.Panel = this.panel;
      KeyboardSession.shared.onDismiss = (): void => {
        panel.hide();
      };
      if (desktop) {
        KeyboardSession.shared.onComposition = (active: boolean): void => {
          // A surface the toolbar opened stays open across a composition; it was asked for, and a
          // window that shut itself the moment a word was typed would be useless for picking an
          // emoji to put in that word.
          if (KeyboardSession.shared.openSurface() !== DesktopSurface.NONE) {
            return;
          }
          if (active) {
            this.resizeCandidateWindow(DesktopSurface.NONE);
            this.placeCandidateWindow();
            panel.show();
          } else {
            panel.hide();
          }
        };
        KeyboardSession.shared.onSurfaceRequested = (surface: DesktopSurface): void => {
          this.showDesktopSurface(surface);
        };
      }
      if (desktop && KeyboardSession.shared.toolbarEnabled()) {
        try {
          this.toolbar = await engine.createPanel(this.context, {
            type: inputMethodEngine.PanelType.STATUS_BAR
          });
          await this.toolbar.setUiContent('keyboard/FloatingToolbar');
          KeyboardSession.shared.onToolbarSettings = (): void => {
            this.openSettings();
          };
          await this.resizeToolbar(screen.densityPixels);
          KeyboardSession.shared.refreshToolbar();
          // Lower right by default, clear of the dock, where a status bar is looked for and where it
          // is least likely to sit on top of what is being written. macOS picks the same corner.
          const width: number = FloatingToolbarLayout.widthVp(
            FloatingToolbarLayout.buttons(KeyboardSession.shared.toolbarComponents()).length)
            * KeyboardSession.shared.toolbarScale() * screen.densityPixels;
          const height: number = FloatingToolbarLayout.heightVp()
            * KeyboardSession.shared.toolbarScale() * screen.densityPixels;
          const margin: number = TOOLBAR_MARGIN_VP * screen.densityPixels;
          await this.toolbar.moveTo(Math.round(screen.width - width - margin),
            Math.round(screen.height - height - margin * 4));
          await this.toolbar.show();
        } catch (error) {
          KeyboardLog.error(`toolbar unavailable: ${describeError(error)}`);
          this.toolbar = undefined;
        }
      }
      // Measured on a 2in1: the framework grants one STATUS_BAR panel, not two. The toolbar takes it
      // when there is one, and the toolbar is the better readout anyway — it says what mode the
      // keyboard is in all the time rather than for three quarters of a second after it changed. The
      // badge is what a desktop falls back to when the toolbar is turned off, which is exactly when
      // nothing else on screen would say the mode had changed at all.
      if (desktop && this.toolbar === undefined) {
        try {
          this.hud = await engine.createPanel(this.context, {
            type: inputMethodEngine.PanelType.STATUS_BAR
          });
          await this.hud.setUiContent('keyboard/InputModeHud');
          await this.hud.resize(Math.round(HUD_WIDTH_VP * screen.densityPixels),
            Math.round(HUD_HEIGHT_VP * screen.densityPixels));
        } catch (error) {
          // Worth saying but not worth failing over: the keyboard types perfectly well without a
          // badge, and refusing to start because a piece of feedback would not build helps nobody.
          KeyboardLog.error(`mode badge unavailable: ${describeError(error)}`);
          this.hud = undefined;
        }
      }
      KeyboardLog.info(`panel ready: ${KeyboardFormFactor.describe()}, `
        + `${desktop ? 'candidate window' : 'soft keyboard'}`
        + `${this.toolbar !== undefined ? ', with toolbar' : ''}`
        + `${this.hud !== undefined ? ', with mode badge' : ''}`);
      // Serve whatever focused while the panel was still being built.
      if (this.pending !== undefined) {
        KeyboardSession.shared.attach(this.pending);
        this.pending = undefined;
        if (!desktop) {
          this.panel.show();
        }
      }
    } catch (error) {
      // The framework allows exactly one soft keyboard panel. If it refused, the session has nothing
      // to draw into, so tear it back down rather than leaving it attached to no surface.
      KeyboardLog.error(`panel creation failed: ${describeError(error)}`);
      KeyboardSession.shared.stop();
      this.panel = undefined;
      engine.off('inputStart', this.started);
      engine.off('inputStop', this.stopped);
      return;
    }
  }

  onDestroy(): void {
    engine.off('inputStart', this.started);
    engine.off('inputStop', this.stopped);
    if (KeyboardFormFactor.isDesktop()) {
      inputMethodEngine.getKeyboardDelegate().off('keyEvent', this.typed);
      inputMethodEngine.getKeyboardDelegate().off('cursorContextChange', this.caretMoved);
    }
    KeyboardSession.shared.stop();
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    if (this.hud !== undefined) {
      engine.destroyPanel(this.hud);
      this.hud = undefined;
    }
    if (this.toolbar !== undefined) {
      engine.destroyPanel(this.toolbar);
      this.toolbar = undefined;
    }
    if (this.panel !== undefined) {
      engine.destroyPanel(this.panel);
      this.panel = undefined;
    }
  }
}
