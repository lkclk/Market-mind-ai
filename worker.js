export default {
  async fetch(request, env) {
    const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,POST,OPTIONS", "Access-Control-Allow-Headers": "Authorization,Content-Type" };
    if (request.method === "OPTIONS") return new Response(null, { headers: cors });
    const path = new URL(request.url).pathname;
    const auth = request.headers.get("Authorization") || "";
    const json = (data, status=200) => new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
    if (path === "/health") return json({ service: "MarketMind MT5 relay", status: "online", version: 1 });
    if (!env.SIGNALS || !env.MM_TOKEN || !env.EA_TOKEN) return json({ error: "Relay secrets or KV binding are not configured" }, 503);
    if (path === "/signal" && request.method === "POST") {
      if (auth !== "Bearer " + env.MM_TOKEN) return json({ error: "Unauthorized" }, 401);
      let s; try { s = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
      if (!s || !/^[A-Z]{3}\/([A-Z]{3})$/.test(s.symbol || "") || !["BUY","SELL"].includes(s.side) ||
          ![s.sl,s.tp].every(Number.isFinite) || !(s.sl > 0 && s.tp > 0) ||
          !(Number.isFinite(s.riskPercent) && s.riskPercent > 0 && s.riskPercent <= 1)) return json({ error: "Invalid signal; riskPercent must be >0 and <=1" }, 400);
      const now = Date.now();
      const item = { id: crypto.randomUUID(), symbol: s.symbol.replace("/",""), side: s.side, sl: s.sl, tp: s.tp, riskPercent: s.riskPercent, createdAt: now, expiresAt: now + 60000 };
      await env.SIGNALS.put("pending", JSON.stringify(item), { expirationTtl: 65 });
      return json({ accepted: true, id: item.id, expiresInSeconds: 60 });
    }
    if (path === "/next" && request.method === "GET") {
      if (auth !== "Bearer " + env.EA_TOKEN) return json({ error: "Unauthorized" }, 401);
      const raw = await env.SIGNALS.get("pending");
      if (!raw) return json({ signal: null });
      await env.SIGNALS.delete("pending");
      const item = JSON.parse(raw);
      if (item.expiresAt < Date.now()) return json({ signal: null });
      return json({ signal: item });
    }
    if (path === "/result" && request.method === "POST") {
      if (auth !== "Bearer " + env.EA_TOKEN) return json({ error: "Unauthorized" }, 401);
      let result; try { result = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
      await env.SIGNALS.put("last-result", JSON.stringify({ ...result, receivedAt: Date.now() }), { expirationTtl: 86400 });
      return json({ saved: true });
    }
    if (path === "/result" && request.method === "GET") {
      if (auth !== "Bearer " + env.MM_TOKEN) return json({ error: "Unauthorized" }, 401);
      return json({ result: await env.SIGNALS.get("last-result", "json") });
    }
    return json({ error: "Not found" }, 404);
  }
};