import { invoke } from "@tauri-apps/api/core";

/**
 * Phase 2A 导入 API 层：与 Rust 端 `src-tauri/src/import.rs` 的命令一一对应。
 *
 * 边界：文件的文件系统层校验与判重全部在 Rust 侧完成（路径按不可信输入处理），
 * 前端只负责提交"对话框返回的路径"与渲染结果，不做文件系统判断。
 */

/** 条目状态（与 Rust `EntryStatus` 的 serde 取值一致）。 */
export type EntryStatus = "ready" | "failed";

/** 与 Rust `ImportEntry` 对应（serde camelCase）。 */
export interface ImportEntry {
  id: number;
  fileName: string;
  /** 完整路径：内部与展示均保留；界面可截断显示，但不得丢弃完整值。 */
  path: string;
  status: EntryStatus;
  errorCode: string | null;
  errorMessage: string | null;
}

/** 与 Rust `CreateImportResult` 对应。 */
export interface CreateImportResult {
  /** "created"=新增条目；"duplicate"=同路径已在列表中（未新增，原条目不变）。 */
  outcome: "created" | "duplicate";
  entry: ImportEntry;
}

/** 当前导入条目列表（按创建顺序）。 */
export function listImportEntries(): Promise<ImportEntry[]> {
  return invoke<ImportEntry[]>("list_import_entries");
}

/**
 * 打开系统原生文件选择窗口（Rust 侧 dialog 插件调用；最小权限，WebView 无 dialog 能力）。
 * - 返回完整路径字符串：用户选择了文件；
 * - 返回 null：用户取消（不产生条目、不报错）。
 */
export function pickVideoFile(): Promise<string | null> {
  return invoke<string | null>("pick_video_file");
}

/**
 * 为给定路径创建导入条目（Rust 侧完成文件系统层校验与规范化去重）。
 *
 * 集成点（受依赖授权阻塞）：D-0013 已批准引入 tauri-plugin-dialog，但尚未获得安装授权；
 * 授权后由"原生文件选择"取得路径并调用本函数，重复路径返回 duplicate（界面提示"已在列表中"）。
 */
export function createImportEntry(path: string): Promise<CreateImportResult> {
  return invoke<CreateImportResult>("create_import_entry", { path });
}

/** 元数据探测视图（与 Rust `ProbeView` 对应，serde camelCase；缺失字段为 null，前端渲染 N/A）。 */
export interface ProbeView {
  entryId: number;
  state: "ready" | "failed";
  sizeBytes: number | null;
  sizeText: string | null;
  durationText: string | null;
  resolutionText: string | null;
  videoCodecText: string | null;
  audioText: string | null;
  failureCode: string | null;
  failureMessage: string | null;
}

/**
 * 为指定导入条目异步执行元数据探测（仅接受条目 ID——媒体路径取自导入登记表，
 * 前端无法指定任意路径或可执行文件；结果在 Rust 侧会话级缓存）。
 * `force = true` 时忽略缓存重新探测（供失败后的"重试"使用）。
 */
export function probeImportEntry(entryId: number, force = false): Promise<ProbeView> {
  return invoke<ProbeView>("probe_import_entry", { entryId, force });
}

/** 会话内已缓存的探测结果（挂载时与条目列表合并渲染）。 */
export function listProbeResults(): Promise<ProbeView[]> {
  return invoke<ProbeView[]>("list_probe_results");
}

/** 缩略图视图（与 Rust `ThumbView` 对应；state = "ready" | "failed"）。 */
export interface ThumbView {
  entryId: number;
  state: "ready" | "failed";
  /** `data:image/jpeg;base64,…`（ready 时存在）。 */
  dataUrl: string | null;
  failureCode: string | null;
  failureMessage: string | null;
  /** 本次是否直接命中磁盘缓存。 */
  cacheHit: boolean;
}

/**
 * 为指定导入条目生成/读取缩略图（FFmpeg CLI 提帧；磁盘缓存键含源大小+mtime，
 * 命中即秒回；仅接受条目 ID——路径取自导入登记表）。
 * `force = true` 忽略缓存重新提取。
 */
export function generateThumbnail(entryId: number, force = false): Promise<ThumbView> {
  return invoke<ThumbView>("generate_thumbnail", { entryId, force });
}

/** 转换结果视图（与 Rust `ConversionView` 对应）。 */
export interface ConversionView {
  entryId: number;
  state: "converting" | "completed" | "failed";
  format: string | null;
  outputPath: string | null;
  outputSize: number | null;
  failureCode: string | null;
  failureMessage: string | null;
}

/**
 * 为指定条目执行视频转换（FFmpeg CLI；阻塞至完成；前端以即发即忘调用）。
 * `format` = "mp4" | "webm"。
 */
export function convertVideo(entryId: number, format: string): Promise<ConversionView> {
  return invoke<ConversionView>("convert_video", { entryId, format });
}

/** 全部转换结果（挂载时恢复状态）。 */
export function listConversionResults(): Promise<ConversionView[]> {
  return invoke<ConversionView[]>("list_conversion_results");
}
