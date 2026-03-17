export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const token = process.env.TG_BOT_TOKEN;
  const chatId = process.env.TG_CHAT_ID;

  if (!token || !chatId) {
    return res.status(500).json({ error: 'TG_BOT_TOKEN or TG_CHAT_ID not set' });
  }

  const { name, phone, answers, segment, utm_source, utm_medium, utm_campaign } = req.body || {};

  if (!name || !phone) {
    return res.status(400).json({ error: 'name and phone are required' });
  }

  // Человеко-читаемые лейблы
  const L = {
    1: { expensive: 'Казалось дорого', others_said: 'Кто-то говорил так', hesitant: 'Не решался попробовать', never: 'Просто не пробовал' },
    2: { saw: 'Увидел как играют', friends: 'Друзья зовут', child: 'Ищу для ребёнка', dream: 'Давно мечтал' },
    3: { self: 'Для себя', child: 'Для ребёнка', teen: 'Для подростка', family: 'Для семьи' },
    4: { price: 'Боюсь что дорого', too_late: 'Думаю что поздно', shy: 'Стесняюсь', nothing: 'Ничего не останавливает', will_quit: 'Ребёнок бросит', uncomfortable: 'Не в своей тарелке', phone: 'Сидит в телефоне', quit_before: 'Бросал другие секции' }
  };

  const lb = (q, v) => (L[q] && L[q][v]) || v || '—';

  const a = answers || {};
  const utm = [utm_source, utm_medium, utm_campaign].filter(Boolean).join(' / ');

  const text =
    `🎾 *Новый лид с квиза!*\n\n` +
    `👤 *Имя:* ${name}\n` +
    `📞 *Телефон:* ${phone}\n` +
    `🎯 *Сегмент:* ${lb(3, segment)}\n\n` +
    `📋 *Ответы:*\n` +
    `1. ${lb(1, a[1])}\n` +
    `2. ${lb(2, a[2])}\n` +
    `3. ${lb(3, a[3])}\n` +
    `4. ${lb(4, a[4])}\n` +
    (utm ? `\n📊 *UTM:* ${utm}` : '');

  try {
    const r = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text: text,
        parse_mode: 'Markdown'
      })
    });

    const data = await r.json();

    if (!data.ok) {
      return res.status(500).json({ error: data.description });
    }

    return res.status(200).json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}
