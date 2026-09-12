// Source: MSIME-Apple@9ca823ab40018ced3cb71812503dbc3b94615ac0
// (`SkinCommunityView.swift`, `CommunityGalleryStyle.swift`).
import { useEffect, useRef, useState, type FormEvent } from "react";
import { ScreenKeyboardPreview } from "./screen-keyboard-preview";
import type {
  CustomSkinLibraryClient,
  SavedTouchKeyboardSkin,
  TouchKeyboardSkinDesign,
} from "./touch-keyboard-skin-design";

export type CommunitySkin = {
  id: string;
  name: string;
  description: string;
  author: string;
  design: TouchKeyboardSkinDesign;
  downloads: number;
  rating_count: number;
  rating_average: number;
  owned: boolean;
  my_rating: number;
};

export type CommunitySkinPage = {
  skins: CommunitySkin[];
  has_more: boolean;
};

export type CommunitySkinTrial = { id: string; name: string };
export type CommunitySkinDownload = {
  skin: { id: string; name: string; design: TouchKeyboardSkinDesign };
  trial: CommunitySkinTrial;
};

export interface CommunitySkinClient {
  list(offset: number, search: string): Promise<CommunitySkinPage>;
  detail(id: string): Promise<CommunitySkin>;
  download(id: string, name: string): Promise<CommunitySkinDownload>;
  rate(id: string, stars: number): Promise<void>;
  publish(id: string, name: string, description: string, design: TouchKeyboardSkinDesign): Promise<void>;
  unpublish(id: string): Promise<void>;
  finishTrial(id: string, keep: boolean): Promise<void>;
}

function communityMessage(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "community_invalid": return "搜索内容无效，请修改后重试。";
      case "community_unauthorized": return "登录已失效；仍可退出后匿名浏览。";
      case "community_forbidden": return "没有权限执行此操作；自己的作品不能评分或下架。";
      case "community_conflict": return "作品状态已变化或已达到发布上限，请刷新后重试。";
      case "community_not_found": return "作品不存在或已下架。";
      case "community_rate_limited": return "请求过于频繁，请稍后再试。";
      case "community_cancelled": return "账号状态已变化，请重新加载。";
      case "community_storage": return "无法安全读取登录状态，请检查设备安全设置。";
      case "community_skin_library_full": return "最多保存 12 套皮肤，请先删除不需要的设计。";
      case "community_skin_invalid_name": return "无法保存这款皮肤：名称无效。";
      case "community_skin_duplicate_name": return "无法保存这款皮肤：名称重复。";
      case "community_trial_format": return "无法安全保存试用状态，请稍后重试。";
    }
  }
  return "社区暂时不可用，请稍后重试。";
}

function mergeUnique(current: CommunitySkin[], incoming: CommunitySkin[]): CommunitySkin[] {
  const ids = new Set(current.map(skin => skin.id));
  const additions: CommunitySkin[] = [];
  for (const skin of incoming) {
    if (ids.has(skin.id)) continue;
    ids.add(skin.id);
    additions.push(skin);
  }
  return [...current, ...additions];
}

function rating(skin: CommunitySkin): string {
  return skin.rating_count === 0 ? "暂无评分" : `${skin.rating_average.toFixed(1)} 分`;
}

function boundedGraphemes(value: string, maximum: number): string {
  if (typeof Intl !== "undefined" && "Segmenter" in Intl) {
    const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
    return Array.from(segmenter.segment(value), item => item.segment).slice(0, maximum).join("");
  }
  return [...value].slice(0, maximum).join("");
}

