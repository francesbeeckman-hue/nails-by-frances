window.NBF = {
  url: "https://ewlpbnrlesizmrokzjnq.supabase.co",
  key: "sb_publishable_X0HJsQtvxneIBzf4npMS6Q_LY3qa8BC",
  tz: "Europe/Amsterdam"
};
window.db = window.supabase.createClient(NBF.url, NBF.key);
// ---- helpers ----
NBF.esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
NBF.euro = c => "€" + (c/100).toFixed(c % 100 ? 2 : 0).replace(".", ",");
NBF.dur = m => m >= 60 ? (Math.floor(m/60) + " u" + (m%60 ? " " + (m%60) + " min" : "")) : m + " min";
NBF.time = iso => new Intl.DateTimeFormat("nl-NL",{timeZone:NBF.tz,hour:"2-digit",minute:"2-digit"}).format(new Date(iso));
NBF.dateLong = iso => new Intl.DateTimeFormat("nl-NL",{timeZone:NBF.tz,weekday:"long",day:"numeric",month:"long",year:"numeric"}).format(new Date(iso));
NBF.ymd = d => { const p = new Intl.DateTimeFormat("en-CA",{timeZone:NBF.tz,year:"numeric",month:"2-digit",day:"2-digit"}).format(d); return p; };
// Amsterdam local date+time -> ISO (UTC)
NBF.toISO = (ymd, hm = "00:00") => {
  const [y,m,d] = ymd.split("-").map(Number), [h,mi] = hm.split(":").map(Number);
  let t = Date.UTC(y, m-1, d, h, mi);
  for (let i = 0; i < 2; i++) {
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB",{timeZone:NBF.tz,hourCycle:"h23",year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit"}).formatToParts(new Date(t)).map(x=>[x.type,x.value]));
    const shown = Date.UTC(+p.year, +p.month-1, +p.day, +p.hour, +p.minute);
    t += Date.UTC(y, m-1, d, h, mi) - shown;
  }
  return new Date(t).toISOString();
};
NBF.addDays = (ymd, n) => { const [y,m,d] = ymd.split("-").map(Number); const t = new Date(Date.UTC(y,m-1,d+n)); return t.toISOString().slice(0,10); };
NBF.errMsg = e => (e && (e.message || e.error_description)) || "Er ging iets mis. Probeer het opnieuw.";
