import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import {
  convertVideo,
  createImportEntry,
  generateThumbnail,
  listConversionResults,
  listImportEntries,
  listProbeResults,
  pickVideoFile,
  probeImportEntry,
  revealConversionOutput,
  type ConversionView,
  type ConvProgress,
  type ImportEntry,
  type ProbeView,
  type ThumbView,
} from "./importApi";
import "./App.css";

/** 仅影响展示：过长路径截断；完整路径始终保留在 state、DOM 属性与展开视图中。 */
function truncatePath(path: string, head = 34, tail = 42): string {
  if (path.length <= head + tail + 1) {
    return path;
  }
  return `${path.slice(0, head)}…${path.slice(-tail)}`;
}

/** 探测槽位：未开始 / 解析中 / 结果。 */
type ProbeSlot = ProbeView | "probing" | undefined;

/** 缩略图槽位：未开始 / 生成中 / 结果。 */
type ThumbSlot = ThumbView | "probing" | undefined;

/** 转换槽位：未开始 / 转换中 / 结果。 */
type ConvSlot = ConversionView | "converting" | undefined;

/** 元数据行：值缺失显示 N/A，不编造任何值。 */
function MetaRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="meta-item">
      <span className="meta-label">{label}</span>
      <span className="meta-value">{value ?? "N/A"}</span>
    </div>
  );
}

/** 缩略图区：ready 显示真实帧；failed 显示错误码与原因；probing 提示；未请求不渲染。 */
function ThumbBlock({ thumb, onRetry }: { thumb: ThumbSlot; onRetry: () => void }) {
  if (thumb === "probing") {
    return <div className="thumb-slot thumb-pending">缩略图生成中…</div>;
  }
  if (thumb === undefined) {
    return null;
  }
  if (thumb.state === "failed") {
    return (
      <div className="thumb-slot thumb-error">
        <span>
          缩略图生成失败
          {thumb.failureCode !== null ? `（${thumb.failureCode}）` : ""}：
          {thumb.failureMessage ?? "未知原因"}
        </span>
        <button type="button" className="meta-retry" onClick={onRetry}>
          重试
        </button>
      </div>
    );
  }
  return (
    <img
      className="thumb"
      src={thumb.dataUrl ?? ""}
      alt="视频缩略图"
      title={thumb.cacheHit ? "缩略图（缓存）" : "缩略图"}
    />
  );
}

function ProbeBlock({ probe, onRetry }: { probe: ProbeSlot; onRetry: () => void }) {
  if (probe === "probing") {
    return <div className="entry-meta meta-pending">元数据解析中…</div>;
  }
  if (probe === undefined) {
    return <div className="entry-meta meta-pending">元数据：未解析</div>;
  }
  if (probe.state === "failed") {
    return (
      <div className="entry-meta meta-error">
        <span>
          元数据读取失败
          {probe.failureCode !== null ? `（${probe.failureCode}）` : ""}：
          {probe.failureMessage ?? "未知原因"}
        </span>
        <button type="button" className="meta-retry" onClick={onRetry}>
          重试
        </button>
      </div>
    );
  }
  return (
    <div className="entry-meta">
      <MetaRow label="大小" value={probe.sizeText} />
      <MetaRow label="时长" value={probe.durationText} />
      <MetaRow label="分辨率" value={probe.resolutionText} />
      <MetaRow label="帧率" value={probe.frameRateText} />
      <MetaRow label="视频编码" value={probe.videoCodecText} />
      <MetaRow label="音频编码" value={probe.audioText} />
      <MetaRow label="比特率" value={probe.bitRateText} />
      <MetaRow label="容器" value={probe.containerText} />
    </div>
  );
}

/** 另一输出格式（供"转 WebM / 转 MP4"与失败态"改用 …"）。 */
function otherFormat(format: string | null | undefined): string {
  return (format ?? "mp4") === "mp4" ? "webm" : "mp4";
}

