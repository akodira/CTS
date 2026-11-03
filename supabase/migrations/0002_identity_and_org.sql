-- CTS migration 0002
-- Identity, customer organizations, departments and teams.

begin;

create table public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  email          text not null check (position('@' in email) > 1),
  full_name      text not null check (char_length(full_name) between 1 and 120),
  phone          text,
  locale         text not null default 'en' check (locale in ('en', 'ar')),
  account_status text not null default 'active'
                 check (account_status in ('active', 'suspended', 'disabled')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index profiles_email_lower_key on public.profiles (lower(email));

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create table public.roles (
  code     text primary key,
  name_en  text not null,
  name_ar  text not null,
  description_en text,
  description_ar text
);

create table public.user_roles (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role_code  text not null references public.roles (code),
  granted_by uuid references public.profiles (id),
  granted_at timestamptz not null default now(),
  primary key (user_id, role_code)
);

create index user_roles_role_idx on public.user_roles (role_code);

create table public.organizations (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.customer_profiles (
  user_id         uuid primary key references public.profiles (id) on delete cascade,
  organization_id uuid references public.organizations (id),
  job_title       text,
  created_at      timestamptz not null default now()
);

create table public.departments (
  id             uuid primary key default gen_random_uuid(),
  name_en        text not null,
  name_ar        text not null,
  description_en text,
  description_ar text,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

create table public.teams (
  id            uuid primary key default gen_random_uuid(),
  department_id uuid references public.departments (id) on delete set null,
  code          text not null unique,
  name_en       text not null,
  name_ar       text not null,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

create table public.team_members (
  team_id   uuid not null references public.teams (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  team_role text not null check (team_role in ('leader', 'agent')),
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create index team_members_user_idx on public.team_members (user_id) where is_active;

create table public.user_invitations (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  role_code   text not null references public.roles (code),
  team_id     uuid references public.teams (id) on delete set null,
  invited_by  uuid references public.profiles (id),
  token_hash  text not null unique,
  expires_at  timestamptz not null,
  accepted_at timestamptz,
  created_at  timestamptz not null default now()
);

create unique index user_invitations_pending_email_key
  on public.user_invitations (lower(email))
  where accepted_at is null;

-- Every new Auth user starts as a customer. Staff accounts are provisioned
-- by an administrator and converted with the set_user_roles RPC (Phase 2).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_full_name text;
  v_locale text;
begin
  v_full_name := left(
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      split_part(new.email, '@', 1),
      'Customer'
    ),
    120
  );

  v_locale := case
    when new.raw_user_meta_data ->> 'locale' in ('en', 'ar')
      then new.raw_user_meta_data ->> 'locale'
    else 'en'
  end;

  insert into public.profiles (id, email, full_name, locale)
  values (new.id, new.email, v_full_name, v_locale)
  on conflict (id) do nothing;

  insert into public.user_roles (user_id, role_code)
  values (new.id, 'customer')
  on conflict (user_id, role_code) do nothing;

  insert into public.customer_profiles (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.handle_user_email_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set email = new.email,
         updated_at = now()
   where id = new.id;

  return new;
end;
$$;

revoke all on function public.handle_user_email_updated() from public;

create trigger on_auth_user_email_updated
after update of email on auth.users
for each row
when (old.email is distinct from new.email)
execute function public.handle_user_email_updated();

commit;
