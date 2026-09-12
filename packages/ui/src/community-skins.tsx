// Source: MSIME-Apple@9ca823ab40018ced3cb71812503dbc3b94615ac0
// (`SkinCommunityView.swift`, `CommunityGalleryStyle.swift`).
import { useEffect, useRef, useState } from "react";
import { ScreenKeyboardPreview } from "./screen-keyboard-preview";
import type { TouchKeyboardSkinDesign } from "./touch-keyboard-skin-design";

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
  finishTrial(id: string, keep: boolean): Promise<void>;
}

function communityMessage(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    switch (error.code) {
      case "community_invalid": return "搜索内容无效，请修改后重试。";
      case "community_unauthorized": return "登录已失效；仍可退出后匿名浏览。";
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

export function CommunitySkinsPage({ client, theme }: {
  client: CommunitySkinClient;
  theme: "light" | "dark";
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
    <div className="community-heading"><h2>换个心情，从键盘开始</h2><p>发现创作者的配色与巧思，找到你的那一款</p></div>
    {error && <p role="alert" className="error">{error}</p>}
    {!listBusy && skins.length === 0 && <p className="community-empty">暂时没有匹配的皮肤。</p>}
    <div className="community-grid">
      {skins.map(skin => <CommunitySkinCard key={skin.id} skin={skin} theme={theme} open={() => open(skin)} />)}
    </div>
    {hasMore && <button type="button" className="secondary community-more" disabled={listBusy} onClick={() => void requestList(activeSearch.current, true)}>加载更多</button>}
    {listBusy && <p role="status" className="community-loading">正在读取社区皮肤…</p>}
  </div>;
}
