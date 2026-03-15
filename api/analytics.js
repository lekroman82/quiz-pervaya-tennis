const SUPABASE_URL = 'https://cwjhdlzsgcwzpbpyrprm.supabase.co';
const SCHOOL_ID = '11111111-1111-1111-1111-111111111111';

async function sbFetch(url, key) {
  const r = await fetch(url, {
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
  });
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  const key = process.env.SUPABASE_SERVICE_KEY;
  if (!key) return res.status(500).json({ error: 'SUPABASE_SERVICE_KEY not set' });

  const days = parseInt(req.query.days) || 0;
  const cutoff = days > 0 ? (() => { const d = new Date(); d.setDate(d.getDate() - days); return d.toISOString(); })() : null;

  let eventsUrl = `${SUPABASE_URL}/rest/v1/events?select=type,session_id,payload,utm_source,utm_medium,utm_campaign,created_at&school_id=eq.${SCHOOL_ID}&order=created_at.desc&limit=50000`;
  if (cutoff) eventsUrl += `&created_at=gte.${cutoff}`;

  let leadsUrl = `${SUPABASE_URL}/rest/v1/leads?select=id,name,phone,segment,created_at&school_id=eq.${SCHOOL_ID}&order=created_at.desc&limit=500`;
  if (cutoff) leadsUrl += `&created_at=gte.${cutoff}`;

  try {
    const [events, leads] = await Promise.all([sbFetch(eventsUrl, key), sbFetch(leadsUrl, key)]);
    return res.status(200).json({ events, leads });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}
