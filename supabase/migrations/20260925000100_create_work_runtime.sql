begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (
    display_name is null or char_length(display_name) <= 120
  ),
  constraint profiles_avatar_url_length check (
    avatar_url is null or char_length(avatar_url) <= 2048
  )
);

create table if not exists public.work_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  prompt text not null,
  model text not null,
  reasoning_effort text not null default 'high',
  status text not null default 'queued',
  sandbox_id text,
  result jsonb,
  error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint work_runs_prompt_length check (
    char_length(prompt) between 1 and 4000000
  ),
  constraint work_runs_model_length check (
    char_length(model) between 1 and 200
  ),
  constraint work_runs_reasoning_effort_value check (
    reasoning_effort in ('none', 'low', 'medium', 'high', 'standard')
  ),
  constraint work_runs_status_value check (
    status in ('queued', 'running', 'completed', 'failed', 'cancelled')
  ),
  constraint work_runs_sandbox_id_length check (
    sandbox_id is null or char_length(sandbox_id) <= 255
  ),
  constraint work_runs_error_length check (
    error is null or char_length(error) <= 1000
  )
);

create table if not exists public.work_events (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.work_runs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  sequence bigint not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint work_events_sequence_positive check (sequence > 0),
  constraint work_events_type_length check (
    char_length(event_type) between 1 and 80
  ),
  constraint work_events_run_sequence_unique unique (run_id, sequence)
);

create index if not exists work_runs_user_created_idx
  on public.work_runs (user_id, created_at desc);
create index if not exists work_runs_user_status_idx
  on public.work_runs (user_id, status);
create index if not exists work_events_run_sequence_idx
  on public.work_events (run_id, sequence);
create index if not exists work_events_user_created_idx
  on public.work_events (user_id, created_at desc);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists work_runs_set_updated_at on public.work_runs;
create trigger work_runs_set_updated_at
before update on public.work_runs
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', '')
    ),
    coalesce(
      nullif(new.raw_user_meta_data ->> 'avatar_url', ''),
      nullif(new.raw_user_meta_data ->> 'picture', '')
    )
  )
  on conflict (id) do update
  set display_name = coalesce(excluded.display_name, profiles.display_name),
      avatar_url = coalesce(excluded.avatar_url, profiles.avatar_url),
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of raw_user_meta_data on auth.users
for each row execute function public.handle_new_user_profile();

insert into public.profiles (id, display_name, avatar_url)
select
  users.id,
  coalesce(
    nullif(users.raw_user_meta_data ->> 'display_name', ''),
    nullif(users.raw_user_meta_data ->> 'full_name', ''),
    nullif(users.raw_user_meta_data ->> 'name', '')
  ),
  coalesce(
    nullif(users.raw_user_meta_data ->> 'avatar_url', ''),
    nullif(users.raw_user_meta_data ->> 'picture', '')
  )
from auth.users
on conflict (id) do nothing;

alter table public.profiles enable row level security;
alter table public.work_runs enable row level security;
alter table public.work_events enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
on public.profiles for select
to authenticated
using ((select auth.uid()) = id);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
on public.profiles for insert
to authenticated
with check ((select auth.uid()) = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists work_runs_select_own on public.work_runs;
create policy work_runs_select_own
on public.work_runs for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists work_events_select_own on public.work_events;
create policy work_events_select_own
on public.work_events for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.profiles from anon;
revoke all on table public.work_runs from anon;
revoke all on table public.work_events from anon;

grant select, insert, update on table public.profiles to authenticated;
grant select on table public.work_runs to authenticated;
grant select on table public.work_events to authenticated;

alter table public.profiles replica identity full;
alter table public.work_runs replica identity full;
alter table public.work_events replica identity full;

do $$
declare
  table_name text;
begin
  foreach table_name in array array['profiles', 'work_runs', 'work_events']
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end
$$;

commit;
