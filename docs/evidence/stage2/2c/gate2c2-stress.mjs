// gate2c2-stress.mjs — Stage 2C-2 Step 4：50 文件压力测试装置（仅测试环境使用）
//
// 用途：经 CDP（回环，dev 构建临时环境变量启用）调用应用既有 IPC：
//   1) create_import_entry 逐个登记素材（Rust 侧校验/去重）；
//   2) probe_import_entry 并发触发元数据探测（走真实 managed 生命周期路径）。
// 输出逐条结果与汇总（ready/failed-by-code/unresolved），供压力报告与关闭清理核对。
//
// 边界：仅连 127.0.0.1；页面目标必须为 http://localhost:1420；路径白名单限 test-assets\stress\。
// 用法：node gate2c2-stress.mjs <port> create-and-probe <materials-dir>
//       node gate2c2-stress.mjs <port> fire-and-exit <materials-dir>   （Phase B：只发不等）

import { appendFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const PORT = process.argv[2] ?? "9333";
const MODE = process.argv[3] ?? "create-and-probe";
const DIR = process.argv[4] ?? "";
const LOG = "D:\\应聘项目zcode\\docs\\evidence\\stage2\\2c\\stage2c2-stress-cdp.log";

if (!DIR) {
  console.error("FAIL: materials dir required");
  process.exit(2);
}

const files = readdirSync(DIR).map((n) => join(DIR, n)).sort();
if (files.length === 0) {
  console.error("FAIL: no materials");
  process.exit(2);
}

const log = (line) => appendFileSync(LOG, line + "\n");

log(`# ===== stress ${MODE} ${new Date().toISOString()} files=${files.length} =====`);
const base = `http://127.0.0.1:${PORT}`;
const version = await (await fetch(`${base}/json/version`)).json();
log(`# browser=${version.Browser}`);
const list = await (await fetch(`${base}/json/list`)).json();
const page = list.find(
  (t) => t.type === "page" && typeof t.url === "string" && t.url.startsWith("http://localhost:1420"),
);
if (!page) {
  log("# FAIL no matching page target");
  console.error("FAIL: no matching page target");
  process.exit(4);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
let seq = 0;
const pending = new Map();
ws.addEventListener("message", (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
  }
});
await new Promise((resolve, reject) => {
  ws.addEventListener("open", resolve);
  ws.addEventListener("error", () => reject(new Error("ws error")));
});
const send = (method, params) =>
  new Promise((resolve) => {
    const id = ++seq;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
const evaluate = async (expression) => {
  const resp = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  return resp?.result?.result?.value;
};
const invokeJson = async (method, args) =>
  JSON.parse(await evaluate(`window.__TAURI_INTERNALS__.invoke(${JSON.stringify(method)}, ${JSON.stringify(args)}).then(r => JSON.stringify(r)).catch(e => JSON.stringify({ __ipc_error: String(e) }))`));

// 1) 逐个登记（顺序创建，保证 id 分配确定）
const ids = [];
for (const path of files) {
  const r = await invokeJson("create_import_entry", { path });
  if (r.__ipc_error) {
    log(`CREATE path=${path} error=${r.__ipc_error}`);
    continue;
  }
  ids.push({ id: r.entry.id, path, outcome: r.outcome });
}
log(`# created=${ids.length} duplicates=${ids.filter((x) => x.outcome === "duplicate").length}`);

// 2) 并发探测
const tally = { ready: 0, failed: 0, byCode: {}, unresolved: 0, ipcErrors: 0 };
const probeOne = async ({ id, path }) => {
  const r = await invokeJson("probe_import_entry", { entryId: id, force: false });
  if (r.__ipc_error) {
    tally.ipcErrors += 1;
    log(`PROBE id=${id} file=${path.split("\\").pop()} IPC_ERROR=${r.__ipc_error}`);
    return;
  }
  if (r.state === "ready") {
    tally.ready += 1;
    log(`PROBE id=${id} file=${path.split("\\").pop()} state=ready size=${r.sizeText} dur=${r.durationText} res=${r.resolutionText} v=${r.videoCodecText} a=${r.audioText}`);
  } else {
    tally.failed += 1;
    tally.byCode[r.failureCode] = (tally.byCode[r.failureCode] ?? 0) + 1;
    log(`PROBE id=${id} file=${path.split("\\").pop()} state=failed code=${r.failureCode}`);
  }
};

if (MODE === "create-and-probe") {
  await Promise.all(ids.map(probeOne));
} else {
  // fire-and-exit：发出探测但不等待完成（供关闭窗口制造取消）
  for (const item of ids) {
    evaluate(`window.__TAURI_INTERNALS__.invoke("probe_import_entry", { entryId: ${item.id}, force: false }).then(r => "ok").catch(e => "err")`)
      .then(() => {})
      .catch(() => {});
  }
  log(`# fired=${ids.length} (not awaited)`);
  await new Promise((r) => setTimeout(r, 700));
}

log(`# TALLY ${JSON.stringify(tally)}`);
console.log(`STRESS_${MODE}_OK ready=${tally.ready} failed=${tally.failed} unresolved=${tally.unresolved} byCode=${JSON.stringify(tally.byCode)}`);
ws.close();
process.exit(0);
