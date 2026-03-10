# Backend Plan: Квиз-платформа для школ тенниса

> Дата: 2026-03-10
> Статус: К разработке
> MVP: 1–5 школ, ручной онбординг

---

## 0. Ключевые решения

| Вопрос | Решение |
|--------|---------|
| Монетизация | Разовая покупка + поддержка |
| Лимиты тарифов | Нет |
| Онбординг | Разработчик настраивает за клиента |
| Гибкость квиза | Фиксированная структура (4 вопроса), меняются тексты/иконки/фото |
| Брендирование | Логотип + цвета + тексты |
| Домен | Поддомен: `{slug}.платформа.ru` |
| Хранение лидов | На платформе |
| Telegram | Ссылка на личный Telegram владельца школы |
| AI-нейропродавец | Отдельный проект, не входит в MVP |
| Аналитика | Дашборд для владельца школы |

---

## 1. Архитектура

```
                    ┌─────────────────────────┐
                    │   {slug}.платформа.ru    │
                    │   (квиз для клиентов)    │
                    └────────┬────────────────┘
                             │
                             ▼
                    ┌─────────────────────────┐
                    │        API-сервер        │
                    │     /api/v1/...          │
                    └────┬───────────┬────────┘
                         │           │
                    ┌────▼───┐  ┌────▼────────┐
                    │   DB   │  │ Файлы (S3)  │
                    │ Postgres│  │ логотипы,   │
                    │        │  │ фото        │
                    └────────┘  └─────────────┘
                         │
                    ┌────▼────────────────────┐
                    │   Админ-панель           │
                    │   admin.платформа.ru     │
                    │   (настройка + дашборд)  │
                    └─────────────────────────┘
```

**Стек:**

| Компонент | Технология | Почему |
|-----------|-----------|--------|
| API | Node.js + Express | Один язык с фронтом, простота |
| БД | PostgreSQL | Надёжно, JSON-поля для гибких данных |
| ORM | Prisma | Типизация, миграции |
| Файлы | S3 (Yandex Cloud / MinIO) | Логотипы, фото |
| Админ-панель | React (Vite) | Быстро, SPA |
| Квиз (фронт) | Текущий index.html, рендерится сервером | Подставляются данные школы |
| Хостинг | VPS (1 сервер для MVP) | Дёшево, контроль |
| Домены | Wildcard DNS `*.платформа.ru` | Поддомены без ручной настройки |

---

## 2. Модель данных

### Таблица `schools` — школы-клиенты

```
schools
├── id              UUID, PK
├── slug            VARCHAR UNIQUE     -- поддомен: "cooltennis" → cooltennis.платформа.ru
├── name            VARCHAR            -- "CoolTennis"
├── owner_name      VARCHAR            -- имя владельца
├── owner_email     VARCHAR            -- email для входа в админку
├── owner_phone     VARCHAR            -- телефон владельца
├── telegram_link   VARCHAR            -- "https://t.me/Roman_Lekomtsev"
├── is_active       BOOLEAN            -- включён/выключен квиз
├── created_at      TIMESTAMP
└── updated_at      TIMESTAMP
```

### Таблица `branding` — визуал школы

```
branding
├── id              UUID, PK
├── school_id       UUID, FK → schools -- 1:1
├── logo_url        VARCHAR            -- ссылка на логотип в S3
├── accent_color    VARCHAR(7)         -- "#C45A30"
├── accent_hover    VARCHAR(7)         -- "#A84B27"
├── bg_color        VARCHAR(7)         -- "#FFFFFF"
├── text_color      VARCHAR(7)         -- "#1A1A1A"
├── telegram_color  VARCHAR(7)         -- "#2AABEE" (цвет кнопки TG)
├── meta_title      VARCHAR            -- для <title> и og:title
├── meta_desc       VARCHAR            -- для <meta description> и og:description
└── counter_text    VARCHAR            -- "Уже прошли тест: 1 247 человек"
```

### Таблица `start_screen` — стартовый экран

