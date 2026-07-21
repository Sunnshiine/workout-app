#!/usr/bin/env node
// Throwaway smoke driver for issue #484: prove the touch half of the sighted
// loop (snapshot_ui / tap) works on the xcode-27 runner once the image ships
// SimulatorKit.framework. Deleted with the spike workflow when #484 closes.
import { spawn, execSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const ARTIFACT_DIR = process.env.ARTIFACT_DIR || "/tmp/simkit-artifacts";
mkdirSync(ARTIFACT_DIR, { recursive: true });

const server = spawn("npx", ["-y", "xcodebuildmcp@2.6.2", "mcp"], {
  env: {
    ...process.env,
    XCODEBUILDMCP_SENTRY_DISABLED: "true",
    XCODEBUILDMCP_HEADLESS_LAUNCH: "1",
    XCODEBUILDMCP_ENABLED_WORKFLOWS:
      "session-management,simulator,simulator-management,ui-automation",
  },
});
server.stderr.on("data", (d) => process.stderr.write(d));

let nextId = 1;
const pending = new Map();
let buf = "";
server.stdout.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i);
    buf = buf.slice(i + 1);
    if (!line.trim()) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    if (msg.id !== undefined && pending.has(msg.id)) {
      const resolve = pending.get(msg.id);
      pending.delete(msg.id);
      resolve(msg);
    }
  }
});

function rpc(method, params, timeoutMs = 120000) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, resolve);
    setTimeout(() => {
      if (pending.delete(id)) reject(new Error(`timeout after ${timeoutMs}ms: ${method}`));
    }, timeoutMs);
    server.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}

function textOf(msg) {
  return (msg.result?.content ?? [])
    .filter((p) => p.type === "text")
    .map((p) => p.text)
    .join("\n");
}

async function call(name, args, timeoutMs) {
  console.log(`\n### tool ${name} ${JSON.stringify(args)}`);
  let msg;
  try {
    msg = await rpc("tools/call", { name, arguments: args }, timeoutMs);
  } catch (e) {
    console.log(`ERROR ${e.message}`);
    return { ok: false, text: e.message };
  }
  const text = textOf(msg);
  const ok = !msg.error && !msg.result?.isError;
  console.log((ok ? "" : "ERROR\n") + (text || JSON.stringify(msg)).slice(0, 4000));
  return { ok, text };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const verdict = {};

await rpc("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "simkit-spike-484", version: "0" },
});
server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

const tools = (await rpc("tools/list", {})).result.tools.map((t) => t.name).sort();
console.log("\nTOOLS REGISTERED: " + tools.join(", "));
verdict.set_sim_appearance_registered = tools.includes("set_sim_appearance");
verdict.snapshot_ui_registered = tools.includes("snapshot_ui");
verdict.tap_registered = tools.includes("tap");

await call("boot_sim", { simulatorName: "iPhone 17 Pro" }, 300000);

const build = await call(
  "build_run_sim",
  {
    launchArgs: ["-UITEST_FIXTURE", "true", "-UITEST_SESSION", "true"],
    extraArgs: ["-skipPackagePluginValidation", "-skipMacroValidation"],
  },
  1500000,
);
verdict.build_run_sim = build.ok;
await sleep(8000);

function refsIn(text) {
  return [...text.matchAll(/"ref"\s*:\s*"([^"]+)"/g)].map((m) => m[1]);
}

let snap = await call("snapshot_ui", {});
verdict.snapshot_ui = snap.ok;
writeFileSync(join(ARTIFACT_DIR, "snapshot_ui-1.txt"), snap.text || "(empty)");

// Run 29842509047: headless snapshot_ui fails with "No translation object
// returned for simulator" — test whether Simulator.app supplies the bridge.
if (!snap.ok) {
  await call("open_sim", {});
  await sleep(15000);
  snap = await call("snapshot_ui", {});
  verdict.snapshot_ui_after_open_sim = snap.ok;
  writeFileSync(join(ARTIFACT_DIR, "snapshot_ui-after-open-sim.txt"), snap.text || "(empty)");
}
const refs = refsIn(snap.text || "");
console.log(`\nelementRefs found: ${refs.length}`);

async function grabScreenshot(label) {
  const shot = await call("screenshot", { returnFormat: "path" });
  const path = (shot.text.match(/\/[^\s'"]+\.(png|jpe?g)/) || [])[0];
  if (path && existsSync(path)) copyFileSync(path, join(ARTIFACT_DIR, `${label}.png`));
  return shot.ok;
}
verdict.screenshot = await grabScreenshot("light-before-tap");

if (refs.length > 0) {
  const tap = await call("tap", { elementRef: refs[0], postDelay: 1 });
  verdict.tap = tap.ok;
  const snap2 = await call("snapshot_ui", {});
  writeFileSync(join(ARTIFACT_DIR, "snapshot_ui-after-tap.txt"), snap2.text || "(empty)");
  await grabScreenshot("light-after-tap");
} else {
  verdict.tap = false;
  console.log("no elementRef in snapshot output — cannot exercise tap");
}

// Flake probe: the open flake question lives entirely in this touch half.
let flakeFailures = 0;
for (let i = 1; i <= 5; i++) {
  const s = await call("snapshot_ui", {});
  const r = refsIn(s.text || "");
  const t = r.length > 0 ? await call("tap", { elementRef: r[0], postDelay: 1 }) : { ok: false };
  if (!s.ok || !t.ok) flakeFailures++;
}
verdict.flake_failures_of_5 = flakeFailures;

// Dark appearance: prefer the MCP tool, fall back to simctl (VISUAL_LOOP step 3).
if (verdict.set_sim_appearance_registered) {
  const dark = await call("set_sim_appearance", { mode: "dark" });
  verdict.set_sim_appearance = dark.ok;
}
if (!verdict.set_sim_appearance) {
  try {
    execSync("xcrun simctl ui booted appearance dark", { stdio: "inherit" });
    verdict.simctl_dark_fallback = true;
  } catch (e) {
    verdict.simctl_dark_fallback = `failed: ${e.message}`;
  }
}
await sleep(3000);
await grabScreenshot("dark");

console.log("\nFINAL VERDICT " + JSON.stringify(verdict, null, 2));
writeFileSync(join(ARTIFACT_DIR, "verdict.json"), JSON.stringify(verdict, null, 2));
server.kill();
const touchHalfWorks = (verdict.snapshot_ui || verdict.snapshot_ui_after_open_sim) && verdict.tap;
console.log(touchHalfWorks ? "\nTOUCH HALF: WORKS" : "\nTOUCH HALF: STILL BROKEN");
process.exit(touchHalfWorks ? 0 : 1);
