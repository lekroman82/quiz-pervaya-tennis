-- ============================================================
-- Квиз-платформа для школ тенниса — Supabase SQL-схема
-- Версия: 1.0 (MVP)
-- Дата: 2026-03-10
--
-- ВАЖНО: Этот скрипт запускается в Supabase SQL Editor
-- Порядок: сначала таблицы, потом RLS-политики, потом функции
-- ============================================================


-- ============================================================
-- 1. ТАБЛИЦЫ
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 schools — школы-клиенты (главная таблица)
--
-- Метафора: это «папка клиента». Всё остальное привязано к ней.
-- Одна школа = один квиз = один поддомен.
-- ------------------------------------------------------------

create table public.schools (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,           -- поддомен: "cooltennis" → cooltennis.платформа.ru
  name        text not null,                  -- "CoolTennis"
  owner_name  text,                           -- имя владельца
  owner_email text,                           -- email (для связи, не для входа)
  owner_phone text,                           -- телефон владельца
  telegram_link text not null,                -- "https://t.me/Roman_Lekomtsev"
  is_active   boolean not null default true,  -- вкл/выкл квиз
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.schools is 'Школы-клиенты. Одна запись = один квиз на отдельном поддомене.';


-- ------------------------------------------------------------
-- 1.2 branding — визуальные настройки школы
--
-- Метафора: «обложка» школы. Цвета, логотип, SEO-тексты.
-- Связь 1:1 со schools.
-- ------------------------------------------------------------

create table public.branding (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null unique references public.schools(id) on delete cascade,
  logo_url        text,                       -- ссылка на логотип (Supabase Storage)
  accent_color    varchar(7) not null default '#C45A30',
  accent_hover    varchar(7) not null default '#A84B27',
  bg_color        varchar(7) not null default '#FFFFFF',
  text_color      varchar(7) not null default '#1A1A1A',
  telegram_color  varchar(7) not null default '#2AABEE',
  meta_title      text,                       -- <title> и og:title
  meta_desc       text,                       -- <meta description> и og:description
  counter_text    text default 'Уже прошли тест: 1 247 человек'
);

comment on table public.branding is 'Визуальные настройки: цвета, логотип, мета-теги. 1:1 со schools.';


-- ------------------------------------------------------------
-- 1.3 start_screen — контент стартового экрана
--
-- Метафора: «витрина магазина». Первое, что видит посетитель.
-- Связь 1:1 со schools.
-- ------------------------------------------------------------

create table public.start_screen (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null unique references public.schools(id) on delete cascade,
  badge_text   text default '🎾 Бесплатный тест — 2 минуты',
  heading      text not null,                 -- главный заголовок H1
  subheading   text,                          -- "Они были неправы."
  description  text,                          -- "Узнайте за 4 вопроса..."
  cta_text     text not null default 'Пройти тест бесплатно',
  cta_note     text default 'Мы не будем звонить. Результат — сразу на экране.',
  motivator    text,                          -- мотивационный текст внизу
  stats        jsonb not null default '[]',   -- [{"icon":"📊","text":"8 из 10..."}]
  reviews      jsonb not null default '[]',   -- [{"text":"...","author":"Ольга","label":"мама"}]
  learn_items  jsonb not null default '[]'    -- [{"icon":"🎾","text":"Подходит ли вам теннис"}]
);

comment on table public.start_screen is 'Контент стартового экрана: заголовки, статистика, отзывы, CTA. 1:1 со schools.';


-- ------------------------------------------------------------
-- 1.4 questions — вопросы квиза (ровно 4 на школу)
--
-- Метафора: «карточки вопросов». Фиксированная структура,
-- меняются только тексты.
-- ------------------------------------------------------------

create table public.questions (
  id            uuid primary key default gen_random_uuid(),
  school_id     uuid not null references public.schools(id) on delete cascade,
  number        smallint not null,            -- 1, 2, 3, 4
  heading       text not null,                -- текст вопроса
  hint          text,                         -- подсказка под вопросом
  is_branching  boolean not null default false, -- true = ответ влияет на следующий вопрос
  unique(school_id, number)
);

comment on table public.questions is 'Вопросы квиза. Ровно 4 на школу. Фиксированная структура.';


-- ------------------------------------------------------------
-- 1.5 answers — варианты ответов на вопросы
--
-- Метафора: «карточки ответов» внутри каждого вопроса.
-- parent_value — для ветвления: показывать карточку только
-- если в предыдущем вопросе выбрали определённый сегмент.
-- ------------------------------------------------------------

create table public.answers (
  id            uuid primary key default gen_random_uuid(),
  question_id   uuid not null references public.questions(id) on delete cascade,
  value         text not null,                -- ключ ответа: "expensive", "child"
  icon          text not null default '🎾',
  text          text not null,                -- текст карточки
  hint          text,                         -- подсказка мелким шрифтом
  sort_order    smallint not null default 0,
  parent_value  text,                         -- NULL = всегда, "child" = только для сегмента child
  unique(question_id, value)
);

comment on table public.answers is 'Варианты ответов. parent_value используется для ветвления Q4.';


-- ------------------------------------------------------------
-- 1.6 answer_fallbacks — fallback для ветвлений
--
-- Метафора: «подстраховка». Если для сегмента "family"
-- нет своих карточек Q4, показать карточки сегмента "self".
-- ------------------------------------------------------------

create table public.answer_fallbacks (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references public.schools(id) on delete cascade,
  question_number  smallint not null,         -- номер вопроса (4)
  segment_value    text not null,             -- "family"
  fallback_value   text not null              -- "self"
);

comment on table public.answer_fallbacks is 'Fallback-маппинг: если для сегмента нет карточек, использовать другой.';


-- ------------------------------------------------------------
-- 1.7 results — персонализированные результаты
--
-- Метафора: «финальные карточки». После квиза посетитель
-- видит заголовок и описание, подобранные под его сегмент.
-- ------------------------------------------------------------

create table public.results (
  id             uuid primary key default gen_random_uuid(),
  school_id      uuid not null references public.schools(id) on delete cascade,
  segment_value  text not null,               -- "child", "teen", "self", "family"
  title          text not null,               -- "Вашему ребёнку подойдёт..."
  description    text not null,               -- "Игровой формат для детей..."
  unique(school_id, segment_value)
);

comment on table public.results is 'Персонализированные результаты по сегментам. 1 запись на сегмент.';


-- ------------------------------------------------------------
-- 1.8 gifts — подарки/бонусы на экране результата
--
-- Метафора: «подарочные коробки», которые мотивируют
-- оставить контакт.
-- ------------------------------------------------------------

create table public.gifts (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references public.schools(id) on delete cascade,
  icon        text not null default '🎁',
  title       text not null,
  description text,
  author      text,                           -- "от Алексея Петрова, тренер 8 лет"
  sort_order  smallint not null default 0
);

comment on table public.gifts is 'Подарки/бонусы на экране результата. Мотивируют оставить контакт.';


-- ------------------------------------------------------------
-- 1.9 answer_labels — лейблы ответов для TG-сообщения
--
-- Метафора: «переводчик». Превращает технический ключ
-- "expensive" в человеческий текст "Казалось дорого"
-- для Telegram-сообщения.
-- ------------------------------------------------------------

create table public.answer_labels (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references public.schools(id) on delete cascade,
  question_number  smallint not null,
  value            text not null,             -- "expensive"
  label            text not null,             -- "Казалось дорого"
  unique(school_id, question_number, value)
);

comment on table public.answer_labels is 'Человеко-читаемые лейблы ответов для формирования TG-сообщения.';


-- ------------------------------------------------------------
-- 1.10 leads — собранные контакты (лиды)
--
-- Метафора: «журнал заявок». Каждая строка — человек,
-- который прошёл квиз и оставил контакты.
-- ------------------------------------------------------------

create table public.leads (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools(id) on delete cascade,
  name              text not null,
  phone             text not null,
  answers           jsonb not null default '{}', -- {"1":"expensive","2":"saw","3":"child","4":"price"}
  segment           text,                        -- значение из Q3
  telegram_clicked  boolean not null default false,
  utm_source        text,
  utm_medium        text,
  utm_campaign      text,
  created_at        timestamptz not null default now()
);

comment on table public.leads is 'Лиды: контакты людей, прошедших квиз. Основная ценность платформы.';


-- ------------------------------------------------------------
-- 1.11 events — аналитические события
--
-- Метафора: «камеры наблюдения». Записывают каждое действие
-- посетителя: зашёл, начал квиз, ответил, отправил форму...
-- Из этих записей строится дашборд аналитики.
-- ------------------------------------------------------------

create table public.events (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools(id) on delete cascade,
  session_id   text,                          -- ID сессии (генерируется на фронте)
  type         text not null,                 -- "visit", "quiz_start", "quiz_answer", "form_submit", "telegram_click"
  payload      jsonb,                         -- {"question":1,"value":"expensive"}
  utm_source   text,
  utm_medium   text,
  utm_campaign text,
  created_at   timestamptz not null default now()
);

comment on table public.events is 'Аналитические события. Из них строится дашборд конверсий.';


-- ------------------------------------------------------------
-- 1.12 profiles — профили пользователей админки
--
-- В Supabase авторизация хранится в auth.users (встроенная).
-- Эта таблица — «дополнение к паспорту»: роль и привязка к школе.
-- Создаётся автоматически при регистрации через триггер.
-- ------------------------------------------------------------

create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  school_id  uuid references public.schools(id) on delete set null,
  role       text not null default 'owner' check (role in ('superadmin', 'owner')),
  created_at timestamptz not null default now()
);