```
start_screen
├── id              UUID, PK
├── school_id       UUID, FK → schools -- 1:1
├── badge_text      VARCHAR            -- "🎾 Бесплатный тест — 2 минуты"
├── heading         TEXT               -- "Вам когда-нибудь говорили, что теннис — ..."
├── subheading      VARCHAR            -- "Они были неправы."
├── description     TEXT               -- "Узнайте за 4 вопроса..."
├── cta_text        VARCHAR            -- "Пройти тест бесплатно"
├── cta_note        VARCHAR            -- "Мы не будем звонить..."
├── motivator       TEXT               -- "Сотни людей начинают..."
├── stats           JSONB              -- [{"icon":"📊","text":"8 из 10..."},...]
├── reviews         JSONB              -- [{"text":"...","author":"Ольга","label":"мама ученика"},...]
└── learn_items     JSONB              -- [{"icon":"🎾","text":"Подходит ли вам теннис"},...]
```

### Таблица `questions` — вопросы (ровно 4 на школу)

```
questions
├── id              UUID, PK
├── school_id       UUID, FK → schools
├── number          SMALLINT           -- 1, 2, 3, 4
├── heading         VARCHAR            -- "Вам когда-нибудь говорили...?"
├── hint            VARCHAR            -- "Честно — это важно..."
├── is_branching    BOOLEAN            -- true для Q3 (сегмент) и Q4 (зависит от Q3)
└── UNIQUE(school_id, number)
```

### Таблица `answers` — варианты ответов

```
answers
├── id              UUID, PK
├── question_id     UUID, FK → questions
├── value           VARCHAR            -- "expensive", "child", "price"
├── icon            VARCHAR            -- "💸"
├── text            VARCHAR            -- "Да — казалось, что это дорого"
├── hint            VARCHAR            -- "Так думали 8 из 10 наших учеников"
├── sort_order      SMALLINT           -- порядок отображения
├── parent_value    VARCHAR NULL       -- для Q4: значение ответа Q3, от которого зависит
│                                      -- NULL = показывать всегда
│                                      -- "child" = показывать только если в Q3 выбрали "child"
└── UNIQUE(question_id, value)
```

**Логика ветвления Q4:**
- У Q3 `is_branching = true` — ответ определяет сегмент
- У Q4 `is_branching = true` — карточки фильтруются по `parent_value`
- Если `ans[3] = "child"`, показываются ответы Q4 где `parent_value = "child"`
- Если `ans[3] = "family"` и карточек с `parent_value = "family"` нет — fallback на `parent_value = "self"` (как сейчас: `Q4_CARDS.family = Q4_CARDS.self`)

### Таблица `answer_fallbacks` — fallback-маппинг для ветвлений

```
answer_fallbacks
├── id              UUID, PK
├── school_id       UUID, FK → schools
├── question_number SMALLINT           -- 4 (номер вопроса с ветвлением)
├── segment_value   VARCHAR            -- "family"
└── fallback_value  VARCHAR            -- "self"
```

### Таблица `results` — персонализированные результаты

```
results
├── id              UUID, PK
├── school_id       UUID, FK → schools
├── segment_value   VARCHAR            -- "child", "teen", "self", "family"
├── title           VARCHAR            -- "Вашему ребёнку подойдёт программа «Юный теннисист»"
├── description     TEXT               -- "Игровой формат для детей..."
└── UNIQUE(school_id, segment_value)
```

### Таблица `gifts` — подарки на экране результата

```
gifts
├── id              UUID, PK
├── school_id       UUID, FK → schools
├── icon            VARCHAR            -- "🎬"
├── title           VARCHAR            -- "Видеоразбор: 5 мифов о теннисе"
├── description     TEXT               -- "Тренер на камеру разбирает..."
├── author          VARCHAR            -- "от Алексея Петрова, тренер 8 лет"
└── sort_order      SMALLINT
```

### Таблица `leads` — лиды (собранные контакты)

