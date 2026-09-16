// Just enough of the device modules for the ported logic to type-check off a device.
//
// The classes under test carry no ArkUI or NAPI dependency, which is the whole reason they can run
// under node. KeyboardLog is the exception: it is a thin shim over hilog and is compiled here so a
// change to it is still checked, not so that it is exercised.
declare module '@ohos.hilog' {
  const hilog: {
    info(domain: number, tag: string, format: string, ...parameters: Object[]): void;
    warn(domain: number, tag: string, format: string, ...parameters: Object[]): void;
    error(domain: number, tag: string, format: string, ...parameters: Object[]): void;
  };
  export default hilog;
}

declare module '@ohos.deviceInfo' {
  const deviceInfo: {
    deviceType: string;
    DeviceTypes: {
      TYPE_2IN1: string;
    };
  };
  export default deviceInfo;
}

declare module 'libmsimeclient.so' {
  const client: {
    loadPreferences(directory: string): string;
    savePreferences(directory: string, expectedRevision: number, snapshot: string): string;
  };
  export default client;
}
