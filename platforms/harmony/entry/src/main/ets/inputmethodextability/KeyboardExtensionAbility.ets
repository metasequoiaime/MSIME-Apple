import InputMethodExtensionAbility from '@ohos.InputMethodExtensionAbility';
import inputMethodEngine from '@ohos.inputMethodEngine';
import Want from '@ohos.app.ability.Want';
import { KeyboardSession, KeyboardPreferences } from '../keyboard/KeyboardSession';
import { KeyboardLog, describeError } from '../keyboard/KeyboardLog';
import fs from '@ohos.file.fs';
import display from '@ohos.display';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { KeyboardMetrics } from '../keyboard/KeyboardMetrics';

KeyboardLog.error('module loaded');
const engine: inputMethodEngine.InputMethodAbility = inputMethodEngine.getInputMethodAbility();

/**
 * The HarmonyOS input method host. The system starts it when an editor takes focus, so the panel is
 * created here rather than by opening a window of our own.
 *
 * A phone keeps the soft keyboard in FLG_FIXED. A 2in1 host switches the same panel to FLAG_CANDIDATE
 * with changeFlag, which is why this host is shared across both form factors instead of duplicated.
 */
export default class KeyboardExtensionAbility extends InputMethodExtensionAbility {
  private panel: inputMethodEngine.Panel | undefined = undefined;
  // The editor that already has focus when the panel finishes being created. The system sends
  // inputStart as soon as the ability is up, which is well before createPanel and setUiContent have
  // resolved, so an editor that arrives in that window is remembered and served once there is a panel
  // to show. Subscribing after the awaits instead would simply drop it, and the keyboard would sit
  // there visible but inert until the user focused something else.
  private pending: inputMethodEngine.InputClient | undefined = undefined;

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
      KeyboardSession.shared.attach(inputClient);
      this.panel.show();
    };

  private readonly stopped: () => void = (): void => {
    KeyboardSession.shared.detach();
    if (this.panel !== undefined) {
      this.panel.hide();
    }
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
    const info: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: inputMethodEngine.PanelFlag.FLG_FIXED
    };
    try {
      this.panel = await engine.createPanel(this.context, info);
      await this.panel.setUiContent('keyboard/KeyboardView');
      // A panel has no size until it is given one, and a zero-height panel never appears. The height
      // is the candidate row plus four key rows; the width is the display width, which the panel
      // reports through its own window rather than being assumed here.
      // vp2px is a UI-context global and an extension ability has no UI context here, so the
      // conversion is done from the display's own density rather than borrowed from the environment.
      const screen: display.Display = display.getDefaultDisplaySync();
      // The same numbers the view lays itself out with; a panel that disagrees clips its bottom row.
      const settings: KeyboardPreferences = KeyboardSession.shared.preferences();
      await this.panel.resize(screen.width, Math.round(
        KeyboardMetrics.totalHeightVp(settings.rowSpacingTenths, settings.heightAdjustment)
        * screen.densityPixels));
      KeyboardLog.info('panel ready');
      // Serve whatever focused while the panel was still being built.
      if (this.pending !== undefined) {
        KeyboardSession.shared.attach(this.pending);
        this.pending = undefined;
        this.panel.show();
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
    KeyboardSession.shared.stop();
    if (this.panel !== undefined) {
      engine.destroyPanel(this.panel);
      this.panel = undefined;
    }
  }
}