```
leads
├── id              UUID, PK
├── school_id       UUID, FK → schools
├── name            VARCHAR            -- "Иван"
├── phone           VARCHAR            -- "+7 (916) 123-45-67"
├── answers         JSONB              -- {"1":"expensive","2":"saw","3":"child","4":"price"}
├── segment         VARCHAR            -- значение из Q3: "child"
├── telegram_clicked BOOLEAN DEFAULT false  -- нажал ли кнопку TG
├── utm_source      VARCHAR NULL
├── utm_medium      VARCHAR NULL
├── utm_campaign    VARCHAR NULL
├── created_at      TIMESTAMP
```

### Таблица `answer_labels` — человеко-читаемые лейблы ответов для TG-сообщения

```
answer_labels
├── id              UUID, PK
├── school_id       UUID, FK → schools
├── question_number SMALLINT           -- 1
├── value           VARCHAR            -- "expensive"
├── label           VARCHAR            -- "Казалось дорого"
└── UNIQUE(school_id, question_number, value)
```

### Таблица `users` — доступ к админ-панели

```
users
├── id              UUID, PK
├── school_id       UUID NULL, FK → schools  -- NULL = суперадмин (разработчик)
├── email           VARCHAR UNIQUE
├── password_hash   VARCHAR
├── role            VARCHAR            -- "superadmin" | "owner"
└── created_at      TIMESTAMP
```

---

## 3. API

### 3.1 Публичный API (квиз-фронт → сервер)

Вызывается из браузера посетителя квиза. Без авторизации.

```
GET  /api/v1/quiz/:slug
```

Отдаёт ВСЕ данные для рендеринга квиза одним запросом:

```json
{
  "school": {
    "name": "Первая",
    "telegram_link": "https://t.me/Roman_Lekomtsev"
  },
  "branding": {
    "logo_url": "https://s3.../logo.png",
    "accent_color": "#C45A30",
    "accent_hover": "#A84B27",
    "bg_color": "#FFFFFF",
    "text_color": "#1A1A1A",
    "meta_title": "Тест: Вам говорили...",
    "meta_desc": "Узнайте за 4 вопроса...",
    "counter_text": "Уже прошли тест: 1 247 человек"
  },
  "start_screen": {
    "badge_text": "🎾 Бесплатный тест — 2 минуты",
    "heading": "Вам когда-нибудь говорили...",
    "subheading": "Они были неправы.",
    "description": "Узнайте за 4 вопроса...",
    "cta_text": "Пройти тест бесплатно",
    "cta_note": "Мы не будем звонить...",
    "stats": [...],
    "reviews": [...],
    "learn_items": [...]
  },
  "questions": [
    {
      "number": 1,
      "heading": "Вам когда-нибудь говорили...?",
      "hint": "Честно — это важно...",
      "is_branching": false,
      "answers": [
        { "value": "expensive", "icon": "💸", "text": "Да — казалось дорого", "hint": "Так думали 8 из 10...", "parent_value": null }
      ]
    }
  ],
  "answer_fallbacks": { "4": { "family": "self" } },
  "results": {
    "child": { "title": "...", "description": "..." },
    "teen": { "title": "...", "description": "..." }
  },
  "gifts": [
    { "icon": "🎬", "title": "...", "description": "...", "author": "..." }
  ],
  "answer_labels": {
    "1": { "expensive": "Казалось дорого", ... },
    "2": { ... }
  }
}
```

```
POST /api/v1/quiz/:slug/lead
```

Тело:
```json
{
  "name": "Иван",
  "phone": "+7 (916) 123-45-67",
  "answers": { "1": "expensive", "2": "saw", "3": "child", "4": "price" },
  "utm_source": "vk",
  "utm_medium": "cpc",
  "utm_campaign": "quiz_march"
}
```

Ответ:
```json
{
  "ok": true,
  "telegram_url": "https://t.me/Roman_Lekomtsev?text=..."
}
```

Сервер:
1. Валидирует данные (имя ≥ 2 символов, телефон = 11 цифр)
2. Сохраняет лид в `leads`
3. Формирует Telegram-ссылку с лейблами из `answer_labels`
4. Возвращает готовую ссылку

