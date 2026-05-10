// Drive headless Edge via the Chrome DevTools Protocol to capture
// authenticated screenshots of every NBRPTS page for the report.
//
// Why CDP and not Playwright? Playwright would be ~150 MB to download.
// Edge is already installed. CDP gives us cookies + screenshots in <30 lines.
//
// Run: pnpm dev (in another terminal) then `node scripts/capture-screenshots.mjs`.
import { spawn } from "node:child_process";
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const EDGE = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";
const OUT  = "C:\\dev\\nbrpts\\deliverables\\screenshots";
const BASE = "http://localhost:3000";
const HOSP = { email: "aku@nbrpts.demo",   pwd: "demo1234" };
const OFFI = { email: "aisha@nbrpts.demo", pwd: "demo1234" };

mkdirSync(OUT, { recursive: true });

// Spawn Edge with remote debugging
const port = 9222 + Math.floor(Math.random() * 1000);
const userDataDir = `C:\\Users\\MR.Laptops\\AppData\\Local\\Temp\\nbrpts-edge-${Date.now()}`;
const edge = spawn(
  EDGE,
  [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    "--no-first-run",
    "--no-default-browser-check",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    "--window-size=1440,900",
    "about:blank",
  ],
  { stdio: "ignore", detached: false }
);

process.on("exit", () => { try { edge.kill(); } catch {} });

// Wait for the debug endpoint
async function getWsUrl() {
  for (let i = 0; i < 40; i++) {
    try {
      const r  = await fetch(`http://127.0.0.1:${port}/json/version`);
      const j  = await r.json();
      const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const page = list.find(p => p.type === "page") || list[0];
      return page.webSocketDebuggerUrl;
    } catch { await sleep(150); }
  }
  throw new Error("Edge debug endpoint never became ready");
}
const wsUrl = await getWsUrl();
console.log("CDP up at", wsUrl);

// Tiny CDP client
class CDP {
  constructor(ws) { this.ws = ws; this.id = 0; this.cbs = new Map(); this.events = []; }
  static async connect(url) {
    const { default: WS } = await import("ws").catch(async () => {
      const { WebSocket } = await import("undici");
      return { default: WebSocket };
    });
    const ws = new WS(url);
    await new Promise((res, rej) => { ws.on("open", res); ws.on("error", rej); });
    const c = new CDP(ws);
    ws.on("message", (raw) => {
      const m = JSON.parse(raw.toString());
      if (m.id && c.cbs.has(m.id)) { c.cbs.get(m.id)(m); c.cbs.delete(m.id); }
      else if (m.method) { c.events.push(m); }
    });
    return c;
  }
  send(method, params = {}) {
    const id = ++this.id;
    return new Promise((res, rej) => {
      this.cbs.set(id, (m) => m.error ? rej(new Error(m.error.message)) : res(m.result));
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  async waitFor(method, timeout = 10000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const idx = this.events.findIndex(e => e.method === method);
      if (idx >= 0) return this.events.splice(idx, 1)[0].params;
      await sleep(50);
    }
    throw new Error(`Timed out waiting for ${method}`);
  }
}

const cdp = await CDP.connect(wsUrl);
await cdp.send("Page.enable");
await cdp.send("DOM.enable");
await cdp.send("Runtime.enable");
await cdp.send("Network.enable");

async function go(path) {
  console.log("→", path);
  await cdp.send("Page.navigate", { url: BASE + path });
  // wait for load + a small settle delay so framer-motion finishes
  try { await cdp.waitFor("Page.loadEventFired", 15000); } catch {}
  await sleep(900);
}

async function snap(name, fullPage = false) {
  let clip;
  if (fullPage) {
    const layout = await cdp.send("Page.getLayoutMetrics");
    const c = layout.cssContentSize || layout.contentSize;
    clip = { x: 0, y: 0, width: 1440, height: Math.min(Math.ceil(c.height), 4000), scale: 1 };
  }
  const { data } = await cdp.send("Page.captureScreenshot", {
    format: "png",
    captureBeyondViewport: !!fullPage,
    clip,
  });
  const file = join(OUT, name + ".png");
  writeFileSync(file, Buffer.from(data, "base64"));
  console.log("   ✓", name + ".png");
}

async function fill(sel, value) {
  const r = await cdp.send("Runtime.evaluate", {
    expression: `(() => { const el = document.querySelector(${JSON.stringify(sel)}); if(!el) return false;
      const setter = Object.getOwnPropertyDescriptor(el.__proto__, 'value').set;
      setter.call(el, ${JSON.stringify(value)});
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true; })()`,
  });
  if (!r.result.value) throw new Error("Could not fill " + sel);
}

async function click(sel) {
  await cdp.send("Runtime.evaluate", {
    expression: `document.querySelector(${JSON.stringify(sel)}).click()`,
  });
}

async function login(creds) {
  await go("/login");
  await fill('input[type="email"]', creds.email);
  await fill('input[type="password"]', creds.pwd);
  await click('button[type="submit"]');
  await sleep(2500);
}

// ---------- public anonymous shots ----------
await go("/");          await snap("01_landing", true);
await go("/dev");       await snap("02_dev_query_feed", true);
await go("/dev/schema");await snap("03_dev_er_diagram");
await go("/dev/triggers"); await snap("04_dev_trigger_lab", true);
await go("/login");     await snap("05_login_page");

// ---------- hospital ----------
await login(HOSP);
await go("/hospital");                  await snap("06_hospital_dashboard", true);
await go("/hospital/submissions");      await snap("07_hospital_submissions", true);
await go("/hospital/submit");           await snap("08_hospital_submit_step1");
// Walk one step of the form to capture the multi-step UX
await sleep(500);
await go("/hospital/device");           await snap("09_hospital_device_simulator", true);

// ---------- officer ----------
// Sign out via a server action navigation, then officer login
await go("/login");
await login(OFFI);
await go("/dev");                       await snap("10_officer_dev_view", true);

console.log("done");
process.exit(0);
