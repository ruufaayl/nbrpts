// Officer-portal screenshot capture (Phase 7 smoke test).
// Signs in as aisha@nbrpts.demo, walks every /officer page, captures PNGs.
import { spawn } from "node:child_process";
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const EDGE = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";
const OUT  = "C:\\dev\\nbrpts\\deliverables\\screenshots";
const BASE = "http://localhost:3000";
const OFFI = { email: "aisha@nbrpts.demo", pwd: "demo1234" };

mkdirSync(OUT, { recursive: true });

const port = 9222 + Math.floor(Math.random() * 1000);
const userDataDir = `C:\\Users\\MR.Laptops\\AppData\\Local\\Temp\\nbrpts-officer-${Date.now()}`;
const edge = spawn(
  EDGE,
  [
    "--headless=new", "--disable-gpu", "--hide-scrollbars",
    "--no-first-run", "--no-default-browser-check",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    "--window-size=1440,900",
    "about:blank",
  ],
  { stdio: "ignore", detached: false },
);

process.on("exit", () => { try { edge.kill(); } catch {} });

async function getWsUrl() {
  for (let i = 0; i < 40; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const page = list.find(p => p.type === "page") || list[0];
      return page.webSocketDebuggerUrl;
    } catch { await sleep(150); }
  }
  throw new Error("Edge debug endpoint never became ready");
}
const wsUrl = await getWsUrl();

class CDP {
  constructor(ws) { this.ws = ws; this.id = 0; this.cbs = new Map(); this.events = []; }
  static async connect(url) {
    const { default: WS } = await import("ws");
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
  async waitFor(method, timeout = 15000) {
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
  try { await cdp.waitFor("Page.loadEventFired", 15000); } catch {}
  await sleep(1100);
}

async function snap(name, fullPage = false) {
  let clip;
  if (fullPage) {
    const layout = await cdp.send("Page.getLayoutMetrics");
    const c = layout.cssContentSize || layout.contentSize;
    clip = { x: 0, y: 0, width: 1440, height: Math.min(Math.ceil(c.height), 4500), scale: 1 };
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

async function getJson(expr) {
  const r = await cdp.send("Runtime.evaluate", { expression: expr, returnByValue: true });
  return r.result.value;
}

await go("/login");
await fill('input[type="email"]', OFFI.email);
await fill('input[type="password"]', OFFI.pwd);
await click('button[type="submit"]');
await sleep(2500);

await go("/officer");                  await snap("11_officer_dashboard", true);
await go("/officer/queue");            await snap("12_officer_queue", true);
await go("/officer/queue?status=flagged"); await snap("13_officer_queue_flagged", true);

// Drill into the first record from the queue
const firstBrn = await getJson(`document.querySelector('a[href^="/officer/record/"]')?.getAttribute('href')?.replace('/officer/record/', '')`);
const targetBrn = firstBrn || "BRN-2026-00010001";
await go("/officer/record/" + targetBrn);
await snap("14_officer_record_detail", true);

await go("/officer/bforms");           await snap("15_officer_bforms", true);
await go("/officer/search?q=Ayesha");  await snap("16_officer_search", true);
await go("/officer/stats");            await snap("17_officer_stats", true);

console.log("done");
process.exit(0);
