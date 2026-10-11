// Wordt aangeroepen door de database (trigger) bij een nieuwe boeking of een annulering.
const crypto = require("crypto");
const { sendMail, isPlaceholder, FRAN } = require("./_mail");

const safeEq = (a, b) => { a = Buffer.from(String(a || "")); b = Buffer.from(String(b || "")); return a.length === b.length && crypto.timingSafeEqual(a, b); };

module.exports = async (req, res) => {
  if (req.method !== "POST") { res.statusCode = 405; return res.end(); }
  if (!process.env.WEBHOOK_SECRET || !safeEq(req.headers["x-webhook-secret"], process.env.WEBHOOK_SECRET)) { res.statusCode = 401; return res.end("unauthorized"); }
  const p = typeof req.body === "string" ? JSON.parse(req.body || "{}") : (req.body || {});
  const b = p.record, old = p.old_record;
  if (!b || !b.id) { res.statusCode = 400; return res.end("no record"); }
  const sent = [], errors = [];
  const go = async (to, tpl) => { try { await sendMail(to, tpl, b); sent.push(tpl); } catch (e) { errors.push(tpl + ": " + e.message); } };
  const hasEmail = !isPlaceholder(b.customer_email);

  if (p.type === "INSERT" && b.status === "confirmed") {
    if (hasEmail) await go(b.customer_email, "confirm");
    if (b.source !== "admin") await go(FRAN, "franNew");
  } else if (p.type === "UPDATE" && b.status === "cancelled" && old && old.status !== "cancelled" && new Date(b.starts_at) > new Date()) {
    if (hasEmail) await go(b.customer_email, "cancelled");
    await go(FRAN, "franCancelled");
  }
  res.setHeader("Content-Type", "application/json");
  res.statusCode = errors.length && !sent.length ? 500 : 200;
  res.end(JSON.stringify({ sent, errors }));
};