```
POST /api/v1/quiz/:slug/event
```

Аналитические события (без блокировки UI — fire and forget):

```json
{ "type": "quiz_start" }
{ "type": "quiz_answer", "question": 1, "value": "expensive" }
{ "type": "quiz_form_submit" }
{ "type": "quiz_telegram_click" }
```

### 3.2 API админ-панели (авторизованный)

Все запросы требуют `Authorization: Bearer <token>`.

#### Авторизация

```
POST /api/v1/auth/login        { email, password } → { token }
POST /api/v1/auth/logout
GET  /api/v1/auth/me           → { user, school }
```

#### Управление школой (owner видит только свою, superadmin — все)

```
GET    /api/v1/admin/school              → данные своей школы
PUT    /api/v1/admin/school              → обновить название, TG-ссылку
PUT    /api/v1/admin/school/branding     → обновить цвета, логотип, мета-теги
PUT    /api/v1/admin/school/start-screen → обновить стартовый экран
```

#### Управление вопросами

```
GET    /api/v1/admin/questions           → список 4 вопросов с ответами
PUT    /api/v1/admin/questions/:number   → обновить текст вопроса + ответы
```

Структура вопросов фиксирована (4 штуки), меняются только тексты.

#### Управление результатами и подарками

```
GET    /api/v1/admin/results             → список результатов по сегментам
PUT    /api/v1/admin/results/:segment    → обновить заголовок и описание
GET    /api/v1/admin/gifts               → список подарков
PUT    /api/v1/admin/gifts/:id           → обновить подарок
```

#### Лиды и аналитика

```
GET    /api/v1/admin/leads               → список лидов (пагинация, фильтры)
         ?page=1&limit=20
         &from=2026-03-01
         &to=2026-03-10
         &segment=child
GET    /api/v1/admin/leads/export        → CSV-экспорт
GET    /api/v1/admin/analytics/summary   → сводка для дашборда
```

Ответ `/analytics/summary`:
```json
{
  "period": { "from": "2026-03-01", "to": "2026-03-10" },
  "total_visits": 1520,
  "quiz_started": 1050,
  "quiz_completed": 840,
  "leads_collected": 275,
  "telegram_clicks": 135,
  "conversion_rates": {
    "visit_to_start": 69.1,
    "start_to_complete": 80.0,
    "complete_to_lead": 32.7,
    "lead_to_telegram": 49.1
  },
  "segments": {
    "child": 98,
    "teen": 45,
    "self": 87,
    "family": 45
  },
  "top_barriers": [
    { "value": "price", "count": 112 },
    { "value": "too_late", "count": 65 }
  ]
}
```

### 3.3 API суперадмина (только разработчик)

```
GET    /api/v1/superadmin/schools         → все школы
POST   /api/v1/superadmin/schools         → создать школу (+ slug, + owner)
PUT    /api/v1/superadmin/schools/:id     → вкл/выкл, правки
DELETE /api/v1/superadmin/schools/:id     → удалить школу
POST   /api/v1/superadmin/schools/:id/seed → залить начальные данные (вопросы, результаты)
```

---

## 4. Роли и доступ

| Действие | superadmin | owner |
|----------|-----------|-------|
| Создать/удалить школу | ✅ | ❌ |
| Настроить квиз (тексты, цвета, вопросы) | ✅ | ✅ (только свою) |
| Смотреть лиды | ✅ (все) | ✅ (только свои) |
| Смотреть дашборд аналитики | ✅ | ✅ (только свой) |
| Экспорт лидов в CSV | ✅ | ✅ |
| Вкл/выкл квиз школы | ✅ | ❌ |

---

## 5. Рендеринг квиза

Текущий `index.html` превращается в **серверный шаблон**.

### Как это работает:

