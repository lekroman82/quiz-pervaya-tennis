const SUPABASE_URL = 'https://cwjhdlzsgcwzpbpyrprm.supabase.co';
const SCHOOL_ID = '11111111-1111-1111-1111-111111111111';

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  const key = process.env.SUPABASE_SERVICE_KEY;
  if (!key) {
    return res.status(500).json({ error: 'SUPABASE_SERVICE_KEY not set' });
  }

  const days = parseInt(req.query.days) || 0;
  let url = `${SUPABASE_URL}/rest/v1/events?select=type,session_id,payload,utm_source,utm_medium,utm_campaign,created_at&school_id=eq.${SCHOOL_ID}&order=created_at.desc&limit=50000`;
  if (days > 0) {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - days);
    url += `&created_at=gte.${cutoff.toISOString()}`;
  }

  const response = await fetch(url, {
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    const err = await response.text();
    return res.status(response.status).json({ error: err });
  }

  const data = await response.json();
  return res.status(200).json(data);
}
