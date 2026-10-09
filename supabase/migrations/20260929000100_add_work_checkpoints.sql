begin;

alter table public.work_runs
  add column if not exists checkpoint jsonb not null default '{}'::jsonb;

alter table public.work_runs
  drop constraint if exists work_runs_status_value;

alter table public.work_runs
  add constraint work_runs_status_value check (
    status in ('queued', 'running', 'waiting', 'completed', 'failed', 'cancelled')
  );

create index if not exists work_runs_waiting_idx
  on public.work_runs (status, updated_at)
  where status = 'waiting';

comment on column public.work_runs.checkpoint is
  'Durable Plan-Act checkpoint: plan, current step, tool history cursor, and waiting metadata.';

commit;
