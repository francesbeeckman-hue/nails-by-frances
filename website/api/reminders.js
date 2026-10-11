// Dagelijkse herinneringen (Vercel Cron, 1x per dag): mailt klanten met een afspraak morgen.
const { sendMail, sb, isPlaceholder, amsMidnightISO } = require("./_mail");

module.exports = async (req, res) => {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.authorization !== `Bearer ${secret}`) { res.statusCode = 401; return res.end("unauthorized"); }
  const from = amsMidnightISO(1), to = amsMidnightISO(2);
  const rows = await sb(`bookings?select=*&status=eq.confirmed&reminder_sent_at=is.null&starts_at=gte.${encodeURIComponent(from)}&starts_at=lt.${encodeURIComponent(to)}&order=starts_at`);
  const out = { day: from, total: rows.length, sent: 0, skipped: 0, errors: [] };
  for (const b of rows) {
    if (isPlaceholder(b.customer_email)) { out.skipped++; continue; }
    try {
      await sendMail(b.customer_email, "reminder", b);
      await sb(`bookings?id=eq.${b.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ reminder_sent_at: new Date().toISOString() }) });
      out.sent++;
    } catch (e) { out.errors.push(e.message); }
  }
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(out));
};
