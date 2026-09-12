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

export interface CommunitySkinClient {
  list(offset: number, search: string): Promise<CommunitySkinPage>;
  detail(id: string): Promise<CommunitySkin>;
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
  const listGeneration = useRef(0);
  const detailGeneration = useRef(0);
  const nextOffset = useRef(0);
  const activeSearch = useRef("");

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

  const closeDetail = () => {
    detailGeneration.current += 1;
    setSelected(null);
    setDetailBusy(false);
    setError("");
  };

  if (selected) return <div className="community-page community-detail-page">
    <button type="button" className="community-back" onClick={closeDetail} aria-label="返回社区">← 社区</button>
    {error && <p role="alert" className="error">{error}</p>}
    <section className="section community-detail">
      <div className="community-detail-preview"><ScreenKeyboardPreview theme={theme} skin="custom" customDesign={selected.design} /></div>
      <div className="community-detail-title"><div><h2>{selected.name}</h2><p>{selected.author}</p></div>{selected.owned && <span>我的作品</span>}</div>
      {selected.description && <p className="community-description">{selected.description}</p>}
      <p className="community-detail-metrics">{selected.downloads.toLocaleString("zh-CN")} 人下载 · {rating(selected)} · {selected.rating_count.toLocaleString("zh-CN")} 人评分</p>
      {selected.my_rating > 0 && <p className="community-my-rating">我的评分：{selected.my_rating} 星</p>}
      {detailBusy && <p role="status">正在读取皮肤详情…</p>}
      <p className="community-readonly-note">当前版本支持浏览和预览；下载试用、评分及发布将在后续版本开放。</p>
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
