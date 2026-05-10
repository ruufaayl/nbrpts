// Capture homepage at three breakpoints — mobile / tablet / desktop.
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import http from "node:http";
import WebSocket from "ws";

const URL = "http://localhost:3000/";
const SCREENSHOT_DIR = "deliverables/screenshots";
const EDGE = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const PORT = 9377;

await fs.mkdir(SCREENSHOT_DIR, { recursive: true });

const userDataDir = `C:/Users/MR.Laptops/AppData/Local/Temp/nbrpts-resp-${Date.now()}`;
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
const ws = new WebSocket(targets.find(t => t.type === "page").webSocketDebuggerUrl);
let id = 0; const pending = new Map();
ws.on("message", (data) => {
  const msg = JSON.parse(data.toString());
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id); pending.delete(msg.id);
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

const captureAt = async (label, w, h) => {
  await send("Emulation.setDeviceMetricsOverride", {
    width: w, height: h, deviceScaleFactor: 1, mobile: w < 768,
  });
  await send("Page.navigate", { url: URL });
  await new Promise(r => setTimeout(r, 2200));
  await send("Runtime.evaluate", {
    expression: `
      document.querySelectorAll('.curtain').forEach(el => el.classList.add('out'));
      document.querySelectorAll('.reveal').forEach(el => el.classList.add('in'));
      document.querySelectorAll('.pipeline').forEach(el => el.classList.add('in'));
      document.querySelectorAll('.word-in, .split-letter').forEach(el => {
        el.style.opacity = '1'; el.style.transform = 'none';
      });
      document.querySelectorAll('.cursor-dot').forEach(el => el.style.display = 'none');
      const targets = ['13','8','20+','19'];
      let i=0;
      document.querySelectorAll('section .font-display').forEach(el => {
        if (i < targets.length && /^\\d+\\+?$/.test(el.textContent.trim())) {
          el.textContent = targets[i++];
        }
      });
      window.requestAnimationFrame=()=>0;
    `,
  });
  await new Promise(r => setTimeout(r, 500));
  const r = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
  const path = `${SCREENSHOT_DIR}/${label}.png`;
  await fs.writeFile(path, Buffer.from(r.data, "base64"));
  console.log(`✓ ${label} (${w}x${h})`);
};

await captureAt("00_home_mobile",  390,  844);   // iPhone 14
await captureAt("00_home_tablet",  820, 1180);   // iPad
await captureAt("00_home_desktop", 1440, 900);   // desktop

ws.close();
process.exit(0);
