begin;

alter table public.conversations
  add column if not exists mode text not null default 'chat';

create index if not exists conversations_user_mode_updated_idx
  on public.conversations (user_id, mode, updated_at desc);

commit;