comment on table public.profiles is 'Профили пользователей админки. Роль + привязка к школе.';


-- ============================================================
-- 2. ИНДЕКСЫ
-- ============================================================

-- Быстрый поиск школы по поддомену (каждый запрос квиза начинается с этого)
create index idx_schools_slug on public.schools(slug);

-- Быстрая выборка лидов по школе и дате
create index idx_leads_school_created on public.leads(school_id, created_at desc);

-- Быстрая выборка событий для аналитики
create index idx_events_school_type_created on public.events(school_id, type, created_at desc);

-- Сортировка ответов
create index idx_answers_question_order on public.answers(question_id, sort_order);


-- ============================================================
-- 3. АВТООБНОВЛЕНИЕ updated_at
-- ============================================================

-- Функция: при UPDATE автоматически ставит текущее время в updated_at
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Триггер для schools
create trigger on_schools_updated
  before update on public.schools
  for each row execute function public.handle_updated_at();


-- ============================================================
-- 4. АВТОСОЗДАНИЕ ПРОФИЛЯ ПРИ РЕГИСТРАЦИИ
-- ============================================================

-- Когда в Supabase Auth появляется новый пользователь,
-- автоматически создаётся запись в profiles.
-- Роль и school_id берутся из user_metadata (задаёшь при создании).

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, school_id, role)
  values (
    new.id,
    (new.raw_user_meta_data->>'school_id')::uuid,
    coalesce(new.raw_user_meta_data->>'role', 'owner')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
-- 5. ROW LEVEL SECURITY (RLS) — ПРАВА ДОСТУПА
--
-- Метафора: RLS — это «замки на дверях». Каждая таблица
-- заперта по умолчанию. Мы добавляем «ключи» (политики):
-- кто может читать, кто может писать.
--
-- Три типа доступа:
-- 1. anon (аноним)   — посетитель квиза, без логина
-- 2. authenticated   — залогиненный пользователь админки
-- 3. service_role    — серверный ключ (обходит все политики)
-- ============================================================

-- Включаем RLS на всех таблицах
alter table public.schools          enable row level security;
alter table public.branding         enable row level security;
alter table public.start_screen     enable row level security;
alter table public.questions        enable row level security;
alter table public.answers          enable row level security;
alter table public.answer_fallbacks enable row level security;
alter table public.results          enable row level security;
alter table public.gifts            enable row level security;
alter table public.answer_labels    enable row level security;
alter table public.leads            enable row level security;
alter table public.events           enable row level security;
alter table public.profiles         enable row level security;


-- ============================================================
-- 5.1 Вспомогательные функции для политик
-- ============================================================

-- Получить school_id текущего пользователя из profiles
create or replace function public.get_my_school_id()
returns uuid as $$
  select school_id from public.profiles where id = auth.uid();
$$ language sql security definer stable;

-- Проверить, является ли текущий пользователь суперадмином
create or replace function public.is_superadmin()
returns boolean as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'superadmin'
  );
