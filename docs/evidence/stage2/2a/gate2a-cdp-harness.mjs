// gate2a-cdp-harness.mjs — Stage 2A 缺口补测：CDP 受控注入测试装置（仅测试环境使用）
//
// 用途：在 dev 构建（启动时以临时环境变量设置 WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9333）中，
// 经 127.0.0.1 的 CDP 连接页面上下文，调用应用**既有命令** create_import_entry 注入白名单内的测试路径，
// 随后触发 location.reload() 使前端按正常挂载路径渲染条目；最后断开连接。
//
// 边界与安全：
// - 仅连接 127.0.0.1；仅当页面目标 url 以 http://localhost:1420 开头（本应用 devUrl）时才执行；
// - 命令仅限 create_import_entry；所有路径必须位于 test-assets 白名单目录内；
// - 不安装依赖、不修改源码/配置；仅向固定证据日志追加记录；
// - 生产构建不设置 CDP 环境变量即无此通道（见 Stage-2A 缺口评估 §4.2）。
//
// 用法：node gate2a-cdp-harness.mjs <port> <scenario...>
//   scenario: ghost | longpath | acl | noext

import { appendFileSync, readFileSync } from "node:fs";
import { join } from "node:path";

const PORT = process.argv[2] ?? "9333";
const SCENARIOS = process.argv.slice(3);
const TA = "D:\\应聘项目zcode\\docs\\evidence\\stage2\\test-assets";
const LOG = "D:\\应聘项目zcode\\docs\\evidence\\stage2\\2a\\stage2a-fix-cdp-calls.log";

if (SCENARIOS.length === 0) {
  console.error("FAIL: no scenarios");
  process.exit(2);
}

const scenarioPath = (s) => {
  switch (s) {
    case "ghost":
      return join(TA, "ghost-file.mp4");
    case "longpath":
      return readFileSync(join(TA, "longpath.txt"), "utf8").replace(/^\uFEFF/, "").trim();
    case "acl":
      return join(TA, "acl-test-copy.mkv");
    case "noext":
      return join(TA, "no_extension_sample");
    default:
      throw new Error("unknown scenario: " + s);
  }
};

const log = (line) => {
  appendFileSync(LOG, line + "\n");
};

const paths = SCENARIOS.map((s) => {
  const p = scenarioPath(s);
  if (!p.startsWith(TA + "\\")) {
    throw new Error("path outside whitelist: " + p);
  }
  return { scenario: s, path: p };
});

log(`# ===== CDP harness run ${new Date().toISOString()} port=${PORT} scenarios=${SCENARIOS.join(",")} =====`);

const base = `http://127.0.0.1:${PORT}`;
const version = await (await fetch(`${base}/json/version`)).json();
log(`# browser=${version.Browser} protocol=${version["Protocol-Version"]}`);

const list = await (await fetch(`${base}/json/list`)).json();
const page = list.find(
  (t) => t.type === "page" && typeof t.url === "string" && t.url.startsWith("http://localhost:1420"),
);
if (!page) {
  log("# FAIL no matching page target");
  console.error("FAIL: no matching page target");
  process.exit(4);
}
log(`# target id=${page.id} url=${page.url}`);

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
  ws.addEventListener("error", () => reject(new Error("ws connection error")));
});

const send = (method, params) =>
  new Promise((resolve) => {
    const id = ++seq;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });

for (const { scenario, path } of paths) {
  const expr = `window.__TAURI_INTERNALS__.invoke("create_import_entry", { path: ${JSON.stringify(
    path,
  )} }).then(r => JSON.stringify(r)).catch(e => "ERR:" + String(e))`;
  const resp = await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
  const value = resp?.result?.result?.value;
  log(`INJECT scenario=${scenario}`);
  log(`  path_len=${path.length}`);
  log(`  result=${typeof value === "string" ? value : JSON.stringify(resp)}`);
}

const reload = await send("Runtime.evaluate", { expression: "location.reload(); 'reload-triggered'", returnByValue: true });
log(`RELOAD=${JSON.stringify(reload?.result?.result?.value)}`);
await new Promise((r) => setTimeout(r, 2000));
ws.close();
log(`# harness done ${new Date().toISOString()}`);
console.log("HARNESS_OK");