/** 转换区：格式按钮 + 状态展示（转换中显示进度；completed 可切格式/打开文件夹）。 */
function ConvSection({
  conv,
  percent,
  onConvert,
  onReveal,
}: {
  conv: ConvSlot;
  percent: number | undefined;
  onConvert: (format: string) => void;
  onReveal: () => void;
}) {
  if (conv === "converting") {
    return (
      <div className="conv-section conv-pending">
        <span className="conv-label">转换中…</span>
        {typeof percent === "number" && (
          <div
            className="conv-progress"
            role="progressbar"
            aria-valuenow={Math.round(percent)}
            aria-valuemin={0}
            aria-valuemax={100}
          >
            <div className="conv-progress-fill" style={{ width: `${percent}%` }} />
            <span className="conv-progress-text">{percent.toFixed(0)}%</span>
          </div>
        )}
      </div>
    );
  }
  if (conv === undefined) {
    return (
      <div className="conv-section">
        <span className="conv-label">转换</span>
        <button type="button" className="conv-btn" onClick={() => onConvert("mp4")}>MP4</button>
        <button type="button" className="conv-btn" onClick={() => onConvert("webm")}>WebM</button>
      </div>
    );
  }
  if (conv.state === "failed") {
    const other = otherFormat(conv.format);
    return (
      <div className="conv-section conv-error">
        <span>
          转换失败（{conv.failureCode}）：{conv.failureMessage}
        </span>
        <button type="button" className="conv-btn" onClick={() => onConvert(conv.format ?? "mp4")}>重试</button>
        <button type="button" className="conv-btn" onClick={() => onConvert(other)}>
          改用 {other.toUpperCase()}
        </button>
      </div>
    );
  }
  const used = conv.format ?? "mp4";
  const other = otherFormat(used);
  return (
    <div className="conv-section conv-ok">
      <span className="conv-label">
        已输出 {used.toUpperCase()}（{conv.outputSize ? `${(conv.outputSize / 1024).toFixed(0)} KB` : ""}）
      </span>
      <button type="button" className="conv-btn" onClick={() => onConvert(used)}>重新转换</button>
      <button type="button" className="conv-btn" onClick={() => onConvert(other)}>
        转 {other.toUpperCase()}
      </button>
      <button type="button" className="conv-btn" onClick={onReveal}>打开所在文件夹</button>
    </div>
  );
}