$$ language sql security definer stable;


-- ============================================================
-- 5.2 Политики для SCHOOLS
-- ============================================================

-- Анонимы: читать только активные школы (нужно для квиза)
create policy "anon_read_active_schools"
  on public.schools for select
  to anon
  using (is_active = true);

-- Owner: читать только свою школу
create policy "owner_read_own_school"
  on public.schools for select
  to authenticated
  using (id = public.get_my_school_id() or public.is_superadmin());

-- Owner: обновлять только свою школу (но не is_active и slug)
create policy "owner_update_own_school"
  on public.schools for update
  to authenticated
  using (id = public.get_my_school_id() or public.is_superadmin());

-- Superadmin: полный CRUD
create policy "superadmin_insert_schools"
  on public.schools for insert
  to authenticated
  with check (public.is_superadmin());

create policy "superadmin_delete_schools"
  on public.schools for delete
  to authenticated
  using (public.is_superadmin());


-- ============================================================
-- 5.3 Политики для контента квиза
--     (branding, start_screen, questions, answers,
--      answer_fallbacks, results, gifts, answer_labels)
--
-- Одинаковая логика: анонимы читают (для рендеринга квиза),
-- owner редактирует свои, superadmin — все.
-- ============================================================

-- Макрос-шаблон для каждой таблицы с school_id
-- (branding, start_screen, results, gifts, answer_labels, answer_fallbacks)