1. Посетитель заходит на `cooltennis.платформа.ru`
2. Сервер определяет школу по поддомену (`slug = "cooltennis"`)
3. Делает `GET /api/v1/quiz/cooltennis` (внутренний вызов)
4. Подставляет данные в HTML-шаблон:
   - CSS-переменные (`:root`) ← из `branding`
   - Тексты стартовой ← из `start_screen`
   - Вопросы и карточки ← из `questions` + `answers`
   - Результаты ← из `results`
   - Подарки ← из `gifts`
   - `const TG = '...'` ← из `schools.telegram_link`
   - `<title>` и `og:*` ← из `branding.meta_title/meta_desc`
   - Логотип ← из `branding.logo_url`
5. Отдаёт готовый HTML (один файл, как сейчас)

### Что меняется в JS квиза:

```diff
- const TG = 'https://t.me/Roman_Lekomtsev';
+ // Подставляется сервером
+ const TG = '{{telegram_link}}';
+ const SLUG = '{{slug}}';

- // Ответы хранятся только в браузере
+ // При отправке формы — POST на сервер
  function send(e) {
    ...
-   document.getElementById('tgLink').href = TG + '?text=' + msg;
+   fetch('/api/v1/quiz/' + SLUG + '/lead', {
+     method: 'POST',
+     headers: { 'Content-Type': 'application/json' },
+     body: JSON.stringify({ name, phone, answers: ans, utm_source, utm_medium, utm_campaign })
+   })
+   .then(r => r.json())
+   .then(data => {
+     document.getElementById('tgLink').href = data.telegram_url;
+     show('screen-final');
+     boom();
+   });
  }
```

Аналитические события отправляются через `navigator.sendBeacon`:

```js
function trackEvent(type, data) {
  navigator.sendBeacon(
    '/api/v1/quiz/' + SLUG + '/event',
    JSON.stringify({ type, ...data })
  );
}
```

---

## 6. Таблица `events` — аналитика

```
events
├── id              UUID, PK
├── school_id       UUID, FK → schools
├── session_id      VARCHAR            -- генерируется на фронте (crypto.randomUUID)
├── type            VARCHAR            -- "visit" | "quiz_start" | "quiz_answer" | "quiz_complete" | "form_submit" | "telegram_click"
├── payload         JSONB NULL         -- {"question":1,"value":"expensive"}
├── utm_source      VARCHAR NULL
├── utm_medium      VARCHAR NULL
├── utm_campaign    VARCHAR NULL
├── created_at      TIMESTAMP
```

Из этой таблицы считается вся аналитика для дашборда:
- `visit` → `total_visits`
- `quiz_start` → `quiz_started`
- `quiz_complete` (type у последнего ответа Q4) → `quiz_completed`
- `form_submit` → `leads_collected`
- `telegram_click` → `telegram_clicks`

---

## 7. Процесс онбординга новой школы

Ты (superadmin) делаешь всё за клиента:

```
1. POST /api/v1/superadmin/schools
   → slug: "cooltennis"
   → name: "CoolTennis"
   → telegram_link: "https://t.me/cooltennis_owner"
   → owner_email: "owner@cooltennis.ru"

2. Сервер создаёт:
   → запись в schools
   → запись в branding (дефолтные цвета)
   → запись в start_screen (шаблон)
   → 4 вопроса в questions (шаблон)
   → ответы в answers (шаблон)
   → 4 результата в results (шаблон)
   → 2 подарка в gifts (шаблон)
   → лейблы в answer_labels (шаблон)
   → пользователь в users (owner, временный пароль)

3. Ты настраиваешь тексты, цвета, загружаешь логотип через админку

4. Отдаёшь клиенту:
   → URL: cooltennis.платформа.ru
   → Логин/пароль от админки (для просмотра лидов и дашборда)
```

---

## 8. Структура файлов проекта

