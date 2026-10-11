// Gedeelde helpers voor e-mails (Resend) en Supabase (server-side). Bestanden met _ worden geen eigen endpoint.
const SUPABASE_URL = "https://bfzuycyluaiepsgiainq.supabase.co";
const SITE = (process.env.SITE_URL || "https://www.nailbarbyfran.nl").replace(/\/$/, "");
const FROM = process.env.MAIL_FROM || "Nail Bar by Fran <afspraken@nailbarbyfran.nl>";
const FRAN = process.env.FRAN_EMAIL || "nails.byfran@outlook.com";
const TZ = "Europe/Amsterdam";
const ADDR = "Magdalena van Weerdenburglaan 36, 1934 GL Egmond aan den Hoef";
const MAPS = "https://www.google.com/maps/search/?api=1&query=Magdalena+van+Weerdenburglaan+36+1934GL+Egmond+aan+den+Hoef";

const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const euro = c => "€" + (c / 100).toFixed(c % 100 ? 2 : 0).replace(".", ",");
const dateLow = iso => new Intl.DateTimeFormat("nl-NL", { timeZone: TZ, weekday: "long", day: "numeric", month: "long" }).format(new Date(iso));
const dateLong = iso => { const s = dateLow(iso); return s.charAt(0).toUpperCase() + s.slice(1); };
const time = iso => new Intl.DateTimeFormat("nl-NL", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
const svcName = b => b.service_name + (b.extras ? " + " + String(b.extras).split(", ").join(" + ") : "");
const isPlaceholder = e => !e || /@nailsbyfrances\.nl$|@nailbarbyfran\.nl$/i.test(e);
const cancelUrl = b => `${SITE}/annuleren?t=${b.cancel_token}`;

function ics(b) {
  const f = iso => new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d+/, "");
  const e = s => String(s).replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
  return ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Nail Bar by Fran//NL", "METHOD:PUBLISH", "BEGIN:VEVENT",
    `UID:${b.id}@nailbarbyfran`, `DTSTAMP:${f(new Date().toISOString())}`, `DTSTART:${f(b.starts_at)}`, `DTEND:${f(b.ends_at)}`,
    `SUMMARY:${e(svcName(b) + " – Nail Bar by Fran")}`, `LOCATION:${e(ADDR)}`,
    `DESCRIPTION:${e("Annuleren of verzetten? " + cancelUrl(b))}`,
    "BEGIN:VALARM", "TRIGGER:-PT2H", "ACTION:DISPLAY", "DESCRIPTION:Nail Bar by Fran", "END:VALARM",
    "END:VEVENT", "END:VCALENDAR"].join("\r\n");
}

function layout(title, inner) {
  return `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${esc(title)}</title></head>
<body style="margin:0;background:#F7F4EF;font-family:Helvetica,Arial,sans-serif;color:#686561">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F7F4EF;padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:18px;overflow:hidden">
<tr><td align="center" style="padding:30px 24px 10px"><img src="${SITE}/logo.png" alt="Nail Bar by Fran" width="150" style="display:block;width:150px;height:auto"></td></tr>
<tr><td style="padding:10px 32px 30px;font-size:15px;line-height:1.6">${inner}</td></tr>
<tr><td style="background:#EFE8DE;padding:18px 32px;font-size:12px;line-height:1.6;color:#686561">
Nail Bar by Fran · <a href="${MAPS}" style="color:#4E3606">${ADDR}</a><br>
<a href="https://wa.me/31648886908" style="color:#4E3606">WhatsApp</a> · <a href="https://instagram.com/nailbarbyfran" style="color:#4E3606">Instagram</a> · <a href="${SITE}/voorwaarden" style="color:#4E3606">Voorwaarden</a> · <a href="${SITE}/privacy" style="color:#4E3606">Privacy</a>
</td></tr></table></td></tr></table></body></html>`;
}
const h1 = t => `<h1 style="font-size:22px;color:#4A4744;font-weight:600;margin:6px 0 14px">${t}</h1>`;
const btn = (href, label) => `<a href="${href}" style="display:inline-block;background:#4E3606;color:#ffffff;text-decoration:none;padding:12px 24px;border-radius:999px;font-size:13px;letter-spacing:.08em;text-transform:uppercase">${label}</a>`;
const card = b => `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F7F4EF;border-radius:14px;margin:16px 0">
<tr><td style="padding:16px 18px;font-size:15px;line-height:1.6;color:#4A4744">
<b>${esc(svcName(b))}</b><br>${esc(dateLong(b.starts_at))} · ${time(b.starts_at)}–${time(b.ends_at)}<br>
<span style="color:#686561">${euro(b.price_cents)} · je betaalt na afloop met pin of contant</span></td></tr></table>`;
const first = n => esc(String(n || "").trim().split(/\s+/)[0]);

