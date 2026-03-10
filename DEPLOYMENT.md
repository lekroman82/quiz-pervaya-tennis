# Деплой квиза «Первая» — пошаговая инструкция

## Что деплоится

Один файл — `index.html`. Всё остальное (`.md`, `.claude/`, `supabase/`) исключено из деплоя через `.vercelignore`.

## Архитектура

```
Пользователь → Vercel (index.html) → Supabase (база данных)
                                    → Telegram (личка тренера)
```

- **Vercel** — хостинг для HTML-файла (бесплатно)
- **Supabase** — база данных PostgreSQL для заявок и аналитики (бесплатно)
- **GitHub** — репозиторий кода, связан с Vercel (автодеплой при пуше)

---

## 1. GitHub — репозиторий

Репозиторий уже создан: `lekroman82/quiz-pervaya-tennis`

Любое изменение в `master` → автоматический деплой на Vercel.

---

## 2. Vercel — хостинг

### Первоначальная настройка (уже сделана)

1. Зайти на [vercel.com](https://vercel.com) → Sign Up через GitHub
2. New Project → Import `quiz-pervaya-tennis`
3. Framework Preset: **Other**
4. Deploy

### Как деплоить новые изменения

Просто пушить в `master`:

```bash
git add index.html
git commit -m "Описание изменений"
git push
```

Vercel подхватит автоматически за 30–60 секунд.

### Проверить статус деплоя

- Открыть [vercel.com/dashboard](https://vercel.com/dashboard) → выбрать проект → вкладка Deployments

### Свой домен (опционально)

1. Vercel → проект → Settings → Domains
2. Ввести домен (например `quiz.pervaya-tennis.ru`)
3. Добавить DNS-записи у регистратора домена (Vercel покажет какие)

---

## 3. Supabase — база данных

### Данные подключения

Прописаны прямо в `index.html` (строки ~995–996):

```javascript
const SUPABASE_URL = 'https://cwjhdlzsgcwzpbpyrprm.supabase.co';
const SUPABASE_KEY = 'sb_publishable_PCoWawJ_ntw_KdtgtHJOTQ_pbozwmb2';
```

- `SUPABASE_URL` — адрес проекта в Supabase
- `SUPABASE_KEY` — публичный ключ (anon key), безопасно хранить в клиентском коде
- Доступ ограничен через RLS-политики (Row Level Security)

### Как попасть в базу

1. Открыть [app.supabase.com](https://app.supabase.com)
2. Проект: `quiz-platform`
3. Table Editor → таблица `leads` (заявки) или `events` (аналитика)

### Если нужно пересоздать базу с нуля

1. Supabase → SQL Editor
2. Выполнить `supabase/001_schema.sql` (таблицы и политики)
3. Выполнить `supabase/002_seed_pervaya.sql` (данные школы «Первая»)

---

## 4. Конфигурационные файлы

| Файл | Назначение |
|------|-----------|
| `vercel.json` | Заголовки безопасности (X-Frame-Options, Referrer-Policy и др.) |
| `.vercelignore` | Исключает `*.md` и `.claude/` из деплоя |

---

## 5. Что менять при переносе на другой аккаунт

| Что | Где | Как |
|-----|-----|-----|
| Supabase URL | `index.html`, строка ~995 | Заменить на URL нового проекта Supabase |
| Supabase Key | `index.html`, строка ~996 | Заменить на anon key нового проекта |
| School ID | `index.html`, строка ~1000 | UUID школы из таблицы `schools` |
| Telegram ссылка | `index.html`, JS: `const TG = ...` | Ссылка на Telegram тренера |

---

## 6. Мониторинг и диагностика

### Проверить что квиз работает

1. Открыть квиз в браузере
2. F12 → Console — не должно быть красных ошибок
3. Пройти квиз, заполнить форму
4. Supabase → Table Editor → `leads` — должна появиться запись
5. Supabase → Table Editor → `events` — цепочка: visit → quiz_start → quiz_answer (×4) → form_submit → telegram_click

### Частые проблемы

| Проблема | Причина | Решение |
|----------|---------|---------|
| Заявки не сохраняются | RLS блокирует вставку | Проверить что школа `is_active = true` в таблице `schools` |
| Ошибка 401 в консоли | Неверный Supabase Key | Проверить anon key в Settings → API |
| Квиз не открывается | Ошибка в HTML/JS | Проверить Console в DevTools |
| Деплой не обновился | Vercel не подхватил | Проверить Deployments в дашборде Vercel |
