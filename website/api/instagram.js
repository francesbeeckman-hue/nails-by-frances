// Haalt de Instagram-feed van @nailbarbyfran op via Behold en bewaart hem 6 uur in de Vercel-cache,
// zodat het gratis Behold-plan (1.200 weergaven/maand) niet opraakt.
const FEED = "https://feeds.behold.so/CVi0OI84mYnBTNgomVNm";

module.exports = async (req, res) => {
  try {
    const r = await fetch(FEED, { headers: { accept: "application/json" } });
    if (!r.ok) throw new Error("feed " + r.status);
    const d = await r.json();
    const posts = (d.posts || [])
      .filter(p => p.visibility !== "hidden")
      .slice(0, 6)
      .map(p => ({
        url: p.permalink,
        img: (p.sizes && p.sizes.medium && p.sizes.medium.mediaUrl) || p.thumbnailUrl || p.mediaUrl,
        alt: (p.prunedCaption || p.caption || "Instagram-post van @nailbarbyfran").split("\n")[0].slice(0, 120),
        video: p.mediaType === "VIDEO"
      }));
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.setHeader("Cache-Control", "public, s-maxage=21600, stale-while-revalidate=86400");
    res.end(JSON.stringify({ posts }));
  } catch (e) {
    res.statusCode = 502;
    res.setHeader("Cache-Control", "public, s-maxage=300");
    res.end(JSON.stringify({ posts: [] }));
  }
};
