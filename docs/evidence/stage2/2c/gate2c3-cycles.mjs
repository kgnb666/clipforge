// gate2c3-cycles.mjs — Stage 2C-3 Step 2A：≥100 次导入+探测循环长稳测试装置（仅测试环境使用）
//
// 用法：node gate2c3-cycles.mjs <port> <materials-dir> [waves=40]
// 流程：顺序 create_import_entry ×N（去重安全）→ 分波并发 probe_import_entry（每波默认 40）→
//       汇总 ready/failed/unresolved 与耗时；全程逐条记录到 stage2c3-cycles-cdp.log。

import { appendFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const PORT = process.argv[2] ?? "9333";
const DIR = process.argv[3] ?? "";
const WAVES = Number(process.argv[4] ?? 40);
const LOG = "D:\\应聘项目zcode\\docs\\evidence\\stage2\\2c\\stage2c3-cycles-cdp.log";

const files = readdirSync(DIR).map((n) => join(DIR, n)).sort();
if (files.length === 0) {
  console.error("FAIL: no materials");
  process.exit(2);
}
const log = (line) => appendFileSync(LOG, line + "\n");
log(`# ===== cycles run ${new Date().toISOString()} files=${files.length} waves=${WAVES} =====`);

const base = `http://127.0.0.1:${PORT}`;
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
const invokeJson = async (method, args) => {
  const resp = await send("Runtime.evaluate", {
    expression: `window.__TAURI_INTERNALS__.invoke(${JSON.stringify(method)}, ${JSON.stringify(args)}).then(r => JSON.stringify(r)).catch(e => JSON.stringify({ __ipc_error: String(e) }))`,
    awaitPromise: true,
    returnByValue: true,
  });
  return JSON.parse(resp?.result?.result?.value ?? "{}");
};

const started = Date.now();
// 1) 顺序登记
const ids = [];
let dup = 0;
for (const path of files) {
  const r = await invokeJson("create_import_entry", { path });
  if (r.__ipc_error) {
    log(`CREATE path=${path} error=${r.__ipc_error}`);
    continue;
  }
  if (r.outcome === "duplicate") dup += 1;
  ids.push({ id: r.entry.id, name: path.split("\\").pop() });
}
log(`# created=${ids.length} duplicates=${dup}`);

// 2) 分波并发探测
const tally = { ready: 0, failed: 0, unresolved: 0, ipcErrors: 0, byCode: {} };
const probeOne = async (item) => {
  const r = await invokeJson("probe_import_entry", { entryId: item.id, force: false });
  if (r.__ipc_error) {
    tally.ipcErrors += 1;
    log(`PROBE ${item.name} IPC_ERROR=${r.__ipc_error}`);
    return;
  }
  if (r.state === "ready") {
    tally.ready += 1;
  } else {
    tally.failed += 1;
    tally.byCode[r.failureCode] = (tally.byCode[r.failureCode] ?? 0) + 1;
  }
};
for (let i = 0; i < ids.length; i += WAVES) {
  const wave = ids.slice(i, i + WAVES);
  await Promise.all(wave.map(probeOne));
  log(`# wave ${Math.floor(i / WAVES) + 1}: cumulative ready=${tally.ready} failed=${tally.failed} ipcErrors=${tally.ipcErrors}`);
}
const elapsedS = ((Date.now() - started) / 1000).toFixed(1);
log(`# TALLY ${JSON.stringify(tally)} elapsed_s=${elapsedS}`);
console.log(`CYCLES_OK total=${ids.length} ready=${tally.ready} failed=${tally.failed} ipcErrors=${tally.ipcErrors} elapsed_s=${elapsedS}`);
ws.close();
process.exit(0);