const templates = {
  confirm: b => ({
    subject: `Je afspraak is bevestigd · ${dateLow(b.starts_at)} ${time(b.starts_at)}`,
    html: layout("Afspraak bevestigd", `${h1(`Tot snel, ${first(b.customer_name)}!`)}<p style="margin:0">Je afspraak bij Nail Bar by Fran staat vast.</p>${card(b)}
<p style="margin:0 0 6px"><b style="color:#4A4744">Adres</b><br><a href="${MAPS}" style="color:#4E3606">${ADDR}</a></p>
<p style="margin:16px 0">In de bijlage zit je afspraak voor je agenda.</p>
<p style="margin:0 0 20px;font-size:13px">Kun je niet? Annuleer of verzet <b>tot 24 uur van tevoren</b> kosteloos.</p>${btn(cancelUrl(b), "Afspraak annuleren")}`),
    attach: true
  }),
  reminder: b => ({
    subject: `Herinnering: morgen om ${time(b.starts_at)} bij Nail Bar by Fran`,
    html: layout("Herinnering", `${h1(`Tot morgen, ${first(b.customer_name)}!`)}<p style="margin:0">Een kleine herinnering aan je afspraak.</p>${card(b)}
<p style="margin:0 0 16px"><b style="color:#4A4744">Adres</b><br><a href="${MAPS}" style="color:#4E3606">${ADDR}</a></p>
<p style="margin:0;font-size:13px">Lukt het toch niet? Laat het zo snel mogelijk weten via <a href="https://wa.me/31648886908" style="color:#4E3606">WhatsApp</a>.</p>`)
  }),
  cancelled: b => ({
    subject: `Je afspraak van ${dateLow(b.starts_at)} is geannuleerd`,
    html: layout("Afspraak geannuleerd", `${h1(`Je afspraak is geannuleerd`)}<p style="margin:0">Hoi ${first(b.customer_name)}, deze afspraak gaat niet door:</p>${card(b)}
<p style="margin:0 0 20px">Wil je een nieuw moment plannen? Dat kan altijd online.</p>${btn(SITE + "/#boeken", "Nieuwe afspraak maken")}`)
  }),
  franNew: b => ({
    subject: `Nieuwe afspraak: ${b.customer_name} · ${dateLow(b.starts_at)} ${time(b.starts_at)}`,
    html: layout("Nieuwe afspraak", `${h1("Nieuwe afspraak 🎉")}${card(b)}
<p style="margin:0 0 16px"><b style="color:#4A4744">${esc(b.customer_name)}</b><br>Tel: <a href="tel:${esc(b.customer_phone)}" style="color:#4E3606">${esc(b.customer_phone)}</a>${isPlaceholder(b.customer_email) ? "" : `<br>E-mail: ${esc(b.customer_email)}`}${b.note ? `<br>Opmerking: “${esc(b.note)}”` : ""}</p>${btn("https://beheer.nailbarbyfran.nl", "Open agenda")}`)
  }),
  franCancelled: b => ({
    subject: `Geannuleerd: ${b.customer_name} · ${dateLow(b.starts_at)} ${time(b.starts_at)}`,
    html: layout("Afspraak geannuleerd", `${h1("Afspraak geannuleerd")}<p style="margin:0">${esc(b.customer_name)} heeft deze afspraak geannuleerd. Het tijdslot is weer vrij.</p>${card(b)}`)
  })
};

async function sendMail(to, tpl, b) {
  const key = process.env.RESEND_API_KEY;
  if (!key) throw new Error("RESEND_API_KEY ontbreekt");
  const t = templates[tpl](b);
  const body = { from: FROM, to: [to], subject: t.subject, html: t.html, reply_to: FRAN };
  if (t.attach) body.attachments = [{ filename: "afspraak-nailbarbyfran.ics", content: Buffer.from(ics(b)).toString("base64") }];
  const r = await fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`Resend ${r.status}: ${await r.text()}`);
  return r.json();
}

async function sb(path, opts = {}) {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY ontbreekt");
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...opts, headers: { apikey: key, ...(key.startsWith("eyJ") ? { Authorization: `Bearer ${key}` } : {}), "Content-Type": "application/json", ...(opts.headers || {}) } });
  if (!r.ok) throw new Error(`Supabase ${r.status}: ${await r.text()}`);
  return r.status === 204 ? null : r.json();
}

// Amsterdam-datum (YYYY-MM-DD + offset in dagen) -> ISO-tijdstip van middernacht in Amsterdam
function amsMidnightISO(daysAhead) {
  const ymd = new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  const [y, m, d] = ymd.split("-").map(Number);
  const target = Date.UTC(y, m - 1, d + daysAhead, 0, 0);
  let t = target;
  for (let i = 0; i < 2; i++) {
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).formatToParts(new Date(t)).map(x => [x.type, x.value]));
    t += target - Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute);
  }
  return new Date(t).toISOString();
}

module.exports = { sendMail, sb, isPlaceholder, amsMidnightISO, FRAN, templates };
