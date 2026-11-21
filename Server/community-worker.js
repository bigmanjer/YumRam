// YUMRAM results server (Cloudflare Worker + Workers KV). Free tier is enough.
// Receives opt-in game benchmark results from YUMRAM (POST /submit) and lets the maintainer export them
// (GET /export with the secret token). Deploy steps: Docs/COMMUNITY.md.
//
// Privacy: stores only the JSON YUMRAM showed the user. The client IP is never stored; it is only used,
// hashed with a daily salt, to limit submissions to 5 per address per day.
//
// Bindings: KV namespace "RESULTS"; secret "EXPORT_TOKEN"; variable "DAILY_SALT" (any random string).

const MAX_BYTES = 16384;
const LEVELS = ["Off", "Gentle", "Balanced", "Strong"];

function bad(msg, status = 400) { return new Response(JSON.stringify({ ok: false, error: msg }), { status, headers: { "content-type": "application/json" } }); }

function validate(p) {
  if (!p || p.Schema !== 1 || p.Kind !== "yumram-game-benchmark") return "wrong format";
  const m = p.Machine || {};
  if (typeof m.Cpu !== "string" || !m.Cpu.trim() || m.Cpu.length > 120) return "cpu";
  if (!(m.Threads >= 1 && m.Threads <= 512 && m.Cores >= 1 && m.Cores <= m.Threads)) return "cores";
  const rs = Array.isArray(p.Results) ? p.Results : [];
  if (rs.length < 1 || rs.length > 40) return "results";
  for (const r of rs) {
    if (!["Light", "Medium", "Heavy"].includes(r.GameClass)) return "class";
    if (!["Half", "Saturating", "Bursty"].includes(r.Load)) return "load";
    for (const lv of LEVELS) { const v = r.Low1 && r.Low1[lv]; if (!(v > 0 && v <= 5000)) return "fps"; }
  }
  // Only these keys are kept - anything else a modified client might add is dropped.
  return null;
}

function clean(p) {
  const m = p.Machine;
  return {
    Schema: 1, Kind: p.Kind, App: String(p.App || "").slice(0, 20), Day: new Date().toISOString().slice(0, 10),
    Machine: { Cpu: m.Cpu.trim(), CpuKey: String(m.CpuKey || m.Cpu).toLowerCase().slice(0, 120), Cores: m.Cores, Threads: m.Threads, Hybrid: !!m.Hybrid, CacheGroups: m.CacheGroups | 0, Laptop: !!m.Laptop, Windows: String(m.Windows || "").slice(0, 40) },
    Results: p.Results.map(r => ({ GameClass: r.GameClass, Game: String(r.Game || "").slice(0, 20), Load: r.Load, GameCpuShare: +r.GameCpuShare || 0,
      Low1: Object.fromEntries(LEVELS.map(l => [l, +r.Low1[l]])), Avg: r.Avg ? Object.fromEntries(LEVELS.map(l => [l, +r.Avg[l] || 0])) : null }))
  };
}

async function sha256(text) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, "0")).join("");
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method === "POST" && url.pathname === "/submit") {
      const body = await req.text();
      if (body.length > MAX_BYTES) return bad("too large", 413);
      let p; try { p = JSON.parse(body); } catch { return bad("not json"); }
      const err = validate(p); if (err) return bad(err);
      const day = new Date().toISOString().slice(0, 10);
      const who = await sha256((req.headers.get("cf-connecting-ip") || "") + day + (env.DAILY_SALT || ""));
      const rlKey = `rl:${day}:${who}`;
      const n = parseInt((await env.RESULTS.get(rlKey)) || "0", 10);
      if (n >= 5) return bad("daily limit reached", 429);
      await env.RESULTS.put(rlKey, String(n + 1), { expirationTtl: 172800 });
      await env.RESULTS.put(`sub:${day}:${crypto.randomUUID()}`, JSON.stringify(clean(p)));
      return new Response(JSON.stringify({ ok: true }), { headers: { "content-type": "application/json" } });
    }
    if (req.method === "GET" && url.pathname === "/export") {
      if (!env.EXPORT_TOKEN || url.searchParams.get("token") !== env.EXPORT_TOKEN) return bad("forbidden", 403);
      const out = []; let cursor;
      do {
        const page = await env.RESULTS.list({ prefix: "sub:", cursor });
        for (const k of page.keys) { const v = await env.RESULTS.get(k.name); if (v) out.push(JSON.parse(v)); }
        cursor = page.list_complete ? undefined : page.cursor;
      } while (cursor);
      return new Response(JSON.stringify(out), { headers: { "content-type": "application/json" } });
    }
    return new Response("YUMRAM results server", { status: 200 });
  }
};
