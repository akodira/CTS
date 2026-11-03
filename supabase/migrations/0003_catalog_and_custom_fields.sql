-- CTS migration 0003
-- Categories (with one optional level of subcategory), priorities and
-- administrator-defined custom fields.

begin;

create table public.ticket_categories (
  id              uuid primary key default gen_random_uuid(),
  parent_id       uuid references public.ticket_categories (id) on delete restrict,
  code            text not null unique,
  name_en         text not null,
  name_ar         text not null,
  description_en  text,
  description_ar  text,
  default_team_id uuid references public.teams (id) on delete set null,
  is_active       boolean not null default true,
  sort_order      int not null default 0,
  created_at      timestamptz not null default now()
);

create index ticket_categories_parent_idx on public.ticket_categories (parent_id);
create index ticket_categories_active_idx on public.ticket_categories (is_active, sort_order);

create or replace function private.check_category_depth()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent_id uuid;
begin
  if new.parent_id is null then
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception 'CATEGORY_CANNOT_PARENT_ITSELF' using errcode = '23514';
  end if;

  select parent_id into v_parent_id
    from public.ticket_categories
   where id = new.parent_id;

  if not found then
    raise exception 'PARENT_CATEGORY_NOT_FOUND' using errcode = '23503';
  end if;

  if v_parent_id is not null then
    raise exception 'CATEGORY_DEPTH_EXCEEDED' using errcode = '23514';
  end if;

  if exists (
    select 1 from public.ticket_categories where parent_id = new.id
  ) then
    raise exception 'CATEGORY_HAS_CHILDREN' using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.check_category_depth() from public;

create trigger ticket_categories_check_depth
before insert or update of parent_id on public.ticket_categories
for each row execute function private.check_category_depth();

create table public.priorities (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  name_en    text not null,
  name_ar    text not null,
  weight     int not null check (weight between 1 and 100),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.ticket_custom_fields (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid references public.ticket_categories (id) on delete cascade,
  code         text not null,
  label_en     text not null,
  label_ar     text not null,
  help_en      text,
  help_ar      text,
  field_type   text not null check (field_type in (
                 'text', 'long_text', 'number', 'date', 'dropdown',
                 'multi_select', 'checkbox', 'radio', 'file'
               )),
  is_required  boolean not null default false,
  is_active    boolean not null default true,
  options      jsonb,
  validation   jsonb,
  visibility   text not null default 'both'
               check (visibility in ('both', 'customer', 'staff')),
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  unique nulls not distinct (category_id, code)
);

create index ticket_custom_fields_category_idx
  on public.ticket_custom_fields (category_id, sort_order)
  where is_active;

commit;
