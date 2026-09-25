/**
 * Copying the packaged Engine resources out of the HAP, once per generation.
 *
 * One implementation, used by both the keyboard extension and the settings page. They used to have
 * their own: the extension wiped and re-copied unless a marker existed, the settings page copied
 * over whatever was already there and wrote no marker at all. Two rules for one directory is how the
 * directory came to hold a set that matched neither, which the shared verification then refused.
 */
import fs from '@ohos.file.fs';
import { KeyboardLog, describeError } from './KeyboardLog';
import { StagedArtifact, StagedResourcePolicy } from './StagedResourcePolicy';

export class StagedResources {
  /**
   * Make `destination` hold exactly what `packaged` holds.
   *
   * Returns whether the destination can be trusted afterwards. The destination is emptied first, so
   * an artifact dropped from a newer package does not survive as the extra file that makes the whole
   * directory fail verification, and the marker is written last, so a copy interrupted half way
   * looks unstaged rather than complete.
   */
  static stage(packaged: string, destination: string, marker: string): boolean {
    try {
      if (!fs.accessSync(packaged)) {
        KeyboardLog.error(`no packaged resources at ${packaged}`);
        return false;
      }
      const artifacts: StagedArtifact[] = [];
      for (const name of fs.listFileSync(packaged)) {
        artifacts.push({ name: name, size: fs.statSync(`${packaged}/${name}`).size });
      }
      const token: string = StagedResourcePolicy.generationToken(artifacts);
      if (!StagedResourcePolicy.needsStaging(StagedResources.readMarker(marker), token)) {
        return true;
      }
      if (fs.accessSync(marker)) {
        fs.unlinkSync(marker);
      }
      StagedResources.removeDirectory(destination);
      fs.mkdirSync(destination, true);
      for (const artifact of artifacts) {
        fs.copyFileSync(`${packaged}/${artifact.name}`, `${destination}/${artifact.name}`);
      }
      const handle = fs.openSync(marker,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(handle.fd, token);
      } finally {
        fs.closeSync(handle);
      }
      KeyboardLog.info(`staged ${destination}`);
      return true;
    } catch (error) {
      KeyboardLog.error(`staging failed: ${describeError(error)}`);
      return false;
    }
  }

  /** Removes a staged directory and its marker, for resources the installed package no longer carries. */
  static unstage(destination: string, marker: string): void {
    try {
      if (fs.accessSync(marker)) {
        fs.unlinkSync(marker);
      }
      StagedResources.removeDirectory(destination);
    } catch (error) {
      KeyboardLog.error(`unstaging failed: ${describeError(error)}`);
    }
  }

  private static readMarker(marker: string): string | null {
    try {
      return fs.accessSync(marker) ? fs.readTextSync(marker) : null;
    } catch (error) {
      return null;
    }
  }

  /** Remove a staged tree before replacing it; rmdirSync only accepts empty directories. */
  static removeDirectory(directory: string): void {
    if (!fs.accessSync(directory)) {
      return;
    }
    for (const entry of fs.listFileSync(directory)) {
      const child: string = `${directory}/${entry}`;
      if (fs.statSync(child).isDirectory()) {
        StagedResources.removeDirectory(child);
      } else {
        fs.unlinkSync(child);
      }
    }
    fs.rmdirSync(directory);
  }
}
