// Capture /ai-engine screenshots — anonymous (page is public).
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import http from "node:http";
import WebSocket from "ws";

const URL = "http://localhost:3000";
const SCREENSHOT_DIR = "deliverables/screenshots";
const EDGE = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const PORT = 9355;

await fs.mkdir(SCREENSHOT_DIR, { recursive: true });

const userDataDir = `C:/Users/MR.Laptops/AppData/Local/Temp/nbrpts-aieng-${Date.now()}`;
const edge = spawn(EDGE, [
  "--headless=new", "--disable-gpu", "--hide-scrollbars",
  "--no-first-run", `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${userDataDir}`, "--window-size=1440,900",
  "about:blank",
], { detached: true, stdio: "ignore" });
edge.unref();

await new Promise(r => setTimeout(r, 1500));

const targets = await new Promise((resolve, reject) => {
  http.get(`http://127.0.0.1:${PORT}/json`, (res) => {
    let buf = ""; res.on("data", c => buf += c); res.on("end", () => resolve(JSON.parse(buf)));
  }).on("error", reject);
});
const pageTarget = targets.find(t => t.type === "page");
const ws = new WebSocket(pageTarget.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
ws.on("message", (data) => {
  const msg = JSON.parse(data.toString());
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
  }
});
await new Promise(r => ws.once("open", r));
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const myId = ++id;
    pending.set(myId, { resolve, reject });
    ws.send(JSON.stringify({ id: myId, method, params }));
  });

await send("Page.enable");
await send("Runtime.enable");
await send("Emulation.setDeviceMetricsOverride", {
  width: 1440, height: 900, deviceScaleFactor: 1, mobile: false,
});

const goto = async (url) => {
  await send("Page.navigate", { url });
  await new Promise(r => setTimeout(r, 1500));
  // wait until ready
  for (let i = 0; i < 20; i++) {
    const r = await send("Runtime.evaluate", {
      expression: "(() => { return document.readyState === 'complete' && document.body.innerText.length > 50 })()",
      returnByValue: true,
    });
    if (r.result?.value) return;
    await new Promise(r => setTimeout(r, 200));
  }
};

const snap = async (filename) => {
  // disable animations + RAF for stable capture
  await send("Runtime.evaluate", {
    expression: "document.querySelectorAll('*').forEach(el=>{try{el.style.animation='none';el.style.transition='none'}catch(e){}}); window.requestAnimationFrame=()=>0;",
  });
  await new Promise(r => setTimeout(r, 250));
  const r = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
  const path = `${SCREENSHOT_DIR}/${filename}`;
  await fs.writeFile(path, Buffer.from(r.data, "base64"));
  console.log(`✓ ${filename}`);
};

console.log("→ landing"); await goto(URL + "/");          await snap("00_landing_with_pillars.png");
console.log("→ /ai-engine"); await goto(URL + "/ai-engine"); await snap("18_ai_engine.png");

ws.close();
console.log("done");
process.exit(0);
