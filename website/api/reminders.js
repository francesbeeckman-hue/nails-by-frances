// Herinneringen: 24 uur en 1 uur voor de afspraak.
// Wordt elke 10 minuten aangeroepen door Supabase (pg_cron, met x-webhook-secret) en 1x per dag door Vercel Cron (fallback).
const { sendMail, sb, isPlaceholder } = require("./_mail");

const iso = ms => new Date(ms).toISOString();
const q = s => encodeURIComponent(s);

module.exports = async (req, res) => {
  const cron = (process.env.CRON_SECRET || "").trim(), hook = (process.env.WEBHOOK_SECRET || "").trim();
  const okCron = cron && req.headers.authorization === `Bearer ${cron}`;
  const okHook = hook && String(req.headers["x-webhook-secret"] || "").trim() === hook;
  if (!okCron && !okHook) { res.statusCode = 401; return res.end("unauthorized"); }

  const now = Date.now(), H = 3600e3;
  const out = { day: { sent: 0, skipped: 0 }, hour: { sent: 0, skipped: 0 }, errors: [] };
  const run = async (kind, col, from, to, minLead, tpl) => {
    const rows = await sb(`bookings?select=*&status=eq.confirmed&${col}=is.null&starts_at=gt.${q(iso(from))}&starts_at=lte.${q(iso(to))}&order=starts_at`);
    for (const b of rows) {
      const lead = new Date(b.starts_at) - new Date(b.created_at);
      // Geboekt kort van tevoren? Dan is de bevestiging net binnen: geen extra herinnering sturen.
      const skip = isPlaceholder(b.customer_email) || lead < minLead;
      try {
        if (!skip) await sendMail(b.customer_email, tpl, b);
        await sb(`bookings?id=eq.${b.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ [col]: new Date().toISOString() }) });
        skip ? out[kind].skipped++ : out[kind].sent++;
      } catch (e) { out.errors.push(`${kind} ${b.id}: ${e.message}`); }
    }
  };
  // Dag van tevoren: afspraak binnen 24 uur (maar niet al binnen 2 uur).
  await run("day", "reminder_sent_at", now + 2 * H, now + 24 * H, 26 * H, "reminder");
  // Uur van tevoren: afspraak binnen 65 minuten.
  try { await run("hour", "reminder_1h_sent_at", now, now + 65 * 60e3, 3 * H, "reminderHour"); }
  catch (e) { out.errors.push("hour: " + e.message); } // kolom bestaat nog niet (SQL 008 nog niet geplakt)
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(out));
};