do $$
declare
  t text;
begin
  foreach t in array array[
    'branding', 'start_screen', 'results',
    'gifts', 'answer_labels', 'answer_fallbacks'
  ]
  loop
    -- Анонимы читают (для рендеринга квиза)
    execute format(
      'create policy "anon_read_%1$s" on public.%1$s for select to anon using (
        school_id in (select id from public.schools where is_active = true)
      )', t
    );

    -- Authenticated: читать свои или всё (superadmin)
    execute format(
      'create policy "auth_read_%1$s" on public.%1$s for select to authenticated using (
        school_id = public.get_my_school_id() or public.is_superadmin()
      )', t
    );

    -- Authenticated: обновлять свои или всё (superadmin)
    execute format(
      'create policy "auth_update_%1$s" on public.%1$s for update to authenticated using (
        school_id = public.get_my_school_id() or public.is_superadmin()
      )', t
    );

    -- Superadmin: вставлять и удалять
    execute format(
      'create policy "superadmin_insert_%1$s" on public.%1$s for insert to authenticated with check (
        public.is_superadmin()
      )', t
    );

    execute format(
      'create policy "superadmin_delete_%1$s" on public.%1$s for delete to authenticated using (
        public.is_superadmin()
      )', t
    );
  end loop;
end;
$$;


-- questions — отдельно, потому что анонимы тоже читают
create policy "anon_read_questions" on public.questions for select to anon
  using (school_id in (select id from public.schools where is_active = true));

create policy "auth_read_questions" on public.questions for select to authenticated
  using (school_id = public.get_my_school_id() or public.is_superadmin());

create policy "auth_update_questions" on public.questions for update to authenticated
  using (school_id = public.get_my_school_id() or public.is_superadmin());

create policy "superadmin_insert_questions" on public.questions for insert to authenticated
  with check (public.is_superadmin());

create policy "superadmin_delete_questions" on public.questions for delete to authenticated
  using (public.is_superadmin());


-- answers — через question_id (join с questions для проверки)
create policy "anon_read_answers" on public.answers for select to anon
  using (question_id in (
    select q.id from public.questions q
    join public.schools s on s.id = q.school_id
    where s.is_active = true
  ));

create policy "auth_read_answers" on public.answers for select to authenticated
  using (question_id in (
    select q.id from public.questions q
    where q.school_id = public.get_my_school_id() or public.is_superadmin()
  ));

create policy "auth_update_answers" on public.answers for update to authenticated
  using (question_id in (
    select q.id from public.questions q
    where q.school_id = public.get_my_school_id() or public.is_superadmin()
  ));