function randomPublicationId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = new Uint8Array(16);
  if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") crypto.getRandomValues(bytes);
  else for (let index = 0; index < bytes.length; index += 1) bytes[index] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, value => value.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function publishMessage(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "community_unauthorized": return "请先登录后再发布皮肤。";
      case "community_forbidden": return "当前账号没有权限执行发布操作。";
      case "community_conflict": return "作品状态已变化或已达到发布上限，请刷新后重试。";
      case "community_invalid": return "名称、说明或皮肤设计不符合发布要求。";
      case "community_rate_limited": return "发布操作过于频繁，请稍后再试。";
      case "community_not_found": return "账号或作品不存在，请重新加载。";
      case "community_cancelled": return "账号状态已变化，请重新登录后重试。";
    }
  }
  return "暂时无法发布皮肤，请稍后重试。";
}

function CommunitySkinPublishDialog({ client, library, onClose, onPublished }: {
  client: CommunitySkinClient;
  library: CustomSkinLibraryClient;
  onClose: () => void;
  onPublished: () => Promise<void>;
}) {
  const [saved, setSaved] = useState<SavedTouchKeyboardSkin[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState("");
  const [publicationId, setPublicationId] = useState(randomPublicationId);

  useEffect(() => {
    let active = true;
    void library.load().then(items => {
      if (!active) return;
      setSaved(items);
      const first = items[0];
      if (first) {
        setSelectedId(first.id);
        setName(first.name);
      }
    }).catch(loadError => {
      if (active) setError(publishMessage(loadError));
    }).finally(() => {
      if (active) setBusy(false);
    });
    return () => { active = false; };
  }, [library]);

  const selected = saved.find(item => item.id === selectedId) ?? null;
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (busy || !selected) return;
    const normalizedName = name.trim();
    const normalizedDescription = description.trim();
    if (!normalizedName || boundedGraphemes(normalizedName, 32) !== normalizedName ||
        [...normalizedName].length > 32 || [...normalizedDescription].length > 280 || !agreed) {
      setError("请填写有效名称和说明，并确认拥有公开发布所需的素材权利。");
      return;
    }
    setBusy(true);
    setError("");
    try {
      await client.publish(publicationId, normalizedName, normalizedDescription, selected.design);
      await onPublished();
    } catch (publishError) {
      setError(publishMessage(publishError));
      setBusy(false);
    }
  };

  return <div className="community-dialog-backdrop">
    <form className="community-publish-dialog" role="dialog" aria-modal="true" aria-label="发布我的皮肤" onSubmit={event => void submit(event)}>
      <div className="community-dialog-heading"><h2>发布我的皮肤</h2><button type="button" className="community-dialog-close" disabled={busy} onClick={onClose} aria-label="关闭发布窗口">×</button></div>
      {error && <p role="alert" className="error">{error}</p>}
      {busy && saved.length === 0 && <p role="status">正在读取我的皮肤…</p>}
      {!busy && saved.length === 0 && <p className="community-empty">还没有命名保存的皮肤，请先在“设计我的皮肤”中保存一款。</p>}
      {saved.length > 0 && <>
        <label>发布设计<select aria-label="发布设计" value={selectedId} disabled={busy} onChange={event => {
          const item = saved.find(value => value.id === event.target.value);
          setSelectedId(event.target.value);
          setPublicationId(randomPublicationId());
          if (item) setName(item.name);
        }}>{saved.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
        {selected && <div className="community-publish-preview"><ScreenKeyboardPreview theme="light" skin="custom" customDesign={selected.design} /></div>}
        <label>皮肤名称<input aria-label="发布皮肤名称" maxLength={32} value={name} disabled={busy} onChange={event => { setPublicationId(randomPublicationId()); setName(boundedGraphemes(event.target.value, 32)); }} /></label>
        <label>设计说明<textarea aria-label="发布设计说明" maxLength={280} rows={4} value={description} disabled={busy} onChange={event => { setPublicationId(randomPublicationId()); setDescription(event.target.value); }} /></label>
        <label className="community-publish-agreement"><input type="checkbox" aria-label="确认拥有发布素材权利" checked={agreed} disabled={busy} onChange={event => setAgreed(event.target.checked)} />我拥有发布所用素材的权利，并同意其他用户免费下载使用</label>
        <p className="community-publish-warning">发布后设计及照片壁纸将公开。请勿包含私人照片或敏感信息；发布成功后可在“我的作品”中下架。</p>
      </>}
      <div className="community-dialog-actions"><button type="button" className="secondary" disabled={busy} onClick={onClose}>取消</button><button type="submit" className="primary" disabled={busy || !selected || !agreed}>{busy ? "正在发布…" : "公开发布"}</button></div>
    </form>
  </div>;
}

function CommunitySkinCard({ skin, theme, open }: {
  skin: CommunitySkin;
  theme: "light" | "dark";
  open: () => void;
}) {
  return <button type="button" className="community-skin-card" aria-label={`查看皮肤 ${skin.name}`} onClick={open}>
    <span className="community-skin-preview"><ScreenKeyboardPreview theme={theme} skin="custom" customDesign={skin.design} compact /></span>
    <strong>{skin.name}</strong>
    <span className="community-skin-author">{skin.owned ? "我的作品" : skin.author}</span>
    <span className="community-skin-metrics"><span>↓ {skin.downloads.toLocaleString("zh-CN")}</span><span>☆ {rating(skin)}</span></span>
  </button>;
}

export function CommunitySkinsPage({ client, theme, localSkinLibrary, initialMine = false }: {
  client: CommunitySkinClient;
  theme: "light" | "dark";
  localSkinLibrary?: CustomSkinLibraryClient;
  initialMine?: boolean;
}) {
  const [skins, setSkins] = useState<CommunitySkin[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [search, setSearch] = useState("");
  const [listBusy, setListBusy] = useState(true);
  const [detailBusy, setDetailBusy] = useState(false);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<CommunitySkin | null>(null);
  const [trial, setTrial] = useState<CommunitySkinTrial | null>(null);
  const [actionBusy, setActionBusy] = useState(false);
  const [actionNotice, setActionNotice] = useState("");
  const [mineOnly, setMineOnly] = useState(initialMine);
  const [publishOpen, setPublishOpen] = useState(false);
  const [confirmUnpublish, setConfirmUnpublish] = useState(false);
  const listGeneration = useRef(0);
  const detailGeneration = useRef(0);
  const nextOffset = useRef(0);
  const activeSearch = useRef("");
  const trialRef = useRef<CommunitySkinTrial | null>(null);

  const requestList = async (query: string, append: boolean) => {
    const generation = ++listGeneration.current;
    const offset = append ? nextOffset.current : 0;
    setListBusy(true);
    setError("");
    try {
      const page = await client.list(offset, query);
      if (generation !== listGeneration.current) return;
      setSkins(current => append ? mergeUnique(current, page.skins) : mergeUnique([], page.skins));
      nextOffset.current = offset + page.skins.length;
      if (!append) activeSearch.current = query;
      setHasMore(page.has_more);
    } catch (requestError) {
      if (generation === listGeneration.current) setError(communityMessage(requestError));
    } finally {
      if (generation === listGeneration.current) setListBusy(false);
    }
  };

  useEffect(() => {
    void requestList("", false);
    return () => {
      listGeneration.current += 1;
      detailGeneration.current += 1;
      const pending = trialRef.current;
      trialRef.current = null;
      if (pending) void client.finishTrial(pending.id, false).catch(() => undefined);
    };
  }, [client]);

  const open = (skin: CommunitySkin) => {
    const generation = ++detailGeneration.current;
    setSelected(skin);
    setDetailBusy(true);
    setError("");
    void client.detail(skin.id).then(value => {
      if (generation === detailGeneration.current) setSelected(value);
    }).catch(detailError => {
      if (generation === detailGeneration.current) setError(communityMessage(detailError));
    }).finally(() => {
      if (generation === detailGeneration.current) setDetailBusy(false);
    });
  };

  const closeDetail = async () => {
    if (actionBusy) return;
    if (trial) {
      setActionBusy(true);
      try {
        await client.finishTrial(trial.id, false);
        trialRef.current = null;
        setTrial(null);
      } catch (actionError) {
        setError(communityMessage(actionError));
        setActionBusy(false);
        return;
      }
      setActionBusy(false);
    }
    detailGeneration.current += 1;
    setSelected(null);
    setDetailBusy(false);
    setError("");
  };

  const download = async () => {
    if (!selected || actionBusy) return;
    setActionBusy(true);
    setActionNotice("");
    setError("");
    try {
      const result = await client.download(selected.id, selected.name);
      setSelected(current => current ? { ...current, design: result.skin.design } : current);
      trialRef.current = result.trial;
      setTrial(result.trial);
      setActionNotice("已下载并开始试用；关闭此页会恢复原皮肤。");
    } catch (actionError) {
      setError(communityMessage(actionError));
    } finally {
      setActionBusy(false);
    }
  };

  const finishTrial = async (keep: boolean) => {
    if (!trial || actionBusy) return;
    const pending = trial;
    setActionBusy(true);
    setError("");
    try {
      await client.finishTrial(pending.id, keep);
      trialRef.current = null;
      setTrial(null);
      setActionNotice(keep ? "已保留这款皮肤。" : "已恢复试用前的皮肤。");
    } catch (actionError) {
      setError(communityMessage(actionError));
    } finally {
      setActionBusy(false);
    }
  };

  const rateSkin = async (stars: number) => {
    if (!selected || actionBusy) return;
    setActionBusy(true);
    setError("");
    try {
      await client.rate(selected.id, stars);
      setSelected(await client.detail(selected.id));
      setActionNotice(`已评分：${stars} 星。`);
    } catch (actionError) {
      setError(communityMessage(actionError));
    } finally {
      setActionBusy(false);
    }
  };

  const unpublish = async () => {
    if (!selected || actionBusy || trial) return;
    setActionBusy(true);
    setError("");
    try {
      await client.unpublish(selected.id);
      detailGeneration.current += 1;
      setSelected(null);
      setConfirmUnpublish(false);
      setActionNotice("已下架这款皮肤；其他用户将无法再下载，已有本地副本不会受影响。");
      await requestList(activeSearch.current, false);
    } catch (actionError) {
      setError(communityMessage(actionError));
    } finally {
      setActionBusy(false);
    }
  };

  const publishDone = async () => {
    setPublishOpen(false);
    setActionNotice("已发布到社区。");
    await requestList(activeSearch.current, false);
  };

  if (selected) return <div className="community-page community-detail-page">
    <button type="button" className="community-back" disabled={actionBusy} onClick={() => void closeDetail()} aria-label="返回社区">← 社区</button>
    {error && <p role="alert" className="error">{error}</p>}
    <section className="section community-detail">
      <div className="community-detail-preview"><ScreenKeyboardPreview theme={theme} skin="custom" customDesign={selected.design} /></div>
      <div className="community-detail-title"><div><h2>{selected.name}</h2><p>{selected.author}</p></div>{selected.owned && <span>我的作品</span>}</div>
      {selected.description && <p className="community-description">{selected.description}</p>}
      <p className="community-detail-metrics">{selected.downloads.toLocaleString("zh-CN")} 人下载 · {rating(selected)} · {selected.rating_count.toLocaleString("zh-CN")} 人评分</p>
      {selected.my_rating > 0 && <p className="community-my-rating">我的评分：{selected.my_rating} 星</p>}
      {detailBusy && <p role="status">正在读取皮肤详情…</p>}
      {actionNotice && <p role="status" className="community-action-notice">{actionNotice}</p>}
      {!trial && <button type="button" className="primary community-action" disabled={actionBusy || detailBusy} onClick={() => void download()}>下载并试用</button>}
      {trial && <div className="community-trial-actions" aria-label="皮肤试用"><p>正在试用：{trial.name}</p><button type="button" className="secondary" disabled={actionBusy} onClick={() => void finishTrial(false)}>恢复原皮肤</button><button type="button" className="primary" disabled={actionBusy} onClick={() => void finishTrial(true)}>保留使用</button></div>}
      {!selected.owned && <div className="community-rating-actions" aria-label="我的评分"><p>我的评分（下载后可评，可重新选择）</p><div>{[1, 2, 3, 4, 5].map(stars => <button key={stars} type="button" className="secondary" disabled={actionBusy} aria-label={`评 ${stars} 星`} onClick={() => void rateSkin(stars)}>{stars} 星</button>)}</div></div>}
      {selected.owned && <button type="button" className="danger-text community-unpublish" disabled={actionBusy || Boolean(trial)} onClick={() => setConfirmUnpublish(true)}>下架这款皮肤</button>}
      {confirmUnpublish && <div className="community-confirmation" role="alertdialog" aria-label="确认下架皮肤">
        <p>下架后其他用户无法再下载，已下载的本地皮肤会保留。确定下架“{selected.name}”吗？</p>
        <div><button type="button" className="danger" disabled={actionBusy} onClick={() => void unpublish()}>确认下架</button><button type="button" className="secondary" disabled={actionBusy} onClick={() => setConfirmUnpublish(false)}>取消</button></div>
      </div>}
    </section>
  </div>;

  return <div className="community-page">
    <form className="community-search" role="search" onSubmit={event => {
      event.preventDefault();
      void requestList(search, false);
    }}>
      <input aria-label="搜索皮肤设计" placeholder="搜索皮肤设计" value={search} onChange={event => setSearch([...event.target.value].slice(0, 128).join(""))} />
      <button type="submit">搜索</button>
    </form>
    <div className="community-heading"><div><h2>{mineOnly ? "你的公开设计" : "换个心情，从键盘开始"}</h2><p>{mineOnly ? "管理你发布到社区的皮肤" : "发现创作者的配色与巧思，找到你的那一款"}</p></div><div className="community-heading-actions"><div className="community-scope-actions" role="group" aria-label="社区皮肤范围"><button type="button" className={mineOnly ? "secondary" : "primary"} aria-pressed={!mineOnly} onClick={() => { if (mineOnly) { setMineOnly(false); void requestList(activeSearch.current, false); } }}>全部皮肤</button><button type="button" className={mineOnly ? "primary" : "secondary"} aria-pressed={mineOnly} onClick={() => { if (!mineOnly) { setMineOnly(true); void requestList(activeSearch.current, false); } }}>我的作品</button></div>{localSkinLibrary && <button type="button" className="primary" onClick={() => setPublishOpen(true)}>发布我的设计</button>}</div></div>
    {error && <p role="alert" className="error">{error}</p>}
    {!listBusy && skins.filter(skin => !mineOnly || skin.owned).length === 0 && <p className="community-empty">{mineOnly ? (hasMore ? "当前页没有你的作品，请继续加载查看更多。" : "还没有已发布的皮肤。") : "暂时没有匹配的皮肤。"}</p>}
    <div className="community-grid">
      {skins.filter(skin => !mineOnly || skin.owned).map(skin => <CommunitySkinCard key={skin.id} skin={skin} theme={theme} open={() => open(skin)} />)}
    </div>
    {hasMore && <button type="button" className="secondary community-more" disabled={listBusy} onClick={() => void requestList(activeSearch.current, true)}>加载更多</button>}
    {listBusy && <p role="status" className="community-loading">正在读取社区皮肤…</p>}
    {publishOpen && localSkinLibrary && <CommunitySkinPublishDialog client={client} library={localSkinLibrary} onClose={() => setPublishOpen(false)} onPublished={publishDone} />}
  </div>;
}
