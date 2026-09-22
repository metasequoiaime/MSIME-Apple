import http from '@ohos.net.http';

/** Harmony startup telemetry. Failures are intentionally ignored: typing must stay offline-first. */
export function flushStartupTelemetry(): void {
  const request = http.createHttp();
  request.request('https://api.msime.app/v1/telemetry/events', {
    method: http.RequestMethod.POST,
    header: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    extraData: JSON.stringify({
      id: 'harmony-launch-' + Date.now().toString(), kind: 'download',
      platform: 'harmony', version: '0.1.0-dev'
    }),
    connectTimeout: 5000,
    readTimeout: 10000
  }).then((): void => { request.destroy(); }).catch((): void => { request.destroy(); });
}
