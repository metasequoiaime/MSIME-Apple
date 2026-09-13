import { useEffect, useState } from "react";

export type AccountUser = {
  id: string;
  displayName: string;
  createdAt: string;
};

export type AccountProviders = {
  email: boolean;
  phone: boolean;
};

export type AccountChallenge = {
  challengeId: string;
  expiresIn: number;
};

export type AccountProfile = {
  user: AccountUser;
  providers: string[];
};

export type AccountPreferenceValue = boolean | number | string;

export type AccountPreferences = {
  revision: number;
  settings: Record<string, AccountPreferenceValue>;
};

export type AccountPreferenceSchema = {
  fields: Record<string, { type: string }>;
  maximumBytes: number;
  updateMode: string;
  revisionRequired: boolean;
};

export type AppIconInfo = {
  supported: boolean;
  selected: string;
};

export interface AppIconClient {
  info(): Promise<AppIconInfo>;
  set(style: string): Promise<AppIconInfo>;
}

export interface SettingsSyncClient {
  schema(): Promise<AccountPreferenceSchema>;
  load(): Promise<AccountPreferences>;
  upload(): Promise<AccountPreferences>;
  apply(userId: string, preferences: AccountPreferences): Promise<void>;
}

export interface AccountClient {
  status(): Promise<{ user?: AccountUser | null }>;
  providers(): Promise<AccountProviders>;
  requestCode(provider: "email" | "phone", target: string): Promise<AccountChallenge>;
  login(challengeId: string, code: string): Promise<{ user?: AccountUser | null }>;
  profile(): Promise<AccountProfile>;
  rename(displayName: string): Promise<AccountProfile>;
  logout(all: boolean): Promise<void>;
  deleteAccount(): Promise<void>;
  clearExpired(): Promise<void>;
  settingsSync?: SettingsSyncClient;
  appIcon?: AppIconClient;
}

type Channel = "email" | "phone";
type Confirmation = "logout-all" | "delete" | null;

function accountMessage(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "account_invalid": return "填写的内容无效，请检查后重试。";
      case "account_unauthorized": return "登录已失效，请重新登录。";
      case "account_conflict": return "云端设置已被其他设备更新，请刷新后重新确认。";
      case "account_rate_limited": return "操作过于频繁，请稍后再试。";
      case "account_storage": return "无法安全读取登录状态，请检查设备安全设置。";
      case "account_cancelled": return "操作已取消，请重试。";
    }
  }
  return "账号服务暂不可用，请稍后再试。";
}

function preferredName(user: AccountUser): string {
  const name = user.displayName.trim();
  return name || `水杉小鹿·${user.id.slice(0, 6).toUpperCase()}`;
}

function providerName(provider: string): string {
  if (provider === "email") return "邮箱";
  if (provider === "phone" || provider === "sms") return "手机号";
  return provider;
}

const appIconOptions = [
  { id: "classic", title: "原版", detail: "经典黑白，简洁如初", color: "#252525" },
  { id: "forest", title: "杉林", detail: "杉叶青绿，沉静自然", color: "#2f6b4f" },
  { id: "sky", title: "晴空", detail: "清透蓝调，轻盈明亮", color: "#4e8fc8" },
  { id: "dusk", title: "暮紫", detail: "晚霞淡紫，温柔入夜", color: "#71618f" },
  { id: "vermilion", title: "朱砂", detail: "朱红印记，纸上东方", color: "#b9473f" },
] as const;

function AppIconSettingsCard({ client }: { client: AppIconClient }) {
  const [info, setInfo] = useState<AppIconInfo | null>(null);
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    setInfo(null);
    setError("");
    void client.info().then(value => {
      if (active) setInfo(value);
    }).catch(() => {
      if (active) setError("暂时无法读取 App 图标状态，请稍后重试。");
    });
    return () => { active = false; };
  }, [client]);

  const choose = async (style: string) => {
    if (!info?.supported || pending || info.selected === style) return;
    setPending(style);
    setError("");
    try {
      setInfo(await client.set(style));
    } catch {
      // A launcher may apply the alias before reporting a package-manager
      // error. Read the OS state again before showing a failure.
      try { setInfo(await client.info()); }
      catch { setError("图标未能更换，请稍后重试。"); }
    } finally {
      setPending(null);
    }
  };

  return <section className="section app-icon-settings">
    <div>
      <h2>App 图标</h2>
      <p>给主屏幕上的水杉换个颜色。Android 会使用系统启动器的图标别名保存选择。</p>
    </div>
    {info === null && !error && <p role="status">正在读取图标状态…</p>}
    {error && <p role="alert" className="error">{error}</p>}
    {info && !info.supported && <p className="account-muted">当前设备暂不支持更换 App 图标。</p>}
    {info && <div className="app-icon-grid">
      {appIconOptions.map(option => {
        const selected = info.selected === option.id;
        const changing = pending === option.id;
        return <button type="button" className={`app-icon-card${selected ? " selected" : ""}`}
          key={option.id} disabled={!info.supported || pending !== null}
          aria-label={`${option.title}，${option.detail}`} aria-pressed={selected}
          onClick={() => void choose(option.id)}>
          <span className="app-icon-preview" style={{ backgroundColor: option.color }} aria-hidden="true">杉</span>
          <span className="app-icon-copy"><strong>{option.title}</strong><small>{option.detail}</small></span>
          <span className="app-icon-state">{changing ? "更换中" : selected ? "使用中" : "使用此图标"}</span>
        </button>;
      })}
    </div>}
    <p className="account-muted">更换后，系统启动器可能需要片刻刷新。随时可以切回原版。</p>
  </section>;
}

