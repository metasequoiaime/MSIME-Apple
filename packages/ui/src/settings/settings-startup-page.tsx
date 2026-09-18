export function SettingsStartupPage({ onClose }: { onClose?: () => void }) {
  return <main className="settings-startup" aria-label="设置加载中" aria-busy="true">
    <div className="settings-startup-spinner" aria-hidden="true" />
    <div className="settings-startup-dots" aria-hidden="true">
      <i />
      <i />
      <i />
    </div>
    <h1>正在打开设置</h1>
    <p role="status">冷启动可能需要稍等片刻</p>
    {onClose && <button type="button" className="settings-startup-close" aria-label="关闭设置" onClick={onClose}>×</button>}
  </main>;
}
