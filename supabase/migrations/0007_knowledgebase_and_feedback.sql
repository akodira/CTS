-- CTS migration 0007
-- Knowledgebase, article feedback and customer satisfaction.

begin;

create table public.kb_categories (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid references public.kb_categories (id) on delete restrict,
  slug       text not null unique,
  name_en    text not null,
  name_ar    text not null,
  sort_order int not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create index kb_categories_parent_idx on public.kb_categories (parent_id);

create table public.kb_articles (
  id            uuid primary key default gen_random_uuid(),
  category_id   uuid references public.kb_categories (id) on delete set null,
  slug          text not null unique,
  title_en      text not null,
  title_ar      text not null,
  summary_en    text,
  summary_ar    text,
  body_en       text not null,
  body_ar       text not null,
  status        text not null default 'draft'
                check (status in ('draft', 'published', 'archived')),
  visibility    text not null default 'public'
                check (visibility in ('public', 'authenticated', 'staff')),
  author_id     uuid references public.profiles (id) on delete set null,
  published_at  timestamptz,
  view_count    bigint not null default 0 check (view_count >= 0),
  search_vector tsvector generated always as (
                  setweight(to_tsvector('simple', coalesce(title_en, '') || ' ' || coalesce(title_ar, '')), 'A') ||
                  setweight(to_tsvector('simple', coalesce(body_en, '') || ' ' || coalesce(body_ar, '')), 'B')
                ) stored,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index kb_articles_category_idx on public.kb_articles (category_id, status);
create index kb_articles_status_idx on public.kb_articles (status, visibility);
create index kb_articles_search_idx on public.kb_articles using gin (search_vector);

create trigger kb_articles_set_updated_at
before update on public.kb_articles
for each row execute function private.set_updated_at();

create table public.kb_article_feedback (
  id         uuid primary key default gen_random_uuid(),
  article_id uuid not null references public.kb_articles (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  is_helpful boolean not null,
  comment    text,
  created_at timestamptz not null default now(),
  unique (article_id, user_id)
);

create table public.kb_article_relations (
  article_id         uuid not null references public.kb_articles (id) on delete cascade,
  related_article_id uuid not null references public.kb_articles (id) on delete cascade,
  primary key (article_id, related_article_id),
  check (article_id <> related_article_id)
);

create table public.customer_feedback (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null unique references public.tickets (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  rating     smallint not null check (rating between 1 and 5),
  comment    text check (comment is null or char_length(comment) <= 2000),
  created_at timestamptz not null default now()
);

create index customer_feedback_rating_idx on public.customer_feedback (rating, created_at);

commit;