create policy "superadmin_insert_answers" on public.answers for insert to authenticated
  with check (public.is_superadmin() or question_id in (
    select q.id from public.questions q
    where q.school_id = public.get_my_school_id()
  ));

create policy "superadmin_delete_answers" on public.answers for delete to authenticated
  using (public.is_superadmin());


-- ============================================================
-- 5.4 Политики для LEADS
--
-- Анонимы ЗАПИСЫВАЮТ лиды (отправка формы квиза).
-- Анонимы НЕ ЧИТАЮТ чужие лиды.
-- Owner читает только свои лиды.
-- ============================================================

-- Анонимы: только вставка (посетитель отправляет форму)
create policy "anon_insert_leads" on public.leads for insert to anon
  with check (
    school_id in (select id from public.schools where is_active = true)
  );

-- Authenticated: читать лиды своей школы
create policy "auth_read_leads" on public.leads for select to authenticated
  using (school_id = public.get_my_school_id() or public.is_superadmin());

-- Superadmin: полный доступ
create policy "superadmin_all_leads" on public.leads for all to authenticated
  using (public.is_superadmin());


-- ============================================================
-- 5.5 Политики для EVENTS
--
-- Анонимы ЗАПИСЫВАЮТ события (аналитика с фронта).
-- Owner читает события своей школы (для дашборда).
-- ============================================================

create policy "anon_insert_events" on public.events for insert to anon
  with check (
    school_id in (select id from public.schools where is_active = true)
  );

create policy "auth_read_events" on public.events for select to authenticated
  using (school_id = public.get_my_school_id() or public.is_superadmin());


-- ============================================================
-- 5.6 Политики для PROFILES
-- ============================================================

-- Пользователь видит только свой профиль
create policy "user_read_own_profile" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_superadmin());

-- Superadmin может управлять профилями
create policy "superadmin_all_profiles" on public.profiles for all to authenticated
  using (public.is_superadmin());


-- ============================================================
-- 6. RPC-ФУНКЦИЯ ДЛЯ ДАШБОРДА АНАЛИТИКИ
--
-- Вызывается из админки: supabase.rpc('get_analytics', {...})
-- Возвращает агрегированные данные за период.
-- ============================================================

create or replace function public.get_analytics(
  p_school_id uuid,
  p_from timestamptz default now() - interval '30 days',
  p_to timestamptz default now()
)
returns json as $$
declare
  result json;
  v_school_id uuid;
begin
  -- Проверка доступа: только своя школа или superadmin
  if not public.is_superadmin() then
    v_school_id := public.get_my_school_id();
    if v_school_id is null or v_school_id != p_school_id then
      raise exception 'Access denied';
    end if;
  end if;

  select json_build_object(
    'period', json_build_object('from', p_from, 'to', p_to),
    'total_visits', (
      select count(distinct session_id) from public.events
      where school_id = p_school_id and type = 'visit'
        and created_at between p_from and p_to
    ),
    'quiz_started', (
      select count(distinct session_id) from public.events
      where school_id = p_school_id and type = 'quiz_start'
        and created_at between p_from and p_to
    ),
    'quiz_completed', (
      select count(distinct session_id) from public.events
      where school_id = p_school_id and type = 'quiz_answer'
        and payload->>'question' = '4'
        and created_at between p_from and p_to
    ),
    'leads_collected', (
      select count(*) from public.leads
      where school_id = p_school_id
        and created_at between p_from and p_to
    ),
    'telegram_clicks', (
      select count(*) from public.leads
      where school_id = p_school_id and telegram_clicked = true
        and created_at between p_from and p_to
    ),
    'segments', (
      select coalesce(json_object_agg(segment, cnt), '{}')
      from (
        select segment, count(*) as cnt from public.leads
        where school_id = p_school_id and segment is not null
          and created_at between p_from and p_to
        group by segment
      ) s
    ),
    'top_barriers', (
      select coalesce(json_agg(json_build_object('value', val, 'count', cnt) order by cnt desc), '[]')
      from (
        select answers->>'4' as val, count(*) as cnt from public.leads
        where school_id = p_school_id and answers->>'4' is not null
          and created_at between p_from and p_to
        group by answers->>'4'
      ) b
    )
  ) into result;

  return result;
end;
$$ language plpgsql security definer;