function App() {
  const [entries, setEntries] = useState<ImportEntry[]>([]);
  const [probes, setProbes] = useState<Record<number, ProbeSlot>>({});
  const [thumbs, setThumbs] = useState<Record<number, ThumbSlot>>({});
  const [convs, setConvs] = useState<Record<number, ConvSlot>>({});
  const [convPct, setConvPct] = useState<Record<number, number>>({});
  const [notice, setNotice] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);

  async function refreshEntries() {
    setEntries(await listImportEntries());
  }

  useEffect(() => {
    (async () => {
      const [entryList, probeList, convList] = await Promise.all([
        listImportEntries(),
        listProbeResults(),
        listConversionResults(),
      ]);
      setEntries(entryList);
      const merged: Record<number, ProbeSlot> = {};
      for (const view of probeList) {
        merged[view.entryId] = view;
      }
      setProbes(merged);
      const convMerged: Record<number, ConvSlot> = {};
      for (const view of convList) {
        convMerged[view.entryId] = view;
      }
      setConvs(convMerged);
      // 已就绪条目自动补齐缩略图（磁盘缓存命中即秒回）
      for (const entry of entryList) {
        const slot = merged[entry.id];
        if (entry.status === "ready" && slot && slot !== "probing" && slot.state === "ready") {
          void runThumb(entry.id);
        }
      }
    })().catch((error) => setNotice(`读取数据失败：${String(error)}`));
  }, []);

  /** 转换进度订阅（Rust 事件 "conv-progress"）：仅更新时间与百分比，不改变转换结论。 */
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void listen<ConvProgress>("conv-progress", (event) => {
      const { entryId, percent } = event.payload;
      setConvPct((prev) => ({ ...prev, [entryId]: percent }));
    }).then((fn) => {
      unlisten = fn;
    });
    return () => {
      unlisten?.();
    };
  }, []);

  function probeFailureFallback(entryId: number, error: unknown): ProbeView {
    return {
      entryId,
      state: "failed",
      sizeBytes: null,
      sizeText: null,
      durationText: null,
      resolutionText: null,
      videoCodecText: null,
      audioText: null,
      frameRateText: null,
      bitRateText: null,
      containerText: null,
      failureCode: null,
      failureMessage: `探测调用失败：${String(error)}`,
    };
  }

  async function runProbe(entryId: number, force = false) {
    setProbes((prev) => ({ ...prev, [entryId]: "probing" }));
    try {
      const view = await probeImportEntry(entryId, force);
      setProbes((prev) => ({ ...prev, [entryId]: view }));
      // 元数据就绪后自动生成缩略图（即发即忘；失败条目不生成）
      if (view.state === "ready") {
        void runThumb(entryId);
      }
    } catch (error) {
      // 仅在仍处于"解析中"时回填失败态，避免快速重复调用把已完成的真实结果覆盖成合成错误。
      setProbes((prev) =>
        prev[entryId] === "probing"
          ? { ...prev, [entryId]: probeFailureFallback(entryId, error) }
          : prev,
      );
    }
  }

  async function runThumb(entryId: number, force = false) {
    setThumbs((prev) => ({ ...prev, [entryId]: "probing" }));
    try {
      const view = await generateThumbnail(entryId, force);
      setThumbs((prev) => ({ ...prev, [entryId]: view }));
    } catch {
      // 缩略图调用失败：槽位复位（不伪造缩略图），错误信息由下次调用/重试呈现
      setThumbs((prev) => (prev[entryId] === "probing" ? { ...prev, [entryId]: undefined } : prev));
    }
  }

  async function runConv(entryId: number, format: string) {
    setConvs((prev) => ({ ...prev, [entryId]: "converting" }));
    setConvPct((prev) => {
      const next = { ...prev };
      delete next[entryId];
      return next;
    });
    try {
      const view = await convertVideo(entryId, format);
      setConvs((prev) => ({ ...prev, [entryId]: view }));
    } catch (error) {
      setConvs((prev) =>
        prev[entryId] === "converting"
          ? { ...prev, [entryId]: undefined }
          : prev,
      );
      setNotice(`转换失败：${String(error)}`);
    }
  }

  async function handleReveal(entryId: number) {
    try {
      await revealConversionOutput(entryId);
    } catch (error) {
      setNotice(`打开所在文件夹失败：${String(error)}`);
    }
  }

  async function handleImportClick() {
    if (busy) {
      return;
    }
    setNotice(null);
    setBusy(true);
    try {
      // 1) 原生文件选择（Rust 侧 dialog 插件；取消返回 null：不产生条目、不报错——P2A-002）
      const picked = await pickVideoFile();
      if (picked === null) {
        return;
      }
      // 2) Rust 侧校验 + 规范化去重（P2A-004/005/006/007；前端不做文件系统判断）
      const result = await createImportEntry(picked);
      // 3) 刷新列表；重复路径提示"已在列表中"（P2A-007 / P2D-009）
      await refreshEntries();
      if (result.outcome === "duplicate") {
        setNotice(`已在列表中：${result.entry.fileName}`);
      } else if (result.entry.status === "ready") {
        // 4) 异步元数据探测（Phase 2B-2）：即发即忘，不占用导入按钮的 busy 态，
        //    探测期间界面保持可交互；失败条目不做探测，导入状态不受影响。
        void runProbe(result.entry.id);
      }
    } catch (error) {
      setNotice(`导入失败：${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="app">
      <header className="toolbar">
        <h1>ClipForge</h1>
        <span className="subtitle">本地视频导入 · 元数据 · 格式转换</span>
        <button type="button" className="primary" onClick={handleImportClick} disabled={busy}>
          {busy ? "选择中…" : "导入视频"}
        </button>
      </header>

      {notice !== null && (
        <div className="notice" role="status">
          {notice}
        </div>
      )}

      <section className="list-area" aria-label="导入条目列表">
        {entries.length === 0 ? (
          <p className="empty">尚未导入任何文件。</p>
        ) : (
          <ul className="entry-list">
            {entries.map((entry) => (
              <li key={entry.id} className={`entry entry-${entry.status}`}>
                <div className="entry-main">
                  <span className="entry-name">{entry.fileName}</span>
                  <span className={`badge badge-${entry.status}`}>
                    {entry.status === "ready" ? "已导入（路径校验通过）" : "导入失败"}
                  </span>
                </div>
                <button
                  type="button"
                  className="entry-path"
                  title={entry.path}
                  onClick={() =>
                    setExpandedId(expandedId === entry.id ? null : entry.id)
                  }
                >
                  {expandedId === entry.id ? entry.path : truncatePath(entry.path)}
                </button>
                {entry.status === "ready" && (
                  <ThumbBlock
                    thumb={thumbs[entry.id]}
                    onRetry={() => void runThumb(entry.id, true)}
                  />
                )}
                {entry.status === "failed" ? (
                  <div className="entry-error">
                    {entry.errorMessage}（{entry.errorCode}）
                  </div>
                ) : (
                  <>
                    <ProbeBlock probe={probes[entry.id]} onRetry={() => void runProbe(entry.id, true)} />
                    <ConvSection
                      conv={convs[entry.id]}
                      percent={convPct[entry.id]}
                      onConvert={(format) => void runConv(entry.id, format)}
                      onReveal={() => void handleReveal(entry.id)}
                    />
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

export default App;
