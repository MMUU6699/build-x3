begin;

create table if not exists public.conversations (
  id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (id, user_id),
  constraint conversations_title_length check (char_length(title) <= 1000)
);

create table if not exists public.messages (
  id uuid not null,
  conversation_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (id, user_id),
  constraint messages_conversation_owner_fk
    foreign key (conversation_id, user_id)
    references public.conversations (id, user_id) on delete cascade,
  constraint messages_role_value check ((data ->> 'role') in ('user', 'assistant', 'system', 'tool'))
);

create index if not exists conversations_user_updated_idx
  on public.conversations (user_id, updated_at desc);
create index if not exists messages_user_conversation_created_idx
  on public.messages (user_id, conversation_id, created_at);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

drop policy if exists conversations_select_own on public.conversations;
create policy conversations_select_own on public.conversations
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists conversations_insert_own on public.conversations;
create policy conversations_insert_own on public.conversations
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists conversations_update_own on public.conversations;
create policy conversations_update_own on public.conversations
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists conversations_delete_own on public.conversations;
create policy conversations_delete_own on public.conversations
  for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists messages_select_own on public.messages;
create policy messages_select_own on public.messages
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists messages_insert_own on public.messages;
create policy messages_insert_own on public.messages
  for insert to authenticated with check (
    (select auth.uid()) = user_id and exists (
      select 1 from public.conversations c
      where c.id = conversation_id and c.user_id = (select auth.uid())
    )
  );
drop policy if exists messages_update_own on public.messages;
create policy messages_update_own on public.messages
  for update to authenticated using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id and exists (
      select 1 from public.conversations c
      where c.id = conversation_id and c.user_id = (select auth.uid())
    )
  );
drop policy if exists messages_delete_own on public.messages;
create policy messages_delete_own on public.messages
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on table public.conversations, public.messages from anon;
grant select, insert, update, delete on table public.conversations, public.messages to authenticated;

commit;
