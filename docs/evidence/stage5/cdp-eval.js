// cdp-eval.js — 通过 CDP 在 ClipForge WebView 页面中执行一段 JS 并返回结果（诊断用）
// 用法: node cdp-eval.js "<js表达式>"  （需先以 --remote-debugging-port=9333 启动应用）
const http = require("http");

function getTarget() {
  return new Promise((resolve, reject) => {
    http.get("http://127.0.0.1:9333/json", (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        try {
          const list = JSON.parse(data);
          const page = list.find((t) => t.type === "page");
          if (!page) return reject(new Error("no page target"));
          resolve(page.webSocketDebuggerUrl);
        } catch (e) { reject(e); }
      });
    }).on("error", reject);
  });
}

(async () => {
  const expr = process.argv[2];
  if (!expr) { console.error("usage: node cdp-eval.js <expr>"); process.exit(2); }
  const url = await getTarget();
  const ws = new WebSocket(url);
  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  });
  await new Promise((r) => ws.addEventListener("open", r));
  const call = (method, params) => new Promise((resolve) => {
    const myId = ++id;
    pending.set(myId, resolve);
    ws.send(JSON.stringify({ id: myId, method, params }));
  });
  await call("Runtime.enable", {});
  const res = await call("Runtime.evaluate", {
    expression: expr,
    awaitPromise: true,
    returnByValue: true,
  });
  const r = res.result || {};
  if (r.exceptionDetails) {
    console.log("EXCEPTION:", JSON.stringify(r.exceptionDetails).slice(0, 800));
  } else {
    console.log("RESULT:", JSON.stringify(r.result ? r.result.value : null));
  }
  ws.close();
  process.exit(0);
})();
