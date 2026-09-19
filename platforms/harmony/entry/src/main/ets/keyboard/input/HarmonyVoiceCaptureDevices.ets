/**
 * The system's recording devices, and the one the user chose.
 *
 * Windows and macOS both let the settings page name a microphone and record from it; this is the
 * same surface on HarmonyOS. Enumeration is a plain routing-manager query, so the settings page can
 * run it without a session. Selection is process-wide rather than per stream — the audio framework
 * offers no per-capturer setter — so each recognizer asserts it immediately before creating its
 * capturer rather than once at startup, which is also what makes a device unplugged between two
 * recordings fall back rather than persist.
 *
 * Nothing here fails a recording. A microphone that has gone away, a selection belonging to another
 * platform's backend, or a routing call the device refuses all end at the system default, because a
 * keyboard that will not record is worse than one that records from the wrong microphone and says so
 * in the log.
 */
import audio from '@ohos.multimedia.audio';
import { KeyboardLog, describeError } from '../KeyboardLog';
import { HARMONY_CAPTURE_BACKEND, VoiceCaptureDevice, VoiceCaptureDevicePolicy }
  from './VoiceCaptureDevicePolicy';

export class HarmonyVoiceCaptureDevices {
  /**
   * Every input device the routing manager reports, in the shared settings shape, or null when the
   * query itself failed. The two are different answers — no microphones versus no list — and the
   * picker has a message for each.
   */
  static list(): VoiceCaptureDevice[] | null {
    const devices: VoiceCaptureDevice[] = [];
    try {
      const routing: audio.AudioRoutingManager =
        audio.getAudioManager().getRoutingManager();
      const descriptors: audio.AudioDeviceDescriptors =
        routing.getDevicesSync(audio.DeviceFlag.INPUT_DEVICES_FLAG);
      for (const descriptor of descriptors) {
        const id: string =
          VoiceCaptureDevicePolicy.stableId(descriptor.deviceType, descriptor.address);
        if (id.length === 0) {
          continue;
        }
        devices.push({
          backend: HARMONY_CAPTURE_BACKEND,
          id: id,
          label: VoiceCaptureDevicePolicy.label(descriptor.displayName, descriptor.name,
            descriptor.deviceType)
        });
      }
    } catch (error) {
      KeyboardLog.error(`capture devices unavailable: ${describeError(error)}`);
      return null;
    }
    return devices;
  }

  /**
   * Route recording to the stored choice, if it names a device that is present.
   *
   * Awaited by the caller so the routing call has completed before the capturer is created; a
   * refusal is logged and left at the system default.
   */
  static async select(backend: string, deviceId: string): Promise<void> {
    if (!VoiceCaptureDevicePolicy.selects(backend)) {
      return;
    }
    const wanted: string = deviceId.trim();
    if (wanted.length === 0) {
      return;
    }
    try {
      const manager: audio.AudioManager = audio.getAudioManager();
      const descriptors: audio.AudioDeviceDescriptors =
        manager.getRoutingManager().getDevicesSync(audio.DeviceFlag.INPUT_DEVICES_FLAG);
      for (const descriptor of descriptors) {
        if (VoiceCaptureDevicePolicy.stableId(descriptor.deviceType, descriptor.address) === wanted) {
          // Routing belongs to the audio session rather than to one capturer, which is why this is
          // asserted per recording rather than once when the keyboard starts.
          await manager.getSessionManager().selectMediaInputDevice(descriptor);
          return;
        }
      }
      KeyboardLog.warn('chosen capture device is not present; recording from the system default');
    } catch (error) {
      KeyboardLog.error(`capture device selection refused: ${describeError(error)}`);
    }
  }
}