function SettingsSyncCard({ client, userId }: { client: SettingsSyncClient; userId: string }) {
  const [schema, setSchema] = useState<AccountPreferenceSchema | null>(null);
  const [cloud, setCloud] = useState<AccountPreferences | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [confirmation, setConfirmation] = useState<"upload" | "apply" | null>(null);

  const load = async () => {
    if (busy) return;
    setBusy(true);
    setMessage("");
    try {
      const [nextSchema, nextCloud] = await Promise.all([client.schema(), client.load()]);
      setSchema(nextSchema);
      setCloud(nextCloud);
    } catch (error) {
      setMessage(accountMessage(error));
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    let active = true;
    setSchema(null);
    setCloud(null);
    setMessage("");
    setBusy(true);
    void Promise.all([client.schema(), client.load()]).then(([nextSchema, nextCloud]) => {
      if (!active) return;
      setSchema(nextSchema);
      setCloud(nextCloud);
    }).catch(error => {
      if (active) setMessage(accountMessage(error));
    }).finally(() => {
      if (active) setBusy(false);
    });
    return () => { active = false; };
  }, [client, userId]);

  const runConfirmed = async () => {
    if (!cloud || !schema || !confirmation || busy) return;
    setBusy(true);
    setMessage("");
    const operation = confirmation;
    setConfirmation(null);
    try {
      if (operation === "upload") setCloud(await client.upload());
      else await client.apply(userId, cloud);
      setMessage(operation === "upload" ? "本机设置已上传。" : "已应用云端设置。请重新打开键盘使部分设置生效。");
    } catch (error) {
      setMessage(accountMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const hasCloudSettings = Boolean(cloud && Object.keys(cloud.settings).length > 0);
  return <section className="section account-settings-sync">
    <h2>设置同步</h2>
    <p>同步输入方案、简繁体、键盘声音与触感、词库学习开关和皮肤。凭据、联网授权及输入内容不会随设置上传。</p>
    {cloud && <p className="account-muted">云端版本：{cloud.revision}</p>}
    <div className="account-inline-actions">
      <button type="button" className="secondary" disabled={busy} onClick={() => void load()}>刷新云端设置</button>
      <button type="button" className="account-primary" disabled={busy || !cloud || !schema} onClick={() => setConfirmation("upload")}>上传本机设置</button>
      <button type="button" className="secondary" disabled={busy || !cloud || !schema || !hasCloudSettings} onClick={() => setConfirmation("apply")}>下载并应用云端设置</button>
    </div>
    {busy && <p role="status">正在处理…</p>}
    {message && <p role="status">{message}</p>}
    {confirmation && <div className="account-confirmation" role="alertdialog" aria-label={confirmation === "upload" ? "确认上传本机设置" : "确认应用云端设置"}>
      <p>{confirmation === "upload"
        ? "将更新云端对应设置，并保留其他平台专属设置。版本冲突时不会自动覆盖。"
        : "将替换本机对应设置，不会下载词库或开启数据上传。"}</p>
      <div>
        <button type="button" className="account-primary" disabled={busy} onClick={() => void runConfirmed()}>{confirmation === "upload" ? "确认上传" : "确认应用"}</button>
        <button type="button" className="secondary" disabled={busy} onClick={() => setConfirmation(null)}>取消</button>
      </div>
    </div>}
  </section>;
}

export function AccountPage({ client, onOpenPublishedSkins }: {
  client: AccountClient;
  onOpenPublishedSkins?: () => void;
}) {
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [providers, setProviders] = useState<AccountProviders>({ email: false, phone: false });
  const [user, setUser] = useState<AccountUser | null>(null);
  const [profile, setProfile] = useState<AccountProfile | null>(null);
  const [channel, setChannel] = useState<Channel | null>(null);
  const [target, setTarget] = useState("");
  const [code, setCode] = useState("");
  const [challenge, setChallenge] = useState<AccountChallenge | null>(null);
  const [expiresAt, setExpiresAt] = useState(0);
  const [resendAt, setResendAt] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const [name, setName] = useState("");
  const [confirmation, setConfirmation] = useState<Confirmation>(null);

  const applyProfile = (value: AccountProfile) => {
    setProfile(value);
    setUser(value.user);
    setName(value.user.displayName);
  };

  const loadProfile = async () => {
    const value = await client.profile();
    applyProfile(value);
  };

  useEffect(() => {
    let active = true;
    void Promise.allSettled([client.status(), client.providers()]).then(async results => {
      if (!active) return;
      const [status, available] = results;
      if (available.status === "fulfilled") setProviders(available.value);
      else setError(accountMessage(available.reason));
      if (status.status === "fulfilled") {
        const nextUser = status.value.user ?? null;
        setUser(nextUser);
        if (nextUser) {
          setName(nextUser.displayName);
          try {
            const value = await client.profile();
            if (active) applyProfile(value);
          } catch (profileError) {
            if (active) setError(accountMessage(profileError));
          }
        }
      } else {
        setError(accountMessage(status.reason));
      }
      if (active) setLoading(false);
    });
    return () => { active = false; };
  }, [client]);

  useEffect(() => {
    if (!challenge) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [challenge]);

  const perform = async (operation: () => Promise<void>) => {
    if (busy) return;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await operation();
    } catch (operationError) {
      setError(accountMessage(operationError));
    } finally {
      setBusy(false);
    }
  };

  const chooseChannel = (value: Channel) => {
    setChannel(value);
    setTarget("");
    setCode("");
    setChallenge(null);
    setError("");
    setNotice("");
  };

  const requestCode = () => void perform(async () => {
    if (!channel) return;
    const normalized = target.trim();
    if (!normalized) throw { code: "account_invalid" };
    const value = await client.requestCode(channel, normalized);
    const timestamp = Date.now();
    setNow(timestamp);
    setChallenge(value);
    setExpiresAt(timestamp + value.expiresIn * 1000);
    setResendAt(timestamp + 60_000);
    setCode("");
    setNotice("验证码已发送，请查收。");
  });

  const signIn = () => void perform(async () => {
    if (!challenge || code.length !== 6 || !/^\d{6}$/.test(code) || expiresAt <= Date.now())
      throw { code: "account_invalid" };
    const result = await client.login(challenge.challengeId, code);
    if (!result.user) throw { code: "account_unavailable" };
    setUser(result.user);
    setChannel(null);
    setChallenge(null);
    setCode("");
    await loadProfile();
    setNotice("登录成功。");
  });

  const signOut = (all: boolean) => void perform(async () => {
    await client.logout(all);
    setUser(null);
    setProfile(null);
    setName("");
    setConfirmation(null);
    setNotice(all ? "已退出所有设备。" : "已退出登录。");
  });

  const deleteAccount = () => void perform(async () => {
    await client.deleteAccount();
    setUser(null);
    setProfile(null);
    setName("");
    setConfirmation(null);
    setNotice("账号已注销。");
  });

  const clearExpired = () => void perform(async () => {
    await client.clearExpired();
    setUser(null);
    setProfile(null);
    setName("");
    setNotice("已清除失效登录状态。");
  });

  const rename = () => void perform(async () => {
    const normalized = name.trim();
    if (!normalized || [...normalized].length > 64 || /[\u0000-\u001f\u007f]/.test(normalized))
      throw { code: "account_invalid" };
    applyProfile(await client.rename(normalized));
    setNotice("昵称已更新。");
  });

  if (loading) return <div className="account-page"><p role="status">正在读取账号状态…</p></div>;

  const resendSeconds = Math.max(0, Math.ceil((resendAt - now) / 1000));
  const expired = Boolean(challenge) && expiresAt <= now;
  const enabledProviders = Number(providers.email) + Number(providers.phone);

  return <div className="account-page">
    {error && <p role="alert" className="error">{error}</p>}
    {notice && <p role="status" className="notice">{notice}</p>}
    <section className="section account-hero">
      <div className="account-avatar" aria-hidden="true">{user ? preferredName(user).slice(0, 1) : "杉"}</div>
      <div>
        <h2>{user ? preferredName(user) : "欢迎来到水杉"}</h2>
        <p>{user ? "水杉账号已登录" : "登录，分享你的键盘设计"}</p>
      </div>
    </section>
    {client.appIcon && <AppIconSettingsCard client={client.appIcon} />}
    {user ? <>
      <section className="section account-profile">
        <div>
          <h2>个人资料</h2>
          <p>昵称会显示在社区作品中，已发布的作品也会同步更新。</p>
        </div>
        <label>社区昵称
          <input aria-label="社区昵称" maxLength={64} value={name}
            onChange={event => setName(event.target.value)} disabled={busy} />
        </label>
        <div className="account-inline-actions">
          <button type="button" className="account-primary" disabled={busy || name.trim() === user.displayName}
            onClick={rename}>{busy ? "正在处理…" : "保存昵称"}</button>
        </div>
        <dl className="account-details">
          <div><dt>账号 ID</dt><dd>#{user.id.slice(0, 6).toUpperCase()}</dd></div>
          <div><dt>登录方式</dt><dd>{profile?.providers.map(providerName).join("、") || "正在读取"}</dd></div>
        </dl>
      </section>
      <section className="section account-actions">
        <h2>账号</h2>
        <div>
          <button type="button" className="secondary" disabled={busy} onClick={() => signOut(false)}>退出登录</button>
          <button type="button" className="secondary" disabled={busy} onClick={() => setConfirmation("logout-all")}>退出所有设备</button>
          <button type="button" className="danger-text" disabled={busy} onClick={() => setConfirmation("delete")}>注销账号</button>
        </div>
        {confirmation && <div className="account-confirmation" role="alertdialog" aria-label={confirmation === "delete" ? "确认注销账号" : "确认退出所有设备"}>
          <p>{confirmation === "delete"
            ? "注销账号将删除已发布皮肤、评分及其他云端账号数据，无法撤销。"
            : "退出所有设备后，所有设备都需要重新登录。"}</p>
          <div>
            <button type="button" className={confirmation === "delete" ? "danger-text" : "account-primary"}
              disabled={busy} onClick={() => confirmation === "delete" ? deleteAccount() : signOut(true)}>
              {confirmation === "delete" ? "确认注销账号" : "确认退出所有设备"}
            </button>
            <button type="button" className="secondary" disabled={busy} onClick={() => setConfirmation(null)}>取消</button>
          </div>
        </div>}
      </section>
      {client.settingsSync && <SettingsSyncCard client={client.settingsSync} userId={user.id} />}
      {onOpenPublishedSkins && <section className="section account-community-actions">
        <div><h2>我的创作</h2><p>查看和管理你已经公开发布的键盘皮肤。</p></div>
        <button type="button" className="secondary" disabled={busy} onClick={onOpenPublishedSkins}>我发布的皮肤</button>
      </section>}
    </> : <section className="section account-login">
      <h2>{channel === "email" ? "邮箱登录" : channel === "phone" ? "手机号登录" : "登录方式"}</h2>
      {!channel ? <>
        <div className="account-provider-actions">
          {providers.email && <button type="button" className="account-primary" onClick={() => chooseChannel("email")}>邮箱登录</button>}
          {providers.phone && <button type="button" className="account-primary" onClick={() => chooseChannel("phone")}>手机号登录</button>}
        </div>
        {enabledProviders === 0 && <p className="account-muted">当前没有可用的验证码登录方式，请稍后重试。</p>}
        <button type="button" className="secondary" disabled={busy} onClick={() => void perform(async () => setProviders(await client.providers()))}>刷新登录方式</button>
        <button type="button" className="secondary" disabled={busy} onClick={clearExpired}>清除失效登录状态</button>
      </> : <>
        <label>{channel === "email" ? "邮箱地址" : "手机号（含国家区号）"}
          <input aria-label={channel === "email" ? "邮箱地址" : "手机号（含国家区号）"}
            type={channel === "email" ? "email" : "tel"} autoComplete={channel === "email" ? "email" : "tel"}
            maxLength={320} value={target} disabled={busy}
            onChange={event => { setTarget(event.target.value); setChallenge(null); setCode(""); }} />
        </label>
        <div className="account-inline-actions">
          <button type="button" className="account-primary" disabled={busy || !target.trim() || resendSeconds > 0}
            onClick={requestCode}>{resendSeconds > 0 ? `${resendSeconds} 秒后可重新发送` : "获取验证码"}</button>
          <button type="button" className="secondary" disabled={busy} onClick={() => setChannel(null)}>取消</button>
        </div>
        {challenge && <div className="account-code">
          <label>6 位验证码
            <input aria-label="6 位验证码" inputMode="numeric" autoComplete="one-time-code" maxLength={6}
              value={code} disabled={busy}
              onChange={event => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))} />
          </label>
          <button type="button" className="account-primary" disabled={busy || expired || !/^\d{6}$/.test(code)}
            onClick={signIn}>{expired ? "验证码已过期，请重新获取" : busy ? "正在登录…" : "登录"}</button>
        </div>}
        <p className="account-muted">验证码只用于本次登录，请勿向他人透露。</p>
      </>}
    </section>}
    <section className="section account-privacy">
      <h2>本地数据与云端作品</h2>
      <p>皮肤设计和打字统计保存在本机。只有你主动发布的作品会分享至社区；账号登录不会自动上传本地设计或输入记录。</p>
    </section>
  </div>;
}
