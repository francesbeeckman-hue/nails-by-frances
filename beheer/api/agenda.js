// Agenda-feed (iCal) voor Apple Agenda / Google Agenda.
// Gebruik: https://<beheer-domein>/api/agenda?token=<geheime token uit het beheer>
const URL = "https://bfzuycyluaiepsgiainq.supabase.co";
const KEY = "sb_publishable_LxwGn6uPu-6mSiTjEfH4AA_-xCdkrqd";

module.exports = async (req, res) => {
  const token = String((req.query && req.query.token) || "").replace(/\.ics$/i, "");
  if (!/^[0-9a-f-]{36}$/i.test(token)) { res.statusCode = 400; return res.end("Ongeldige agenda-link"); }
  try {
    const r = await fetch(`${URL}/rest/v1/rpc/calendar_feed`, {
      method: "POST",
      headers: { apikey: KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ p_token: token })
    });
    if (!r.ok) { res.statusCode = 403; return res.end("Ongeldige agenda-link"); }
    const ics = await r.json();
    res.setHeader("Content-Type", "text/calendar; charset=utf-8");
    res.setHeader("Content-Disposition", 'inline; filename="nail-bar-by-fran.ics"');
    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.end(ics);
  } catch (e) {
    res.statusCode = 502; res.end("Agenda tijdelijk niet beschikbaar");
  }
};