```
quiz-platform/
├── server/
│   ├── src/
│   │   ├── index.ts                 -- точка входа, Express
│   │   ├── middleware/
│   │   │   ├── auth.ts              -- JWT-проверка
│   │   │   └── tenant.ts            -- определение школы по поддомену
│   │   ├── routes/
│   │   │   ├── quiz.ts              -- публичный API (GET quiz, POST lead, POST event)
│   │   │   ├── admin.ts             -- API админки (school, questions, results, leads)
│   │   │   └── superadmin.ts        -- API суперадмина (schools CRUD)
│   │   ├── services/
│   │   │   ├── quiz.service.ts      -- сборка данных квиза, формирование TG-ссылки
│   │   │   ├── lead.service.ts      -- сохранение лидов, валидация
│   │   │   ├── analytics.service.ts -- агрегация событий для дашборда
│   │   │   └── school.service.ts    -- CRUD школы, seed-данные
│   │   ├── templates/
│   │   │   └── quiz.html            -- шаблон квиза (бывший index.html)
│   │   └── prisma/
│   │       └── schema.prisma        -- схема БД
│   ├── package.json
│   └── tsconfig.json
├── admin/
│   ├── src/
│   │   ├── pages/
│   │   │   ├── Login.tsx
│   │   │   ├── Dashboard.tsx        -- аналитика
│   │   │   ├── Leads.tsx            -- таблица лидов
│   │   │   ├── Settings.tsx         -- брендинг + тексты
│   │   │   └── Questions.tsx        -- редактор вопросов
│   │   └── App.tsx
│   ├── package.json
│   └── vite.config.ts
└── docker-compose.yml               -- postgres + server + admin
```

---

## 9. Что НЕ входит в MVP

| Фича | Почему не сейчас | Когда |
|------|------------------|-------|
| AI-нейропродавец (Telegram-бот) | Отдельный проект | v2 |
| Telegram Bot API интеграция | Сейчас — ссылка на личный TG | v2, вместе с ботом |
| Конструктор вопросов (добавить/удалить) | Структура фиксирована | Если будет спрос |
| Кастомный CSS/шрифты | Только цвета + логотип | Если будет спрос |
| Домен клиента (quiz.cooltennis.ru) | Поддомены проще | Если будет спрос |
| Яндекс.Метрика интеграция | Своя аналитика | v1.1 |
| A/B-тесты заголовков | Нужен трафик | После 1000 визитов |
| Self-service регистрация | Ручной онбординг | Если >10 клиентов |
| Мультиязычность | Только русский рынок | Не планируется |
| Оплата через сайт | Разовая покупка оффлайн | Не планируется |

---

## 10. Порядок разработки

### Этап 1: База (сервер + БД)

- [ ] Инициализация проекта (Express + TypeScript + Prisma)
- [ ] Схема БД, миграции
- [ ] Middleware: определение школы по поддомену
- [ ] `GET /api/v1/quiz/:slug` — сборка данных квиза
- [ ] Серверный рендеринг `quiz.html` с подстановкой данных
- [ ] `POST /api/v1/quiz/:slug/lead` — сохранение лида + формирование TG-ссылки
- [ ] `POST /api/v1/quiz/:slug/event` — сохранение аналитических событий
- [ ] Seed-скрипт: заливка данных текущей школы «Первая» из index.html

### Этап 2: Авторизация + суперадмин

- [ ] JWT-авторизация (login, logout, me)
- [ ] CRUD школ (superadmin)
- [ ] Seed-команда для создания новой школы с шаблонными данными

### Этап 3: Админ-панель (owner)

- [ ] Страница логина
- [ ] Дашборд: визиты, конверсии, сегменты, топ-барьеры
- [ ] Таблица лидов с фильтрами + CSV-экспорт
- [ ] Настройки: брендинг (цвета, логотип, мета-теги)
- [ ] Настройки: стартовый экран (тексты, статистика, отзывы)
- [ ] Редактор вопросов (тексты, иконки, подсказки)
- [ ] Редактор результатов и подарков

### Этап 4: Деплой + перенос «Первой»

- [ ] Docker-compose (postgres + server + admin)
- [ ] Wildcard DNS для `*.платформа.ru`
- [ ] SSL (Let's Encrypt wildcard)
- [ ] Перенос данных «Первой» из index.html в БД
- [ ] Проверка: `pervaya.платформа.ru` работает идентично текущему index.html
- [ ] Подключение UTM-параметров (чтение из URL → передача в lead и events)
